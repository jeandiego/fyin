package integrationtests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"fyin/internal/b3"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// b3Page imita uma página de GET negocio-posicao/api/extrato-posicao/v2/posicao, com os campos vistos em 30 out 2026.
const b3Page = `{"paginaAtual":1,"totalPaginas":1,"itens":[
	{"categoriaProduto":"TesouroDireto","tipoProduto":"TesouroDireto","descricaoTipoProduto":"Tesouro Direto","totalPosicao":1000.5,
	 "posicoes":[{"produto":"TESOURO IPCA+ 2032","codigoIsin":"BRSTNCNTB7T1","indexador":"IPCA","vencimento":"2032-08-15T00:00:00",
	   "quantidade":2.5,"valorAplicado":900,"valorBruto":1010.75,"valorLiquido":1000.5,"valorAtualizado":1010.75,
	   "instituicao":"NU INVESTIMENTOS S.A. - CTVM","documento":"12345678900","dataReferencia":"2026-10-29T00:00:00"}]},
	{"categoriaProduto":"RendaVariavel","tipoProduto":"Acao","descricaoTipoProduto":"Ações","totalPosicao":3200,
	 "posicoes":[{"produto":"PETR4 - PETROBRAS","codigoNegociacao":"PETR4","codigoIsin":"BRPETRACNPR6","quantidade":100,
	   "precoFechamento":32,"valorAtualizado":3200,"instituicao":"XP INVESTIMENTOS","documento":"12345678900"}]},
	{"categoriaProduto":"Derivativo","tipoProduto":"Futuro","descricaoTipoProduto":"Futuro","totalPosicao":0,
	 "posicoes":[{"codigoNegociacao":"WINZ26","quantidade":1,"valorAplicado":5000,"vencimento":"2026-12-16T00:00:00",
	   "instituicao":"XP INVESTIMENTOS","documento":"12345678900"}]}]}`

func postB3(t *testing.T, pool *pgxpool.Pool, now time.Time, body string) (int, map[string]any) {
	t.Helper()
	mux := http.NewServeMux()
	b3.NewHandler(b3.NewService(pool, func() time.Time { return now })).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("POST", "/v1/b3/positions", strings.NewReader(body)))
	var out map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &out), rec.Body.String())
	return rec.Code, out
}

func getB3(t *testing.T, pool *pgxpool.Pool, now time.Time) []any {
	t.Helper()
	mux := http.NewServeMux()
	b3.NewHandler(b3.NewService(pool, func() time.Time { return now })).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/b3/imports", nil))
	require.Equal(t, http.StatusOK, rec.Code, rec.Body.String())
	var out []any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &out))
	return out
}

func importBody(owner, ref string, pages ...string) string {
	return `{"owner":"` + owner + `","referenceDate":"` + ref + `","pages":[` + strings.Join(pages, ",") + `]}`
}

var b3Now = time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)

func TestB3_ImportReplacesOwnerPositionAndFeedsPortfolio(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)

	code, got := postB3(t, pool, b3Now, importBody("ana", "2026-10-29", b3Page))

	require.Equal(t, http.StatusOK, code)
	// Futuro é gravado, mas não soma: total = 1000.50 líquido do Tesouro + 3200 da ação
	assert.Equal(t, map[string]any{"owner": "ana", "positions": float64(3), "total": "4200.50", "delta": nil,
		"referenceDate": "2026-10-29", "importedAt": "2026-10-30T12:00:00Z"}, got)

	var cpf int
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT count(*) FROM b3_positions WHERE raw ? 'documento'`).Scan(&cpf))
	assert.Zero(t, cpf, "o CPF não fica gravado")

	_, inv := getInvestments(t, pool)
	_, home := getHome(t, pool, "")
	// seed: 1000 do CDB + 200.50 da caixinha + 5000 do carro; B3: 4200.50
	assert.Equal(t, "10401.00", inv["total"])
	assert.Equal(t, inv["total"], home["invested"], "a home soma o mesmo que o detalhe")
	var acc map[string]any
	for _, a := range inv["accounts"].([]any) {
		if a.(map[string]any)["id"] == "b3-ana" {
			acc = a.(map[string]any)
		}
	}
	require.NotNil(t, acc, "a B3 vira uma conta do dono")
	assert.Equal(t, "B3", acc["institution"])
	assert.Equal(t, "4200.50", acc["total"])
	groups := acc["groups"].([]any)
	require.Len(t, groups, 3)
	assert.Equal(t, "Acao", groups[0].(map[string]any)["kind"])
	td := groups[1].(map[string]any)
	assert.Equal(t, "TesouroDireto", td["kind"])
	p := td["positions"].([]any)[0].(map[string]any)
	assert.Equal(t, "TESOURO IPCA+ 2032", p["name"])
	assert.Equal(t, "1000.50", p["balance"], "Tesouro entra pelo líquido")
	assert.Equal(t, "IPCA", p["indexer"])
	assert.Equal(t, "2032-08-15", p["dueDate"])
	fut := groups[2].(map[string]any)
	assert.Equal(t, "Futuro", fut["kind"])
	assert.Equal(t, true, fut["outsideTotal"])
	assert.Equal(t, "5000.00", fut["total"])

	// Segundo import do mesmo dono substitui tudo e informa quanto mudou.
	code, got = postB3(t, pool, b3Now.Add(24*time.Hour), importBody("ana", "2026-10-30", strings.Replace(b3Page, `"valorLiquido":1000.5`, `"valorLiquido":1100.5`, 1)))
	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, "4300.50", got["total"])
	assert.Equal(t, "100.00", got["delta"])
	var n int
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT count(*) FROM b3_positions`).Scan(&n))
	assert.Equal(t, 3, n)
}

func TestB3_ImportsListEveryOwnerAndFlagsStale(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)
	exec(t, pool, `INSERT INTO items (id, owner, connector, status) VALUES ('66666666-6666-4666-8666-666666666666', 'bia', 'Nubank', 'UPDATED')`)
	postB3(t, pool, b3Now, importBody("ana", "2026-10-29", b3Page))

	fresh := getB3(t, pool, b3Now.Add(24*time.Hour))
	old := getB3(t, pool, b3Now.Add(31*24*time.Hour))

	require.Len(t, fresh, 2)
	ana, bia := fresh[0].(map[string]any), fresh[1].(map[string]any)
	assert.Equal(t, "ana", ana["owner"])
	assert.Equal(t, "2026-10-30T12:00:00Z", ana["importedAt"])
	assert.Equal(t, "2026-10-29", ana["referenceDate"])
	assert.Equal(t, float64(3), ana["positions"])
	assert.Equal(t, "4200.50", ana["total"])
	assert.Equal(t, false, ana["stale"])
	assert.Equal(t, map[string]any{"owner": "bia", "importedAt": nil, "referenceDate": nil, "positions": float64(0), "total": "0.00", "stale": false}, bia,
		"quem ainda não importou aparece para o app oferecer a importação")
	assert.Equal(t, true, old[0].(map[string]any)["stale"], "mais de 30 dias pede atualização")
}

func TestB3_RejectsInvalidImport(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)

	for name, body := range map[string]string{
		"dono desconhecido": importBody("zé", "2026-10-29", b3Page),
		"data inválida":     importBody("ana", "29/10/2026", b3Page),
		"sem páginas":       importBody("ana", "2026-10-29"),
		"página sem itens":  importBody("ana", "2026-10-29", `{"paginaAtual":1}`),
		"json quebrado":     `{"owner":`,
	} {
		code, got := postB3(t, pool, b3Now, body)
		assert.Equal(t, http.StatusBadRequest, code, name)
		assert.NotEmpty(t, got["error"], name)
	}
	var n int
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT count(*) FROM b3_imports`).Scan(&n))
	assert.Zero(t, n, "import inválido não grava nada")
}
