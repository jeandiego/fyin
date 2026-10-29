---
name: fyin-api
description: Arquitetura e convenções do backend Go do Fyin (cmd/, internal/, migrations/, integrationtests/). Use ao criar ou alterar endpoint, serviço, query SQL, migration, sync com a Pluggy ou ao mudar o contrato JSON consumido pelo app iOS.
---

# Backend Go do Fyin

Go + Postgres (pgx) + `net/http` (ServeMux). Sem framework, sem ORM. Módulo `fyin`.

## Camadas

```
cmd/api, cmd/sync      composição: lê env, monta dependências, sobe. Sem regra de negócio.
internal/<feature>/    uma pasta por feature: handler.go + service.go (+ store.go)
internal/pluggy        client HTTP da Pluggy (única fronteira externa)
internal/sync          cópia Pluggy → Postgres, numa transação
internal/testdb        banco isolado por teste
migrations/            NNN_nome.sql, embutidas em migrations/embed.go
integrationtests/      testes por feature, banco real + fake da Pluggy
```

Fluxo: `Handler` (HTTP, parse, status) → `Service` (regra, tempo, orquestração) → `Store` (SQL).
Features pequenas podem manter o SQL no `Service` (como `internal/items`); crie `Store` quando houver query não trivial (como `internal/home`).

## Regras

- **Dependências por construtor**: `NewHandler(svc)`, `NewService(store, now)`, `NewStore(pool)`. Relógio entra como `now func() time.Time`; nunca chame `time.Now()` dentro de serviço.
- **Interfaces no consumidor**, mínimas (`items.Pluggy`, `sync.API`); `*pluggy.Client` as satisfaz. Não crie interface para storage.
- **Rotas**: cada handler expõe `Register(mux)` com padrões `"GET /v1/..."`; registre-o em `cmd/api/main.go`. Tudo sob `/v1`, atrás do `bearer` middleware.
- **Dinheiro nunca é float.** O Postgres devolve `numeric(14,2)::text` e o JSON leva string decimal (`"6240.00"`). O iOS decodifica em `Decimal`.
- **Datas**: calendário e "mês" em `America/Sao_Paulo` (`saoPaulo` em `internal/home`), mês no formato `YYYY-MM`, dia `YYYY-MM-DD`. Instantes em RFC 3339.
- **Erros HTTP**: corpo `{"error":"mensagem em português"}`. Erro de cliente (400/404) tem mensagem específica; erro interno loga com `log.Printf("<feature> <op>: %v", err)` e responde mensagem genérica, nunca o texto do erro. Valide entradas na borda (ex.: UUID de rota antes do SQL).
- **Erro sentinela** por feature (`items.ErrNotFound`) traduzido em `fail()` no handler.
- **Operação longa** (sync): responde `202` na hora, roda em goroutine, estado consultável por GET. Sem mutex solto: estado atrás de `sync.Mutex` no serviço.
- **Pluggy**: busque tudo antes de gravar e grave numa única transação (`internal/sync.Item`). Nunca logue segredo ou payload sensível (`sync/redact.go`).
- **SQL**: parametrizado (`$1`), sem concatenar entrada. Valores derivados saem de view/CTE no banco, não de cálculo em Go.
- **Migrations**: arquivo novo `NNN_descricao.sql` com o próximo número; nunca edite uma já aplicada. Comente o porquê no topo.
- **Atalhos conscientes** levam comentário `// shortcut: <limite>, <quando trocar>`.
- Comentários e mensagens em português, só o porquê.

## Contrato com o app

O JSON de `internal/home`, `internal/items`, `internal/investments` e `internal/cards` é consumido por `ios/Fyin/Features/*`. Mudou campo, tipo ou rota: atualize no mesmo PR o modelo Swift correspondente (skill `fyin-ios`) e o teste de integração. Prefira adicionar campo a renomear/remover.

## Novo endpoint, checklist

1. Teste de integração em `integrationtests/` primeiro (skill `testing`, golden: `integrationtests/sync_test.go`).
2. Migration, se o schema mudar.
3. Store/Service/Handler na pasta da feature; `Register` em `cmd/api/main.go`.
4. Atualizar o modelo/repository do iOS se o contrato mudou.

## Verificação

```bash
make up && make test    # exige Postgres de pé
go vet ./...
```
