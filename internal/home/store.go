package home

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store lê os números da home. Valores saem como texto decimal do Postgres; nada passa por float.
type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// figures preenche os campos de s que vêm do banco, para o mês [start, end).
// O saldo das contas é o de `end`: parte do snapshot mais próximo e desfaz/aplica as transações até lá.
// Valores em USD entram convertidos pela cotação mais recente (to_brl).
// Investido = investimentos + ativos manuais + caixinhas/reservas das contas (bankData.reservedBalances, fora do saldo).
// Empréstimos e investimentos são sempre os atuais (a Pluggy não dá histórico).
func (st *Store) figures(ctx context.Context, start, end time.Time, s *Summary) error {
	return st.pool.QueryRow(ctx, `
		WITH bank AS (
			SELECT to_brl(coalesce(
				(SELECT sn.balance - coalesce((SELECT sum(t.amount) FROM transactions t
					WHERE t.account_id = a.id AND t.date >= $2 AND t.date <= sn.taken_at), 0)
				 FROM balance_snapshots sn WHERE sn.account_id = a.id AND sn.taken_at >= $2
				 ORDER BY sn.taken_at LIMIT 1),
				(SELECT sn.balance + coalesce((SELECT sum(t.amount) FROM transactions t
					WHERE t.account_id = a.id AND t.date > sn.taken_at AND t.date < $2), 0)
				 FROM balance_snapshots sn WHERE sn.account_id = a.id AND sn.taken_at < $2
				 ORDER BY sn.taken_at DESC LIMIT 1)
			), a.raw->>'currencyCode') AS balance
			FROM accounts a WHERE a.type = 'BANK'
		), last_bills AS (
			-- última fatura fechada até o fim do mês, por cartão
			SELECT DISTINCT ON (b.account_id) b.total, b.closing_date, b.due_date
			FROM bills b WHERE b.closing_date < ($2 AT TIME ZONE 'America/Sao_Paulo')::date
			ORDER BY b.account_id, b.closing_date DESC
		)
		SELECT
			(SELECT max(synced_at) FROM items),
			(SELECT coalesce(sum(balance), 0)::numeric(14,2)::text FROM bank),
			(SELECT (coalesce((SELECT sum(to_brl(balance, raw->>'currencyCode')) FROM investments WHERE status IS DISTINCT FROM 'TOTAL_WITHDRAWAL'), 0)
			       + coalesce((SELECT sum(value) FROM manual_assets), 0)
			       + coalesce((SELECT sum(value) FROM b3_holdings WHERE counts AND NOT duplicate), 0)
			       + coalesce((SELECT sum(to_brl((amt->>'amount')::numeric, amt->>'currencyCode')) FROM accounts a,
			           jsonb_path_query(a.raw, '$.bankData.reservedBalances[*].availableAmounts[*]') amt
			           WHERE a.type = 'BANK'), 0))::numeric(14,2)::text),
			(SELECT coalesce(sum(amount), 0)::numeric(14,2)::text FROM spending WHERE date >= $1 AND date < $2),
			(SELECT coalesce(sum(total), 0)::numeric(14,2)::text FROM last_bills),
			(SELECT max(closing_date)::text FROM last_bills),
			(SELECT max(due_date)::text FROM last_bills),
			(SELECT coalesce(sum(outstanding_balance), 0)::numeric(14,2)::text FROM loans),
			-- shortcut: início da conexão = 1ª transação do item; trocar pela data de criação do item quando a guardarmos.
			(SELECT max(first_day)::text FROM (
				SELECT min((t.date AT TIME ZONE 'America/Sao_Paulo')::date) AS first_day
				FROM transactions t JOIN accounts a ON a.id = t.account_id GROUP BY a.item_id) f
			 WHERE first_day > ($1 AT TIME ZONE 'America/Sao_Paulo')::date
			   AND first_day < ($2 AT TIME ZONE 'America/Sao_Paulo')::date)`,
		start, end,
	).Scan(&s.SyncedAt, &s.Balance, &s.Invested, &s.Spending.Spent,
		&s.Card.Total, &s.Card.ClosingDate, &s.Card.DueDate, &s.Loans.Total, &s.Spending.Since)
}

// currentCard troca o card do mês atual pelas faturas atuais (as mesmas do modal de cartões, card_bills).
// closingDate só vem quando todas estão abertas; senão dueDate é o da mais próxima com saldo.
func (st *Store) currentCard(ctx context.Context, now time.Time, s *Summary) error {
	return st.pool.QueryRow(ctx, `
		SELECT coalesce(sum(total), 0)::numeric(14,2)::text,
			CASE WHEN bool_and(status = 'open') THEN min(closing_date)::text END,
			coalesce(min(due_date) FILTER (WHERE status <> 'open'), min(due_date))::text
		FROM card_bills(($1::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date) WHERE is_current`, now,
	).Scan(&s.Card.Total, &s.Card.ClosingDate, &s.Card.DueDate)
}
