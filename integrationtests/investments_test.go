package integrationtests

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"fyin/internal/investments"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func getInvestments(t *testing.T, pool *pgxpool.Pool) (int, map[string]any) {
	t.Helper()
	mux := http.NewServeMux()
	investments.NewHandler(investments.NewStore(pool)).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/investments", nil))
	var body map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	return rec.Code, body
}

func TestInvestments_WithoutDataIsEmpty(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)

	code, got := getInvestments(t, pool)

	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, map[string]any{"total": "0.00", "accounts": []any{}}, got)
}

func TestInvestments_SplitsByOwnerAndProductAndMatchesHomeTotal(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)
	// Mesma instituição, outro titular: vira outra conta, nunca soma com a da Ana.
	exec(t, pool, `
		INSERT INTO items (id, owner, connector, status) VALUES
			('66666666-6666-4666-8666-666666666666', 'bia', 'MeuPluggy', 'UPDATED');
		INSERT INTO investments VALUES
			(gen_random_uuid(), '66666666-6666-4666-8666-666666666666', 'FIXED_INCOME', 'LCI Banco X', 'ACTIVE', 300.00,
				'{"subtype":"LCI","rateType":"CDI","rate":94,"dueDate":"2027-08-15T03:00:00.000Z","taxExempt":true,"currencyCode":"BRL"}'),
			(gen_random_uuid(), '66666666-6666-4666-8666-666666666666', 'FIXED_INCOME', 'CDB Banco Y', 'ACTIVE', 200.00,
				'{"subtype":"CDB","rateType":"IPCA","fixedAnnualRate":6.5}'),
			(gen_random_uuid(), '66666666-6666-4666-8666-666666666666', 'EQUITY', 'PETR4', 'ACTIVE', 7000.00,
				'{"subtype":"STOCK","code":"PETR4","quantity":200,"currencyCode":"BRL"}');
		UPDATE accounts SET raw = '{"bankData":{"reservedBalances":[
			{"name":"Viagem","availableAmounts":[{"amount":200.50,"currencyCode":"BRL","remuneration":{"indexer":"CDI","postFixedIndexerPercentage":1.149992}}]},
			{"name":"Vazia","availableAmounts":[{"amount":0}]}]}}' WHERE id = '`+checkingID+`';`)

	code, got := getInvestments(t, pool)
	_, home := getHome(t, pool, "")

	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, "13700.50", got["total"])
	assert.Equal(t, home["invested"], got["total"], "o detalhe soma o mesmo que a home")
	pos := func(name, balance string, extra map[string]any) map[string]any {
		p := map[string]any{"name": name, "balance": balance, "currency": "BRL", "code": nil, "quantity": nil,
			"indexer": nil, "rate": nil, "fixedRate": nil, "dueDate": nil, "taxExempt": nil}
		for k, v := range extra {
			p[k] = v
		}
		return p
	}
	assert.Equal(t, []any{
		map[string]any{"id": "66666666-6666-4666-8666-666666666666", "institution": "MeuPluggy", "owner": "bia", "manual": false, "total": "7500.00",
			"groups": []any{
				map[string]any{"kind": "STOCK", "total": "7000.00", "positions": []any{pos("PETR4", "7000.00", map[string]any{"code": "PETR4", "quantity": "200"})}},
				map[string]any{"kind": "LCI", "total": "300.00", "positions": []any{pos("LCI Banco X", "300.00",
					map[string]any{"indexer": "CDI", "rate": "94", "dueDate": "2027-08-15", "taxExempt": true})}},
				map[string]any{"kind": "CDB", "total": "200.00", "positions": []any{pos("CDB Banco Y", "200.00",
					map[string]any{"currency": "BRL", "indexer": "IPCA", "fixedRate": "6.5"})}},
			}},
		map[string]any{"id": "manual-1", "institution": "Carro", "owner": "ana", "manual": true, "total": "5000.00",
			"groups": []any{map[string]any{"kind": "MANUAL", "total": "5000.00", "positions": []any{pos("Carro", "5000.00", nil)}}}},
		map[string]any{"id": itemID, "institution": "MeuPluggy", "owner": "ana", "manual": false, "total": "1200.50",
			"groups": []any{
				// o investimento do seed não tem raw: cai no tipo; o resgatado e a caixinha zerada não aparecem
				map[string]any{"kind": "FIXED_INCOME", "total": "1000.00", "positions": []any{pos("CDB", "1000.00", nil)}},
				map[string]any{"kind": "RESERVE", "total": "200.50", "positions": []any{pos("Viagem", "200.50",
					map[string]any{"indexer": "CDI", "rate": "115.00"})}},
			}},
	}, got["accounts"])
}
