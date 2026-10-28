-- Dados da home: empréstimos, investimentos, patrimônio manual, histórico de saldo e regras de gasto.

CREATE TABLE loans (
  id                   uuid PRIMARY KEY,
  item_id              uuid NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  product_name         text NOT NULL,
  outstanding_balance  numeric(14,2),        -- payments.contractOutstandingBalance
  raw                  jsonb NOT NULL
);

CREATE TABLE investments (
  id       uuid PRIMARY KEY,
  item_id  uuid NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  type     text NOT NULL,
  name     text NOT NULL,
  status   text,                             -- ACTIVE | PENDING | TOTAL_WITHDRAWAL
  balance  numeric(14,2) NOT NULL,           -- valor líquido atual
  raw      jsonb NOT NULL
);

-- Patrimônio declarado à mão (imóvel, carro...). Sem tela ainda: inserir via psql.
CREATE TABLE manual_assets (
  id     bigserial PRIMARY KEY,
  owner  text NOT NULL,
  name   text NOT NULL,
  value  numeric(14,2) NOT NULL
);

-- Saldo informado pela instituição a cada sync (só contas BANK). É a âncora do saldo retroativo
-- e a base para achar transações faltando (view divergences).
CREATE TABLE balance_snapshots (
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  taken_at    timestamptz NOT NULL,
  balance     numeric(14,2) NOT NULL,
  PRIMARY KEY (account_id, taken_at)
);
INSERT INTO balance_snapshots (account_id, taken_at, balance)
SELECT a.id, i.synced_at, a.balance FROM accounts a JOIN items i ON i.id = a.item_id
WHERE a.type = 'BANK' AND a.balance IS NOT NULL;

-- Categorias que só movem dinheiro entre contas do próprio dono, então não são gasto.
-- Ajustar aqui ao conectar outro banco; a view divergences acusa quando a fatura não fecha.
CREATE TABLE spending_exclusions (
  account_type  text NOT NULL,             -- BANK | CREDIT
  category      text NOT NULL,
  reason        text NOT NULL,
  PRIMARY KEY (account_type, category)
);
INSERT INTO spending_exclusions VALUES
  ('BANK',   'Same person transfer', 'transferência entre contas próprias'),
  ('BANK',   'Credit card payment',  'pagamento da fatura; as compras já contam no cartão'),
  ('BANK',   'Credit card fees',     'Bradesco classifica o pagamento da fatura assim'),
  ('BANK',   'Investments',          'aplicação não é gasto'),
  ('BANK',   'Automatic investment', 'aplicação não é gasto'),
  ('CREDIT', 'Credit card payment',  'pagamento recebido pelo cartão');

-- Livro de gastos (fixos + variáveis): fonte única da home, e o lugar para auditar um mês.
-- Conta: só saídas, em positivo. Cartão: compras positivas, estornos negativos, por data de lançamento.
CREATE VIEW spending AS
SELECT t.id, t.account_id, a.type AS account_type, t.date,
       (t.date AT TIME ZONE 'America/Sao_Paulo')::date AS day,
       t.description, t.category,
       CASE WHEN a.type = 'BANK' THEN -t.amount ELSE t.amount END AS amount
FROM transactions t JOIN accounts a ON a.id = t.account_id
WHERE (a.type = 'CREDIT' OR t.amount < 0)
  AND NOT EXISTS (SELECT 1 FROM spending_exclusions e WHERE e.account_type = a.type AND e.category = t.category);

-- Onde o que a instituição informa não bate com a soma das transações:
--   saldo:  saldo do sync anterior + transações até este sync <> saldo deste sync (faltou transação)
--   fatura: gastos do ciclo (fechamento anterior, fechamento] <> total da fatura (regra de gasto ou dado errado)
CREATE VIEW divergences AS
WITH snaps AS (
  SELECT account_id, taken_at, balance,
         lag(taken_at) OVER w AS prev_at, lag(balance) OVER w AS prev_balance
  FROM balance_snapshots WINDOW w AS (PARTITION BY account_id ORDER BY taken_at)
), cycles AS (
  SELECT account_id, closing_date, total,
         lag(closing_date) OVER (PARTITION BY account_id ORDER BY closing_date) AS prev_closing
  FROM bills WHERE closing_date IS NOT NULL
), checks AS (
  SELECT 'saldo' AS kind, s.account_id, (s.taken_at AT TIME ZONE 'America/Sao_Paulo')::date AS day,
         s.balance AS reported,
         s.prev_balance + coalesce((SELECT sum(t.amount) FROM transactions t
           WHERE t.account_id = s.account_id AND t.date > s.prev_at AND t.date <= s.taken_at), 0) AS calculated
  FROM snaps s WHERE s.prev_at IS NOT NULL
  UNION ALL
  SELECT 'fatura', c.account_id, c.closing_date, c.total,
         coalesce((SELECT sum(sp.amount) FROM spending sp
           WHERE sp.account_id = c.account_id AND sp.day > c.prev_closing AND sp.day <= c.closing_date), 0)
  FROM cycles c WHERE c.prev_closing IS NOT NULL
)
SELECT checks.*, a.name AS account_name, checks.reported - checks.calculated AS difference
FROM checks JOIN accounts a ON a.id = checks.account_id
WHERE checks.reported <> checks.calculated;
