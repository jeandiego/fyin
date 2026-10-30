// Package investments detalha o patrimônio investido da home: contas (instituição × titular), grupos e posições.
package investments

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Portfolio struct {
	Total       string    `json:"total"`                 // igual ao "invested" da home
	UsdRate     *string   `json:"usdRate,omitempty"`     // PTAX usada nas conversões; ausente se ainda não há cotação
	UsdRateDate *string   `json:"usdRateDate,omitempty"` // YYYY-MM-DD da cotação
	Accounts    []Account `json:"accounts"`
}

// Account é um item da Pluggy (instituição de um titular), a posição de um dono na B3 ("b3-<dono>") ou um ativo manual.
type Account struct {
	ID          string  `json:"id"`
	Institution string  `json:"institution"` // conector da Pluggy; no ativo manual, o nome dele
	Owner       string  `json:"owner"`
	Manual      bool    `json:"manual"`
	Total       string  `json:"total"`
	TotalUsd    *string `json:"totalUsd,omitempty"` // soma das posições em dólar, na moeda original
	Groups      []Group `json:"groups"`
}

// Group junta as posições de um produto: subtipo da Pluggy (CDB, LCI, STOCK...), tipo se não houver subtipo,
// RESERVE para caixinhas, MANUAL para ativo manual e o tipoProduto cru da B3 (TesouroDireto, Acao, Futuro...).
type Group struct {
	Kind         string     `json:"kind"`
	Label        *string    `json:"label,omitempty"`        // rótulo da própria B3, para tipos que o app não conhece
	OutsideTotal bool       `json:"outsideTotal,omitempty"` // derivativo da B3: aparece, mas não soma em nenhum total
	Total        string     `json:"total"`
	TotalUsd     *string    `json:"totalUsd,omitempty"`
	Positions    []Position `json:"positions"`
}

// Position traz o que a Pluggy informa; o app decide o que mostrar por tipo.
type Position struct {
	Name      string  `json:"name"`
	Balance   string  `json:"balance"`         // valor atual em reais (convertido pela PTAX se em USD), o que soma no total
	Original  string  `json:"balanceOriginal"` // valor na moeda da posição; igual a balance em reais
	Currency  string  `json:"currency"`
	Code      *string `json:"code"`      // ticker
	Quantity  *string `json:"quantity"`  // cotas/ações
	Indexer   *string `json:"indexer"`   // CDI, IPCA, SELIC...
	Rate      *string `json:"rate"`      // % do indexador (115 = 115% do CDI)
	FixedRate *string `json:"fixedRate"` // taxa pré ao ano (IPCA + 6,5)
	DueDate   *string `json:"dueDate"`   // YYYY-MM-DD
	TaxExempt *bool   `json:"taxExempt"`
}

type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Portfolio usa as mesmas fontes do "invested" da home: investimentos não resgatados, caixinhas das contas,
// posição da B3 que a Pluggy não traz (b3_holdings.duplicate) e ativos manuais. Posições zeradas não aparecem. Ordem: conta, grupo e posição por valor, maior primeiro.
// Posições em USD são convertidas pela cotação mais recente (to_brl); outras moedas não são tratadas.
func (st *Store) Portfolio(ctx context.Context) (Portfolio, error) {
	rows, err := st.pool.Query(ctx, `
		WITH p0 AS (
			SELECT v.item_id::text AS account, i.connector AS institution, i.owner, false AS manual,
				coalesce(v.raw->>'subtype', v.type) AS kind, v.name, v.balance,
				coalesce(v.raw->>'currencyCode', 'BRL') AS currency, v.raw->>'code' AS code, v.raw->>'quantity' AS quantity,
				v.raw->>'rateType' AS indexer, v.raw->>'rate' AS rate, v.raw->>'fixedAnnualRate' AS fixed_rate,
				((v.raw->>'dueDate')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date::text AS due_date,
				(v.raw->>'taxExempt')::boolean AS tax_exempt, true AS counts, NULL AS label
			FROM investments v JOIN items i ON i.id = v.item_id
			WHERE v.status IS DISTINCT FROM 'TOTAL_WITHDRAWAL'
			UNION ALL
			SELECT a.item_id::text, i.connector, i.owner, false, 'RESERVE', coalesce(r->>'name', 'Reserva'),
				(amt->>'amount')::numeric(14,2), coalesce(amt->>'currencyCode', 'BRL'), NULL, NULL,
				amt#>>'{remuneration,indexer}',
				round((amt#>>'{remuneration,postFixedIndexerPercentage}')::numeric * 100, 2)::text, NULL, NULL, NULL, true, NULL
			FROM accounts a JOIN items i ON i.id = a.item_id,
				jsonb_path_query(a.raw, '$.bankData.reservedBalances[*]') r,
				jsonb_array_elements(r->'availableAmounts') amt
			WHERE a.type = 'BANK'
			UNION ALL
			SELECT 'b3-' || owner, 'B3', owner, false, product_type, name, value, 'BRL', code, quantity::text, indexer, NULL, NULL,
				due_date::text, NULL, counts, product_label
			FROM b3_holdings WHERE NOT duplicate
			UNION ALL
			SELECT 'manual-' || id, name, owner, true, 'MANUAL', name, value, 'BRL', NULL, NULL, NULL, NULL, NULL, NULL, NULL, true, NULL
			FROM manual_assets
		), p AS (
			SELECT p0.*, to_brl(balance, currency) AS brl FROM p0
		), t AS (
			SELECT p.*,
				sum(brl) OVER (PARTITION BY account, kind) AS group_total,
				sum(brl) FILTER (WHERE counts) OVER (PARTITION BY account) AS account_total,
				sum(brl) FILTER (WHERE counts) OVER () AS total,
				sum(balance) FILTER (WHERE currency = 'USD') OVER (PARTITION BY account, kind) AS group_usd,
				sum(balance) FILTER (WHERE currency = 'USD') OVER (PARTITION BY account) AS account_usd
			FROM p
		)
		SELECT account, institution, owner, manual, kind, name, brl::text, balance::text, currency, code, quantity,
			indexer, rate, fixed_rate, due_date, tax_exempt, label, NOT counts,
			group_total::numeric(14,2)::text, coalesce(account_total, 0)::numeric(14,2)::text, coalesce(total, 0)::numeric(14,2)::text,
			group_usd::numeric(14,2)::text, account_usd::numeric(14,2)::text
		FROM t WHERE balance <> 0
		-- t. ordena pelos numéricos; sem ele valeriam as colunas de texto do SELECT ("200.50" > "1000.00").
		-- O que não soma (derivativo da B3) vai para o fim da conta.
		ORDER BY t.account_total DESC NULLS LAST, account, t.counts DESC, t.group_total DESC, kind, t.brl DESC, name`)
	if err != nil {
		return Portfolio{}, err
	}
	defer rows.Close()

	out := Portfolio{Total: "0.00", Accounts: []Account{}}
	for rows.Next() {
		var a Account
		var g Group
		var p Position
		if err := rows.Scan(&a.ID, &a.Institution, &a.Owner, &a.Manual, &g.Kind, &p.Name, &p.Balance, &p.Original, &p.Currency,
			&p.Code, &p.Quantity, &p.Indexer, &p.Rate, &p.FixedRate, &p.DueDate, &p.TaxExempt, &g.Label, &g.OutsideTotal,
			&g.Total, &a.Total, &out.Total, &g.TotalUsd, &a.TotalUsd); err != nil {
			return Portfolio{}, err
		}
		n := len(out.Accounts)
		if n == 0 || out.Accounts[n-1].ID != a.ID {
			out.Accounts = append(out.Accounts, a)
			n++
		}
		acc := &out.Accounts[n-1]
		if m := len(acc.Groups); m == 0 || acc.Groups[m-1].Kind != g.Kind {
			acc.Groups = append(acc.Groups, g)
		}
		last := &acc.Groups[len(acc.Groups)-1]
		last.Positions = append(last.Positions, p)
	}
	if err := rows.Err(); err != nil {
		return Portfolio{}, err
	}
	err = st.pool.QueryRow(ctx, `SELECT rate::text, day::text FROM usd_brl`).Scan(&out.UsdRate, &out.UsdRateDate)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return Portfolio{}, err
	}
	return out, nil
}
