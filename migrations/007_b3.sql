-- Posição importada da Área do Investidor da B3: o app lê o site logado e manda as páginas cruas da API de posição.
-- Tabelas próprias, fora de items: a B3 não é item da Pluggy e o "Sincronizar tudo" não pode tentar sincronizá-la.
-- Cada import substitui a posição inteira do dono.

CREATE TABLE b3_positions (
  id              bigserial PRIMARY KEY,
  owner           text NOT NULL,
  category        text NOT NULL,           -- categoriaProduto: TesouroDireto, RendaFixa, RendaVariavel, Derivativo...
  product_type    text NOT NULL,           -- tipoProduto: TesouroDireto, CDB, Acao, BDR, FundoInvestimentoImobiliario, Futuro...
  product_label   text NOT NULL,           -- descricaoTipoProduto, rótulo da própria B3
  name            text NOT NULL,
  isin            text,
  code            text,                    -- codigoNegociacao (ticker)
  institution     text,                    -- custodiante (corretora)
  indexer         text,
  due_date        date,
  quantity        numeric,
  close_price     numeric,
  applied         numeric(14,2),
  gross           numeric(14,2),
  net             numeric(14,2),           -- valorLiquido: só o Tesouro Direto informa
  updated_value   numeric(14,2),           -- valorAtualizado: bruto, sem IR
  reference_date  date NOT NULL,           -- D-1 da B3
  raw             jsonb NOT NULL           -- sem o CPF (documento)
);
CREATE INDEX b3_positions_owner ON b3_positions (owner);

CREATE TABLE b3_imports (
  owner           text PRIMARY KEY,
  imported_at     timestamptz NOT NULL,
  reference_date  date NOT NULL,
  positions       int NOT NULL,
  total           numeric(14,2) NOT NULL,
  previous_total  numeric(14,2)            -- total do import anterior, para o "quanto mudou"
);

-- Valor que a posição soma no patrimônio: líquido quando a B3 informa, senão o atualizado.
-- Derivativo (futuro, opção, termo, swap) é exposição ou margem, não ativo: aparece, mas não soma.
-- shortcut: duplica o que a Pluggy já traz (CDB do Nubank, por exemplo); a deduplicação é a próxima tarefa.
CREATE VIEW b3_holdings AS
SELECT p.*,
  coalesce(p.net, p.updated_value, p.applied, 0)::numeric(14,2) AS value,
  p.category <> 'Derivativo' AS counts
FROM b3_positions p;
