-- Tratar divergências: marcar como explicada uma que já foi entendida (ex.: compra cancelada que o
-- banco continua listando), para ela sair da lista sem esconder as novas.
CREATE TABLE divergence_acks (
  kind        text NOT NULL,               -- saldo | fatura
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day         date NOT NULL,
  note        text NOT NULL,
  PRIMARY KEY (kind, account_id, day)
);

-- A checagem de fatura passa a usar os movimentos do cartão em vez do livro de gastos: excluir algo
-- do gasto (ex.: compra cancelada) não deve fazer a fatura parecer errada.
CREATE OR REPLACE VIEW divergences AS
WITH card_moves AS (
  -- Tudo que o cartão lançou, menos os pagamentos: é o que compõe a fatura, mesmo o que não é gasto.
  SELECT t.account_id, t.bill_id, t.amount, (t.date AT TIME ZONE 'America/Sao_Paulo')::date AS day
  FROM transactions t JOIN accounts a ON a.id = t.account_id
  WHERE a.type = 'CREDIT'
    AND NOT EXISTS (SELECT 1 FROM spending_exclusions e WHERE e.account_type = 'CREDIT' AND e.category = t.category)
), snaps AS (
  SELECT account_id, taken_at, balance,
         lag(taken_at) OVER w AS prev_at, lag(balance) OVER w AS prev_balance
  FROM balance_snapshots WINDOW w AS (PARTITION BY account_id ORDER BY taken_at)
), cycles AS (
  SELECT id, account_id, closing_date, total,
         lag(closing_date) OVER (PARTITION BY account_id ORDER BY closing_date) AS prev_closing
  FROM bills WHERE closing_date IS NOT NULL
), bill_sums AS (
  SELECT c.account_id, c.closing_date, c.total, x.calculated
  FROM cycles c CROSS JOIN LATERAL (VALUES
    ((SELECT coalesce(sum(m.amount), 0) FROM card_moves m
      WHERE m.account_id = c.account_id AND m.day > c.prev_closing AND m.day <= c.closing_date)),
    ((SELECT coalesce(sum(m.amount), 0) FROM card_moves m
      WHERE m.account_id = c.account_id AND m.day >= c.prev_closing AND m.day < c.closing_date)),
    ((SELECT coalesce(sum(m.amount), 0) FROM card_moves m WHERE m.bill_id = c.id))
  ) AS x(calculated)
  WHERE c.prev_closing IS NOT NULL
), checks AS (
  SELECT 'saldo' AS kind, s.account_id, (s.taken_at AT TIME ZONE 'America/Sao_Paulo')::date AS day,
         s.balance AS reported,
         s.prev_balance + coalesce((SELECT sum(t.amount) FROM transactions t
           WHERE t.account_id = s.account_id AND t.date > s.prev_at AND t.date <= s.taken_at), 0) AS calculated
  FROM snaps s WHERE s.prev_at IS NOT NULL
  UNION ALL
  (SELECT DISTINCT ON (account_id, closing_date) 'fatura', account_id, closing_date, total, calculated
   FROM bill_sums ORDER BY account_id, closing_date, abs(total - calculated))
)
SELECT checks.*, a.name AS account_name, checks.reported - checks.calculated AS difference
FROM checks JOIN accounts a ON a.id = checks.account_id
-- Tolerância de 5 centavos: a Pluggy manda totais com 4 casas (2777.2639) e câmbio arredondado por compra.
WHERE abs(checks.reported - checks.calculated) > 0.05
  AND NOT EXISTS (SELECT 1 FROM divergence_acks k
                  WHERE k.kind = checks.kind AND k.account_id = checks.account_id AND k.day = checks.day);
