-- Valores monetários em NUMERIC(14,2); nunca float.
-- `raw` guarda o payload da Pluggy para não perder campos; contém dados pessoais (ex.: CPF em paymentData).

CREATE TABLE items (
  id                  uuid PRIMARY KEY,
  owner               text NOT NULL,
  connector           text NOT NULL,
  status              text NOT NULL,
  consent_expires_at  timestamptz,
  synced_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE accounts (
  id            uuid PRIMARY KEY,
  item_id       uuid NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  type          text NOT NULL,            -- BANK | CREDIT
  subtype       text NOT NULL,
  name          text NOT NULL,
  balance       numeric(14,2),            -- cartão: dívida total (fatura fechada + em aberto + parcelas futuras)
  credit_limit  numeric(14,2),
  raw           jsonb NOT NULL
);

CREATE TABLE bills (
  id            uuid PRIMARY KEY,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  due_date      date NOT NULL,
  closing_date  date,
  total         numeric(14,2) NOT NULL,
  minimum       numeric(14,2),
  raw           jsonb NOT NULL            -- inclui payments[], base para "paga / a pagar"
);
CREATE INDEX bills_due_idx ON bills (due_date);

-- Sinal de `amount` vem como a instituição manda: no cartão compra é positivo (DEBIT), em conta é negativo.
CREATE TABLE transactions (
  id                  uuid PRIMARY KEY,
  account_id          uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  date                timestamptz NOT NULL,
  description         text NOT NULL,
  amount              numeric(14,2) NOT NULL,
  type                text NOT NULL,      -- DEBIT | CREDIT
  status              text NOT NULL,      -- POSTED | PENDING
  category            text,
  bill_id             uuid,               -- só em fatura já fechada
  bill_forecast       text,               -- 'YYYY-MM' da fatura em aberto
  installment_number  int,
  total_installments  int,
  raw                 jsonb NOT NULL
);
CREATE INDEX transactions_account_date_idx ON transactions (account_id, date);
