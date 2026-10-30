# Plano · Importar posição da B3

Protótipo: `Fyin.pen`, quadro **18 · Importar da B3** (jornadas A e B + tabela de estados).
Validação técnica: feita no navegador em 30 out 2026 (ver "Fatos da B3").

## Decisões tomadas

| Tema | Decisão |
| --- | --- |
| Escopo | Posição **completa** da B3 (Tesouro, CDB registrado, ações, FIIs...). O que a Pluggy já traz do mesmo dono não soma de novo (ver Deduplicação). |
| Dono | A sheet "Importar da B3" pergunta **Jean ou Poliana** antes de abrir o site. |
| Valor | Entra o **líquido** (`valorLiquido`) no Tesouro; nos demais produtos a B3 só informa `valorAtualizado`, que entra no lugar (mesmo papel do `balance` da Pluggy). Guardamos também aplicado, bruto e atualizado: o objetivo futuro é uma **visão completa de impostos** (IR retido, bruto × líquido por posição). |
| Derivativos | `categoriaProduto = Derivativo` (Futuro, Opção, Termo, Swap, Box) é **gravado e mostrado, mas não soma** no patrimônio nem no `invested` da home: o valor é exposição/margem, não ativo. |
| Plano B (planilha + Compartilhar) | **Fora da v1.** O estado "Leitura pausada" existe, mas sem o botão "Importar arquivo". |
| Onde roda a leitura | No **app**: a WebView logada chama a API da B3 e entrega o JSON ao app, que repassa ao backend. O token da B3 nunca sai do aparelho. |

## Fatos da B3 (confirmados)

- Login: Azure AD B2C (`b3investidor.b2clogin.com`), passa pelo Cloudflare num navegador real.
- Token: `sessionStorage["token"]`, JWT de 60 min, escopo `Read.All`, **sem refresh token**. `sessionStorage["cache-guid"]` vai como query.
- Posição: `GET https://investidor.b3.com.br/negocio-posicao/api/extrato-posicao/v2/posicao?data=YYYY-MM-DD&pagina=N&cache-guid=…` com `Authorization: Bearer`.
  - Resposta: `{ itens: [{ categoriaProduto, tipoProduto, descricaoTipoProduto, totalPosicao, posicoes: [...] }], paginaAtual, totalPaginas }`.
  - Posição: `codigoIsin, codigoNegociacao, produto, nomeTituloPublico, indexador, vencimento, quantidade, disponivel, indisponivel, valorAplicado, valorBruto, valorLiquido, valorAtualizado, instituicao, documentoInstituicao, dataReferencia, percRentabilidadeContratada, documento (CPF!)`.
- Formatos por produto (lidos no código do site, `minhacarteira/322.*.js` e `617.*.js`, 30 out 2026). O app da B3 escolhe o cartão por `categoriaProduto` + `tipoProduto`:

  | Filtro na B3 | `categoriaProduto` / `tipoProduto` | Campos da lista | Valor que existe |
  | --- | --- | --- | --- |
  | Tesouro Direto | `TesouroDireto` / `TesouroDireto` | produto, indexador, vencimento, quantidade, codigoIsin, instituicao | `valorAplicado`, `valorBruto`, `valorLiquido` (só aqui) |
  | CDB (e LCI, LCA, CRI, CRA, DEB, LF, RDB...) | `RendaFixa` / `CDB`, `LCI`... | produto, emissor, indexador, vencimento, quantidade, tipoRegime, dataEmissao; detalhe: tipoPreco, valorUnitarioFormatado, valorTotalFormatado | `valorAtualizado` (curva de emissão em CDB/LCI/LCA; mercado em CRI/CRA/DEB) |
  | Ações | `RendaVariavel` / `Acao` | codigoNegociacao (ticker), razaoSocial, quantidade, precoFechamento, codigoIsin, escriturador | `valorAtualizado` = quantidade × fechamento |
  | BDR | `RendaVariavel` ou `Internacional` / `BDR` | igual a ações | `valorAtualizado` |
  | FII | `RendaVariavel` / `FundoInvestimentoImobiliario` | codigoNegociacao, nomeFundo, quantidade, precoFechamento, escriturador | `valorAtualizado` |
  | ETF | `RendaVariavel`/`Internacional` / `ETFFundoIndiceAcoes`, `ETFFundoIndiceInternacional`, `ETFRendaFixa` | codigoNegociacao, nomeFundo, quantidade, precoFechamento | `valorAtualizado` |
  | Futuro | `Derivativo` / `Futuro` (também `Opcao`, `Termo`, `Swap`, `Box`) | codigoNegociacao, quantidade (contratos), vencimento, razaoSocial | `valorAplicado`; **não é patrimônio** (exposição/margem) |
  | (outros) | `RendaVariavel` / `FundoInvestimento`, `Ouro`; `RendaFixa` / `COE`; `EmprestimoAtivos` | variam | `valorAtualizado` |

  Consequência: o "valor líquido" só existe no Tesouro. Nos demais o valor que entra é `valorAtualizado` (bruto, sem IR), o que reforça a visão futura de impostos.
  Enum completo de `tipoProduto` no site: CCB…TDA (renda fixa), COE, Opcao, Swap, Termo, Futuro, Box, EmprestimoAtivos, TesouroDireto, Acao, ETFFundoIndiceAcoes, ETFFundoIndiceInternacional, FundoInvestimento, Ouro, FundoInvestimentoImobiliario, ETFRendaFixa, BDR, FundosdeInvestimento*.
- Sessão: ao reabrir o navegador (30 out, ~50 min depois do login) a B3 voltou para `/login`; `sessionStorage` não sobrevive à WebView recriada. Falta confirmar se o B2C pede a senha de novo ou entra direto após o CPF.
- Data de referência: D-1. A Home da B3 expõe a última carga em `negocio-sistema/api/sistema/v1/carga/ultima-execucao`.
- **Não confirmado**: quanto tempo o SSO do B2C dura sem novo login (define se o passo 7 "atualizar sem ver a B3" acontece na prática).

## Backend (skill `fyin-api`)

1. **Migration `007_b3.sql`**
   - `b3_positions(owner, category, product_type, isin, code, name, issuer, institution, indexer, due_date, quantity, close_price, applied, gross, net, updated_value, reference_date, raw jsonb)`. Chave: `(owner, product_type, coalesce(isin, code), institution)` — derivativo pode vir sem ISIN. `value` exibido = `coalesce(net, updated_value)`.
   - `b3_imports(owner PRIMARY KEY, imported_at timestamptz, reference_date date, positions int, net_total numeric(14,2), previous_net_total numeric(14,2))` para frescor e o "+R$ desde 28 set" do toast.
   - Comentário no topo: B3 não é item da Pluggy; tabela própria para não entrar em `items` (o "Sincronizar tudo" tentaria a Pluggy).
2. **`internal/b3`** (handler + service + store)
   - `POST /v1/b3/positions` corpo `{ owner, pages: [<JSON cru da B3>...] }`. O service valida dono (`jean|poliana`), datas e números, mapeia e **substitui** a posição do dono numa transação. **Remove `documento` (CPF)** do `raw` antes de gravar (reaproveitar `sync/redact.go` ou campo explícito). Responde o resumo `{ positions, netTotal, delta, referenceDate }`.
   - `GET /v1/b3/imports`: lista por dono (`importedAt`, `referenceDate`, `positions`, `stale` = mais de 30 dias). O servidor decide o "desatualizado", o app não calcula.
   - Parse no Go, não no app: fica testável e o app só repassa.
3. **Patrimônio**: `investments.Store.Portfolio` ganha um `UNION ALL` de `b3_positions` como conta `b3-<owner>`, instituição `B3`, `kind` = `tipoProduto` cru (`TesouroDireto`, `CDB`, `Acao`, `BDR`, `FundoInvestimentoImobiliario`, `Futuro`...), com rótulos em `PortfolioKind` (Tesouro Direto, CDB, Ações, BDRs, FIIs, ETFs, Futuros) e fallback para `descricaoTipoProduto`. Ações/FII/BDR/ETF mostram ticker, quantidade e fechamento; renda fixa mostra emissor, indexador e vencimento. `home/store.go` soma `coalesce(net, updated_value)` no `invested`. Os dois **excluem `category = 'Derivativo'`** do total; o detalhe mostra o grupo com o rótulo "Fora do total" e sem peso percentual.
4. **Testes de integração** (`integrationtests/b3_test.go`, golden `sync_test.go`): import grava e substitui; segundo import calcula delta; CPF não fica no banco; posição aparece em `/v1/investments` e soma no `invested` da home; futuro aparece no detalhe mas não soma em nenhum total; dono inválido → 400; corpo malformado → 400 com mensagem em português.

## App iOS (skill `fyin-ios`)

Feature nova `ios/Fyin/Features/B3/` (não importa Settings; ligação por closure em `FyinApp`).

1. **Modelo + Repository**: `B3Import` (GET) e `B3ImportResult` (POST); `LiveB3Repository`/`PreviewB3Repository`.
2. **`B3Reader`** (`WKWebView` + `WKWebsiteDataStore.default()` para manter os cookies do B2C):
   - Carrega `investidor.b3.com.br`. Por `WKScriptMessageHandler`, um script injetado avisa quando `sessionStorage.token` aparece e então pagina o endpoint de posição (todas as páginas), devolvendo o JSON ao Swift.
   - Data de referência: `ultima-execucao` da B3, nunca o relógio do aparelho.
   - Modo **oculto** (atualizar): roda fora da tela; se em ~5 s cair na página de login, sinaliza `needsLogin` e o ViewModel apresenta a WebView (passo 8).
   - Isolado num tipo só: quando a B3 mudar o site, só ele muda.
3. **`B3ViewModel`**: estados `idle | explaining | login | reading(step) | importing | done(result) | paused(reason) | offline`, com teste unitário usando um repository e um reader falsos.
4. **Telas** (fiéis ao quadro 18, tokens de `Theme.swift`):
   - Ajustes: seção "Fora do Open Finance" com uma linha por dono importado + "Importar da B3" (Settings Row). Selo "Atualizar" em âmbar se `stale`.
   - Sheet de explicação com o seletor de dono (Filter Pill Jean | Poliana) + "Entrar na B3".
   - WebView em sheet grande: barra com domínio e cadeado, faixa "O Fyin lê só a sua posição".
   - Painel de leitura com etapas reais (entrou → lendo posição de DD mmm → enviando ao Fyin).
   - Toast de conclusão com o delta; terminado, a Home recarrega (closure, como o sync).
   - Patrimônio: a conta aparece como "B3 · Jean" com `Institutions` ganhando a entrada `b3`.
5. **Acessibilidade**: VoiceOver anuncia as etapas; Reduzir movimento no painel; `.sensoryFeedback(.success)` ao concluir.

## Design system

- `Fyin.pen`: o quadro 18 entra no mesmo PR. Promover a componente o **WebView Sheet** e o **Painel de etapas** se forem usados de fato.
- Skill `fyin-design-system`: adicionar a fonte "Fora do Open Finance" e o padrão de WebView de terceiros (domínio visível, aviso do Fyin, nunca desenhar o site).

## Deduplicação Pluggy × B3

Feita depois do import, em `migrations/008_b3_dedup.sql`: a view `b3_holdings` ganha `duplicate`.

- **A Pluggy vence** (atualiza sozinha); a B3 só cobre o que falta. Compara só com investimentos não resgatados do mesmo dono.
- Chaves, em ordem: ISIN (`raw->>'isin'` × `isin`), ticker (`raw->>'code'` × `code`) e, só em renda fixa, emissor (12 primeiros alfanuméricos de `issuer` × `emissor`/`razaoSocial`) + vencimento + indexador (DI = CDI).
- Sem chave que case, **as duas somam**: melhor contar duas vezes do que sumir com dinheiro.
- `/v1/investments` esconde a posição duplicada da conta B3 e o `invested` da home não a soma. O total do import continua sendo a B3 inteira. Contrato JSON não mudou.
- No banco local, em 30 out 2026, não havia sobreposição real (B3 só com Tesouro do Jean, que a Pluggy não traz); os casos estão semeados em `TestB3_PluggyWinsOverPositionItAlreadyBrings`. O formato do `emissor` da B3 num CDB ainda não foi visto de verdade.

### Pendência: conferir o fallback por emissor no primeiro import da B3 da Poliana

O fallback é **frágil**: compara só os 12 primeiros caracteres alfanuméricos do emissor (`NUFINANCEIRA`), porque Pluggy e B3 escrevem a razão social de jeitos diferentes e a B3 não traz CNPJ na posição. Pode errar para os dois lados:
- **Não casar** (B3 escreve diferente, ex. `NU FIN`, ou o campo vem com outro nome que não `emissor`/`razaoSocial`; indexador fora de DI/CDI): o CDB soma duas vezes.
- **Casar errado** (dois CDBs do mesmo emissor, mesmo vencimento e indexador em corretoras diferentes): a posição da B3 some do total.

Quem é a primeira a ter CDB do Nubank pelos dois lados é a Poliana. Depois do primeiro import dela, rodar no `make psql`:

```sql
-- CDBs da B3 da Poliana: duplicate deve ser true para os que a Pluggy também traz
SELECT name, raw->>'emissor' AS emissor, raw->>'razaoSocial' AS razao, indexer, due_date, value, duplicate
FROM b3_holdings WHERE owner = 'poliana' AND category = 'RendaFixa' ORDER BY due_date;
-- e comparar com os CDBs ativos da Pluggy dela
SELECT raw->>'issuer', raw->>'rateType', (raw->>'dueDate')::date, balance
FROM investments v JOIN items i ON i.id = v.item_id
WHERE i.owner = 'poliana' AND v.type = 'FIXED_INCOME' AND v.status IS DISTINCT FROM 'TOTAL_WITHDRAWAL' ORDER BY 3;
```

Se algum CDB que existe nos dois lados ficar com `duplicate = false`, ou um que só existe na B3 ficar `true`, ajustar a regra numa migration nova (e o caso no teste). Se a B3 trouxer CNPJ do emissor, trocar o prefixo de 12 caracteres pelo CNPJ (`raw->>'issuerCNPJ'` na Pluggy).

## Fora desta entrega

- Visão de impostos (bruto, IR, líquido) — dados já ficam guardados.
- Plano B por planilha (Share Extension).
- Lembrete mensal por push.
- Proventos e movimentações da B3.

## Riscos

- Leitura de site sem API oficial: quebra se a B3 mudar endpoint ou login. Mitigação: `B3Reader` isolado + estado "Leitura pausada".
- Zona cinzenta de termos de uso (uso pessoal, sessão aberta pelo próprio investidor).
- CPF (`documento`) passa pelo app em memória; não é gravado nem logado.

## Ordem de execução

Worktree a partir da `main` (AGENTS.md) → backend com testes → app → pen/skill → PR único (contrato JSON muda dos dois lados).
