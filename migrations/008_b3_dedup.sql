-- Posição da B3 que a Pluggy já traz do mesmo dono não soma de novo: a Pluggy vence porque atualiza sozinha,
-- a B3 só cobre o que falta. O total do import (b3_imports) continua sendo a posição inteira da B3.
-- Casa por ISIN, por ticker ou, na renda fixa sem nenhum dos dois (CDB do Nubank), por emissor + vencimento + indexador.
-- Sem chave que case, as duas somam: melhor contar duas vezes do que sumir com dinheiro.
-- shortcut: emissor compara os 12 primeiros caracteres alfanuméricos (Pluggy e B3 escrevem a razão social diferente);
-- trocar por CNPJ se a B3 passar a informá-lo na posição.
CREATE OR REPLACE VIEW b3_holdings AS
SELECT p.*,
  coalesce(p.net, p.updated_value, p.applied, 0)::numeric(14,2) AS value,
  p.category <> 'Derivativo' AS counts,
  EXISTS (
    SELECT 1 FROM investments v JOIN items i ON i.id = v.item_id
    WHERE i.owner = p.owner AND v.status IS DISTINCT FROM 'TOTAL_WITHDRAWAL' AND (
      nullif(v.raw->>'isin', '') = nullif(p.isin, '')
      OR nullif(v.raw->>'code', '') = nullif(p.code, '')
      OR (p.category = 'RendaFixa' AND v.type = 'FIXED_INCOME'
        AND ((v.raw->>'dueDate')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date = p.due_date
        -- B3 escreve DI, a Pluggy CDI
        AND replace(upper(v.raw->>'rateType'), 'CDI', 'DI') = replace(upper(p.indexer), 'CDI', 'DI')
        AND nullif(left(regexp_replace(upper(v.raw->>'issuer'), '[^A-Z0-9]', '', 'g'), 12), '')
          = left(regexp_replace(upper(coalesce(p.raw->>'emissor', p.raw->>'razaoSocial')), '[^A-Z0-9]', '', 'g'), 12))
    )
  ) AS duplicate
FROM b3_positions p;
