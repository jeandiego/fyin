// Package sync copia os dados de um item da Pluggy para o Postgres.
package sync

import (
	"context"
	"encoding/json"
	"fmt"

	"fyin/internal/pluggy"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// num devolve "" para número ausente; o SQL converte com NULLIF(...)::numeric.
func num(n json.Number) string { return n.String() }

type Result struct {
	Accounts     int `json:"accounts"`
	Bills        int `json:"bills"`
	Transactions int `json:"transactions"`
	Loans        int `json:"loans"`
	Investments  int `json:"investments"`
}

// API é a parte da Pluggy usada pelo sync; *pluggy.Client a satisfaz.
type API interface {
	Item(ctx context.Context, id string) (pluggy.Item, error)
	Accounts(ctx context.Context, itemID string) ([]pluggy.Account, error)
	Bills(ctx context.Context, accountID string) ([]pluggy.Bill, error)
	Transactions(ctx context.Context, accountID string) ([]pluggy.Transaction, error)
	Loans(ctx context.Context, itemID string) ([]pluggy.Loan, error)
	Investments(ctx context.Context, itemID string) ([]pluggy.Investment, error)
}

// Item busca tudo na API primeiro e só então grava, numa única transação.
// Transações e faturas de cada conta são substituídas por inteiro: a Pluggy recria
// transações de cartão com novo id perto do fechamento da fatura, então upsert por id duplicaria.
// shortcut: a substituição apaga edições locais em transactions; guardar overrides em tabela própria (chave de dedup) antes de permitir recategorização manual.
func Item(ctx context.Context, pool *pgxpool.Pool, api API, owner, itemID string) (Result, error) {
	var res Result
	item, err := api.Item(ctx, itemID)
	if err != nil {
		return res, fmt.Errorf("item: %w", err)
	}
	accounts, err := api.Accounts(ctx, itemID)
	if err != nil {
		return res, fmt.Errorf("accounts: %w", err)
	}
	loans, err := api.Loans(ctx, itemID)
	if err != nil {
		return res, fmt.Errorf("loans: %w", err)
	}
	investments, err := api.Investments(ctx, itemID)
	if err != nil {
		return res, fmt.Errorf("investments: %w", err)
	}
	type fetched struct {
		bills []pluggy.Bill
		txs   []pluggy.Transaction
	}
	data := make(map[string]fetched, len(accounts))
	for _, a := range accounts {
		var f fetched
		if f.txs, err = api.Transactions(ctx, a.ID); err != nil {
			return res, fmt.Errorf("transactions %s: %w", a.ID, err)
		}
		if a.Type == "CREDIT" {
			if f.bills, err = api.Bills(ctx, a.ID); err != nil {
				return res, fmt.Errorf("bills %s: %w", a.ID, err)
			}
		}
		data[a.ID] = f
	}

	tx, err := pool.Begin(ctx)
	if err != nil {
		return res, err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO items (id, owner, connector, status, consent_expires_at, synced_at)
		VALUES ($1::uuid, $2, $3, $4, NULLIF($5::text,'')::timestamptz, now())
		ON CONFLICT (id) DO UPDATE SET owner=$2, connector=$3, status=$4, consent_expires_at=NULLIF($5::text,'')::timestamptz, synced_at=now()`,
		item.ID, owner, item.Connector.Name, item.Status, item.ConsentExpiresAt)
	if err != nil {
		return res, err
	}

	for _, a := range accounts {
		accountRaw, err := redact(a.Raw)
		if err != nil {
			return res, fmt.Errorf("redact account %s: %w", a.ID, err)
		}
		limit := ""
		if a.CreditData != nil {
			limit = num(a.CreditData.CreditLimit)
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO accounts (id, item_id, type, subtype, name, balance, credit_limit, raw)
			VALUES ($1::uuid, $2::uuid, $3, $4, $5, NULLIF($6::text,'')::numeric, NULLIF($7::text,'')::numeric, $8::jsonb)
			ON CONFLICT (id) DO UPDATE SET type=$3, subtype=$4, name=$5, balance=NULLIF($6::text,'')::numeric, credit_limit=NULLIF($7::text,'')::numeric, raw=$8::jsonb`,
			a.ID, itemID, a.Type, a.Subtype, a.Name, num(a.Balance), limit, string(accountRaw))
		if err != nil {
			return res, err
		}
		res.Accounts++
		if a.Type == "BANK" {
			_, err = tx.Exec(ctx, `
				INSERT INTO balance_snapshots (account_id, taken_at, balance)
				SELECT $1::uuid, now(), NULLIF($2::text,'')::numeric WHERE $2::text <> ''`, a.ID, num(a.Balance))
			if err != nil {
				return res, err
			}
		}

		f := data[a.ID]
		if _, err = tx.Exec(ctx, `DELETE FROM bills WHERE account_id=$1::uuid`, a.ID); err != nil {
			return res, err
		}
		if _, err = tx.Exec(ctx, `DELETE FROM transactions WHERE account_id=$1::uuid`, a.ID); err != nil {
			return res, err
		}

		batch := &pgx.Batch{}
		for _, b := range f.bills {
			batch.Queue(`
				INSERT INTO bills (id, account_id, due_date, closing_date, total, minimum, raw)
				VALUES ($1::uuid, $2::uuid, left($3::text,10)::date, NULLIF(left($4::text,10),'')::date, $5::text::numeric, NULLIF($6::text,'')::numeric, $7::jsonb)`,
				b.ID, a.ID, b.DueDate, b.BillClosingDate, num(b.TotalAmount), num(b.MinimumPaymentAmount), string(b.Raw))
		}
		for _, t := range f.txs {
			txRaw, err := redact(t.Raw)
			if err != nil {
				return res, fmt.Errorf("redact transaction %s: %w", t.ID, err)
			}
			// Grava em reais; a moeda e o valor originais continuam em raw.
			amount := t.Amount
			if t.AmountInAccountCurrency != "" {
				amount = t.AmountInAccountCurrency
			}
			var billID, forecast string
			var inst, total *int
			if cc := t.CreditCard; cc != nil {
				billID, forecast, inst, total = cc.BillID, cc.BillForecastDate, cc.InstallmentNumber, cc.TotalInstallments
			}
			batch.Queue(`
				INSERT INTO transactions (id, account_id, date, description, amount, type, status, category, bill_id, bill_forecast, installment_number, total_installments, raw)
				VALUES ($1::uuid, $2::uuid, $3::timestamptz, $4, $5::text::numeric, $6, $7, NULLIF($8::text,''), NULLIF($9::text,'')::uuid, NULLIF($10::text,''), $11, $12, $13::jsonb)`,
				t.ID, a.ID, t.Date, t.Description, num(amount), t.Type, t.Status, t.Category, billID, forecast, inst, total, string(txRaw))
		}
		br := tx.SendBatch(ctx, batch)
		for i := 0; i < batch.Len(); i++ {
			if _, err = br.Exec(); err != nil {
				br.Close()
				return res, err
			}
		}
		if err = br.Close(); err != nil {
			return res, err
		}
		res.Bills += len(f.bills)
		res.Transactions += len(f.txs)
	}

	// Empréstimos e investimentos também são substituídos por inteiro: o que sumiu da Pluggy foi quitado/resgatado.
	if _, err = tx.Exec(ctx, `DELETE FROM loans WHERE item_id=$1::uuid`, itemID); err != nil {
		return res, err
	}
	if _, err = tx.Exec(ctx, `DELETE FROM investments WHERE item_id=$1::uuid`, itemID); err != nil {
		return res, err
	}
	for _, l := range loans {
		raw, err := redact(l.Raw)
		if err != nil {
			return res, fmt.Errorf("redact loan %s: %w", l.ID, err)
		}
		outstanding := ""
		if l.Payments != nil {
			outstanding = num(l.Payments.ContractOutstandingBalance)
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO loans (id, item_id, product_name, outstanding_balance, raw)
			VALUES ($1::uuid, $2::uuid, $3, NULLIF($4::text,'')::numeric, $5::jsonb)`,
			l.ID, itemID, l.ProductName, outstanding, string(raw))
		if err != nil {
			return res, err
		}
	}
	for _, i := range investments {
		raw, err := redact(i.Raw)
		if err != nil {
			return res, fmt.Errorf("redact investment %s: %w", i.ID, err)
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO investments (id, item_id, type, name, status, balance, raw)
			VALUES ($1::uuid, $2::uuid, $3, $4, NULLIF($5::text,''), $6::text::numeric, $7::jsonb)`,
			i.ID, itemID, i.Type, i.Name, i.Status, num(i.Balance), string(raw))
		if err != nil {
			return res, err
		}
	}
	res.Loans, res.Investments = len(loans), len(investments)
	return res, tx.Commit(ctx)
}

type Divergence struct {
	Kind, Account, Day, Reported, Calculated, Difference string
}

// Divergences lista onde o saldo ou a fatura informados não batem com as transações (view divergences).
func Divergences(ctx context.Context, pool *pgxpool.Pool) ([]Divergence, error) {
	rows, err := pool.Query(ctx, `
		SELECT kind, account_name, day::text, reported::text, calculated::text, difference::text
		FROM divergences ORDER BY day DESC, kind`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(r pgx.CollectableRow) (Divergence, error) {
		var d Divergence
		return d, r.Scan(&d.Kind, &d.Account, &d.Day, &d.Reported, &d.Calculated, &d.Difference)
	})
}
