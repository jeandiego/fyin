# fyin

Backend Go + Postgres que sincroniza dados da Pluggy (Meu Pluggy). Comandos: `make up`, `make sync`, `make test`.

## Rules

Toda nova sessão de desenvolvimento deve partir da main > worktree > PR merge main > delete worktree. 
Nenhuma feature deve ser desenvolvida em cima do que esta sendo modificado

## Testes

Siga a skill `.claude/skills/testing` (origem: github.com/primo-devs/public-skills, `skills/testing`).
Integração por padrão, banco real clonado de um template (`internal/testdb`), nunca mock de storage; só a Pluggy é substituída, por um fake.

Golden standard (um exemplo por tipo, use estes como referência):

| Tipo | Exemplo |
| --- | --- |
| Suite de integração (feature, banco real + fake da Pluggy) | `integrationtests/sync_test.go` |
| Teste de client HTTP (httptest) | `internal/pluggy/client_test.go` |

Requer o Postgres de pé (`make up`).
