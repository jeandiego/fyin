-- Pagamento de fatura saindo da conta não é gasto: as compras já contam no cartão.
-- Nubank marca com operationTypeAdditionalInfo = PAGAMENTO_FATURA, mas categoriza como "Transfers"
-- (que também inclui PIX de verdade), e o Mercado Pago só identifica pela descrição.

-- Padrões ILIKE de descrição que não são gasto. Ajustar aqui ao conectar outro banco.
CREATE TABLE spending_description_exclusions (
  account_type  text NOT NULL,             -- BANK | CREDIT
  pattern       text NOT NULL,             -- ILIKE, ex.: 'Pagamento de fatura%'
  reason        text NOT NULL,
  PRIMARY KEY (account_type, pattern)
);
INSERT INTO spending_description_exclusions VALUES
  ('BANK', 'Pagamento de fatura%', 'Mercado Pago não marca o pagamento da fatura; só a descrição identifica');

-- Mercado Pago: "Dinheiro reservado ..." move para reserva/investimento na própria conta.
INSERT INTO spending_exclusions VALUES
  ('BANK', 'Transfer - Internal', 'reserva/investimento dentro da própria conta (Mercado Pago)');

CREATE OR REPLACE VIEW spending AS
SELECT t.id, t.account_id, a.type AS account_type, t.date,
       (t.date AT TIME ZONE 'America/Sao_Paulo')::date AS day,
       t.description, t.category,
       CASE WHEN a.type = 'BANK' THEN -t.amount ELSE t.amount END AS amount
FROM transactions t JOIN accounts a ON a.id = t.account_id
WHERE (a.type = 'CREDIT' OR t.amount < 0)
  AND t.raw->>'operationTypeAdditionalInfo' IS DISTINCT FROM 'PAGAMENTO_FATURA'
  AND NOT EXISTS (SELECT 1 FROM spending_exclusions e WHERE e.account_type = a.type AND e.category = t.category)
  AND NOT EXISTS (SELECT 1 FROM spending_description_exclusions e
                  WHERE e.account_type = a.type AND t.description ILIKE e.pattern)
  -- Transferência entre contas da família (ex.: PIX de um dono para o outro): o mesmo valor entra
  -- em outra conta nossa em até 1 dia. shortcut: casa só por valor e data; trocar por CPF do recebedor se surgir falso positivo.
  AND NOT (a.type = 'BANK' AND EXISTS (
        SELECT 1 FROM transactions c JOIN accounts ca ON ca.id = c.account_id
        WHERE ca.type = 'BANK' AND c.account_id <> t.account_id
          AND c.amount = -t.amount AND abs(extract(epoch FROM c.date - t.date)) <= 86400));

-- Cada banco fecha o ciclo de um jeito: Bradesco conta o dia do fechamento na fatura que fecha,
-- Nubank joga o dia do fechamento (e as parcelas lançadas nele) para a próxima; Bradesco liga
-- bill_id à fatura errada, Nubank e Mercado Pago ligam certo. A fatura só diverge quando nenhum
-- dos três critérios fecha; `calculated` é o mais próximo do total.
CREATE OR REPLACE VIEW divergences AS
WITH snaps AS (
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
    ((SELECT coalesce(sum(sp.amount), 0) FROM spending sp
      WHERE sp.account_id = c.account_id AND sp.day > c.prev_closing AND sp.day <= c.closing_date)),
    ((SELECT coalesce(sum(sp.amount), 0) FROM spending sp
      WHERE sp.account_id = c.account_id AND sp.day >= c.prev_closing AND sp.day < c.closing_date)),
    ((SELECT coalesce(sum(sp.amount), 0) FROM spending sp JOIN transactions t ON t.id = sp.id WHERE t.bill_id = c.id))
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
WHERE abs(checks.reported - checks.calculated) > 0.05;
