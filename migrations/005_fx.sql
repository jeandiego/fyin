-- Cotação do dólar (PTAX de venda do Banco Central), uma por dia útil. Alimenta a conversão de contas e
-- posições em USD (corretora internacional) para reais; sem isso o valor em dólar somava como se fosse real.

CREATE TABLE fx_rates (
  day         date PRIMARY KEY,           -- dia da cotação (America/Sao_Paulo)
  usd_brl     numeric(10,4) NOT NULL,
  fetched_at  timestamptz NOT NULL DEFAULT now()
);

-- Cotação mais recente: fim de semana e feriado herdam a última cotação útil.
CREATE VIEW usd_brl AS SELECT day, usd_brl AS rate FROM fx_rates ORDER BY day DESC LIMIT 1;

-- Converte para reais, arredondando por valor para que os totais fechem com as linhas.
-- shortcut: sem cotação gravada devolve o valor como veio; o app avisa pela ausência de usdRate.
CREATE FUNCTION to_brl(amount numeric, currency text) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN currency = 'USD' THEN round(amount * coalesce((SELECT rate FROM usd_brl), 1), 2) ELSE amount END
$$;
