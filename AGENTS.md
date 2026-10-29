# fyin

Backend Go + Postgres que sincroniza dados da Pluggy (Meu Pluggy). Comandos: `make up`, `make sync`, `make test`.

## Rules

Toda nova sessão de desenvolvimento deve partir da main > worktree > PR merge main > delete worktree. 
Nenhuma feature deve ser desenvolvida em cima do que esta sendo modificado

## Arquitetura

Antes de mexer, carregue a skill da área e siga-a. Elas definem camadas, contratos e checklists; não replique o conteúdo delas aqui.

| Área | Skill |
| --- | --- |
| Backend Go (`cmd/`, `internal/`, `migrations/`, `integrationtests/`) | `.claude/skills/fyin-api` |
| App iOS (`ios/`) | `.claude/skills/fyin-ios` |
| UI: qual componente/token usar (e não usar), de `Fyin.pen` | `.claude/skills/fyin-design-system` |

- Mudança que cruza os dois lados (contrato JSON) usa as duas skills e altera backend e app no mesmo PR.
- Se a skill e o código divergirem, não improvise: corrija a skill no mesmo PR ou pergunte.

## Testes

Siga a skill `.claude/skills/testing` (origem: github.com/primo-devs/public-skills, `skills/testing`).
Integração por padrão, banco real clonado de um template (`internal/testdb`), nunca mock de storage; só a Pluggy é substituída, por um fake.

Golden standard (um exemplo por tipo, use estes como referência):

| Tipo | Exemplo |
| --- | --- |
| Suite de integração (feature, banco real + fake da Pluggy) | `integrationtests/sync_test.go` |
| Teste de client HTTP (httptest) | `internal/pluggy/client_test.go` |

Requer o Postgres de pé (`make up`).
