-- Faturas por cartão para o modal de cartões (board "17 · Cartão · Morph"). A Pluggy só manda as faturas
-- fechadas; a aberta e as futuras saem de bill_forecast. Período = mês do vencimento ('YYYY-MM'), o mesmo
-- de bill_forecast. Fatura e cartão são entidades separadas: pagamentos mudam o status, nunca o total.

-- Uma linha por (cartão, período): fechadas + aberta e futuras até a última parcela lançada (no mínimo uma futura).
-- shortcut: datas da aberta/futuras = as da última fechada + N meses; erra 1-2 dias quando o banco ajusta por
-- fim de semana. Trocar se a Pluggy passar a mandar o fechamento previsto. Cartão sem fatura fechada não aparece.
CREATE VIEW card_bill_periods AS
WITH closed AS (
  SELECT b.account_id, to_char(b.due_date, 'YYYY-MM') AS period, b.id AS bill_id, b.closing_date, b.due_date, b.total
  FROM bills b WHERE b.closing_date IS NOT NULL
), last AS (
  SELECT DISTINCT ON (account_id) * FROM closed ORDER BY account_id, closing_date DESC
), pending AS (
  SELECT l.account_id, to_char(l.due_date + n * interval '1 month', 'YYYY-MM'), NULL::uuid,
         (l.closing_date + n * interval '1 month')::date, (l.due_date + n * interval '1 month')::date, NULL::numeric(14,2)
  FROM last l, generate_series(1, greatest(2, (
      SELECT max((date_part('year', f) - date_part('year', l.due_date)) * 12 + date_part('month', f) - date_part('month', l.due_date))::int
      FROM transactions t, to_date(t.bill_forecast, 'YYYY-MM') f
      WHERE t.account_id = l.account_id AND t.bill_id IS NULL AND t.bill_forecast IS NOT NULL))) n
), all_bills AS (
  SELECT * FROM closed UNION ALL SELECT * FROM pending
)
SELECT x.*,
       lag(x.closing_date) OVER w AS prev_closing,
       lead(x.closing_date) OVER w AS next_closing,
       coalesce(lag(x.closing_date) OVER w, (x.closing_date - interval '1 month')::date) + 1 AS opening_date
FROM all_bills x WINDOW w AS (PARTITION BY x.account_id ORDER BY x.period);

-- Lançamentos de cada fatura: tudo que o cartão lançou, menos pagamentos (igual à view divergences).
-- Fechada: cada banco liga a compra à fatura de um jeito (ver 003), então vale o critério cuja soma fica mais
-- perto do total informado. Aberta e futuras: o bill_forecast da própria transação.
CREATE VIEW card_bill_lines AS
WITH moves AS (
  SELECT t.id, t.account_id, t.bill_id, t.bill_forecast, t.amount, (t.date AT TIME ZONE 'America/Sao_Paulo')::date AS day
  FROM transactions t JOIN accounts a ON a.id = t.account_id
  WHERE a.type = 'CREDIT'
    AND NOT EXISTS (SELECT 1 FROM spending_exclusions e WHERE e.account_type = 'CREDIT' AND e.category = t.category)
), cand AS (
  SELECT p.account_id, p.period, p.total, c.crit, m.id, m.amount
  FROM card_bill_periods p CROSS JOIN (VALUES (1), (2), (3)) c(crit)
  LEFT JOIN moves m ON m.account_id = p.account_id AND CASE c.crit
    WHEN 1 THEN m.bill_id = p.bill_id
    WHEN 2 THEN m.day > p.opening_date - 1 AND m.day <= p.closing_date
    ELSE m.day >= p.opening_date - 1 AND m.day < p.closing_date END
  WHERE p.bill_id IS NOT NULL
), best AS (
  SELECT DISTINCT ON (account_id, period) account_id, period, crit
  FROM cand GROUP BY account_id, period, total, crit
  ORDER BY account_id, period, abs(total - coalesce(sum(amount), 0)), crit
)
SELECT c.account_id, c.period, c.id AS transaction_id
FROM cand c JOIN best USING (account_id, period, crit) WHERE c.id IS NOT NULL
UNION ALL
SELECT p.account_id, p.period, m.id
FROM card_bill_periods p JOIN moves m ON m.account_id = p.account_id AND m.bill_id IS NULL AND m.bill_forecast = p.period
WHERE p.bill_id IS NULL;

-- Status de cada fatura em `today` e qual é a atual do cartão: a mais antiga com saldo (fechada ou vencida);
-- sem saldo, a aberta. Paga = pagamentos entre o fechamento dela e o da seguinte cobrem o total (5 centavos de
-- tolerância, como em divergences). Parcial = não cobriu, mas a seguinte já fechou: o resto rolou para ela.
CREATE FUNCTION card_bills(today date) RETURNS TABLE (
  account_id uuid, period text, opening_date date, closing_date date, due_date date,
  total numeric(14,2), paid numeric(14,2), paid_on date, status text, is_current boolean
) LANGUAGE sql STABLE AS $$
WITH pay AS (
  SELECT t.account_id, (t.date AT TIME ZONE 'America/Sao_Paulo')::date AS day, -t.amount AS amount
  FROM transactions t JOIN accounts a ON a.id = t.account_id
  WHERE a.type = 'CREDIT' AND t.amount < 0
    AND EXISTS (SELECT 1 FROM spending_exclusions e WHERE e.account_type = 'CREDIT' AND e.category = t.category)
), b AS (
  SELECT p.*,
    coalesce(p.total, (SELECT coalesce(sum(t.amount), 0) FROM card_bill_lines l JOIN transactions t ON t.id = l.transaction_id
                       WHERE l.account_id = p.account_id AND l.period = p.period))::numeric(14,2) AS amount,
    (SELECT coalesce(sum(y.amount), 0) FROM pay y WHERE y.account_id = p.account_id
       AND y.day > p.closing_date AND (p.next_closing IS NULL OR y.day <= p.next_closing))::numeric(14,2) AS paid_amount,
    (SELECT max(y.day) FROM pay y WHERE y.account_id = p.account_id
       AND y.day > p.closing_date AND (p.next_closing IS NULL OR y.day <= p.next_closing)) AS paid_day
  FROM card_bill_periods p
), s AS (
  SELECT b.*, CASE
    WHEN today <= b.closing_date THEN CASE WHEN b.prev_closing IS NULL OR today > b.prev_closing THEN 'open' ELSE 'future' END
    WHEN b.paid_amount >= b.amount - 0.05 THEN 'paid'
    WHEN b.next_closing < today THEN 'partial'
    WHEN today > b.due_date THEN 'overdue'
    ELSE 'closed' END AS st
  FROM b
)
SELECT s.account_id, s.period, s.opening_date, s.closing_date, s.due_date, s.amount, s.paid_amount, s.paid_day, s.st,
       s.period = (SELECT c.period FROM s c WHERE c.account_id = s.account_id AND c.st IN ('closed', 'overdue', 'open')
                   ORDER BY c.period LIMIT 1)
FROM s
$$;
