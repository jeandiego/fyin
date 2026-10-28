package integrationtests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"fyin/internal/home"
	"fyin/internal/sync"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// 28/10/2026 às 10h em São Paulo.
var homeNow = time.Date(2026, 10, 28, 13, 0, 0, 0, time.UTC)

func getHome(t *testing.T, pool *pgxpool.Pool, query string) (int, map[string]any) {
	t.Helper()
	mux := http.NewServeMux()
	home.NewHandler(home.NewService(home.NewStore(pool), func() time.Time { return homeNow })).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/home"+query, nil))
	var body map[string]any
	if rec.Code == http.StatusOK {
		require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &body))
	}
	return rec.Code, body
}

func exec(t *testing.T, pool *pgxpool.Pool, sql string) {
	t.Helper()
	_, err := pool.Exec(context.Background(), sql)
	require.NoError(t, err)
}

// seedHome cria conta corrente com saldo informado em 27/10, cartão com duas faturas fechadas,
// empréstimo, investimentos e patrimônio manual. Valores escolhidos para cada regra mudar o total.
func seedHome(t *testing.T, pool *pgxpool.Pool) {
	exec(t, pool, `
		INSERT INTO items (id, owner, connector, status, synced_at) VALUES
			('`+itemID+`', 'ana', 'MeuPluggy', 'UPDATED', '2026-10-27T12:00:00Z');
		INSERT INTO accounts (id, item_id, type, subtype, name, balance, raw) VALUES
			('`+checkingID+`', '`+itemID+`', 'BANK', 'CHECKING_ACCOUNT', 'Conta', 1000.00,
				'{"bankData":{"reservedBalances":[{"availableAmounts":[{"amount":200.50}]},{"availableAmounts":[{"amount":0}]}]}}'),
			('`+cardID+`', '`+itemID+`', 'CREDIT', 'CREDIT_CARD', 'Cartao', 9999.00, '{}');
		INSERT INTO balance_snapshots VALUES ('`+checkingID+`', '2026-10-27T12:00:00Z', 1000.00);
		INSERT INTO transactions (id, account_id, date, description, amount, type, status, category, raw) VALUES
			(gen_random_uuid(), '`+checkingID+`', '2026-09-20T12:00:00Z', 'Padaria',        -100.00, 'DEBIT',  'POSTED', NULL, '{}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-05T12:00:00Z', 'Financiamento',  -300.00, 'DEBIT',  'POSTED', 'Real estate financing', '{}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-10T12:00:00Z', 'Pagto fatura',   -500.00, 'DEBIT',  'POSTED', 'Credit card fees', '{}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-12T12:00:00Z', 'Salario',        2000.00, 'CREDIT', 'POSTED', 'Transfer - PIX', '{}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-14T12:00:00Z', 'Pagamento de fatura', -700.00, 'DEBIT', 'POSTED', 'Transfers', '{"operationTypeAdditionalInfo":"PAGAMENTO_FATURA"}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-14T13:00:00Z', 'Pagamento de fatura Cartão de crédito', -80.00, 'DEBIT', 'POSTED', 'Transfers', '{}'),
			(gen_random_uuid(), '`+checkingID+`', '2026-10-15T12:00:00Z', 'Pix para Fulano', -25.00, 'DEBIT', 'POSTED', 'Transfers', '{}'),
			(gen_random_uuid(), '`+cardID+`',     '2026-10-01T02:30:00Z', 'Mercado 30/09',    70.00, 'DEBIT',  'POSTED', 'Groceries', '{}'),
			(gen_random_uuid(), '`+cardID+`',     '2026-10-03T12:00:00Z', 'Loja',            200.00, 'DEBIT',  'POSTED', 'Shopping', '{}'),
			(gen_random_uuid(), '`+cardID+`',     '2026-10-04T12:00:00Z', 'Estorno loja',    -50.00, 'CREDIT', 'POSTED', 'Shopping', '{}'),
			(gen_random_uuid(), '`+cardID+`',     '2026-10-06T12:00:00Z', 'Pagamento',      -500.00, 'CREDIT', 'POSTED', 'Credit card payment', '{}');
		INSERT INTO bills (id, account_id, due_date, closing_date, total, raw) VALUES
			(gen_random_uuid(), '`+cardID+`', '2026-09-15', '2026-09-02', 300.00, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-10-15', '2026-10-02', 450.00, '{}');
		INSERT INTO loans VALUES (gen_random_uuid(), '`+itemID+`', 'Financiamento', 48900.00, '{}');
		INSERT INTO investments VALUES
			(gen_random_uuid(), '`+itemID+`', 'FIXED_INCOME', 'CDB', 'ACTIVE', 1000.00, '{}'),
			(gen_random_uuid(), '`+itemID+`', 'FIXED_INCOME', 'CDB resgatado', 'TOTAL_WITHDRAWAL', 99.00, '{}');
		INSERT INTO manual_assets (owner, name, value) VALUES ('ana', 'Carro', 5000.00);`)
}

func TestHome_WithoutDataShowsZeros(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)

	code, got := getHome(t, pool, "")

	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, map[string]any{
		"month": "2026-10", "months": []any{"2026-08", "2026-09", "2026-10"}, "syncedAt": nil,
		"balance": "0.00", "invested": "0.00",
		"spending": map[string]any{"spent": "0.00", "goal": "0.00", "day": 28.0, "daysInMonth": 31.0, "since": nil},
		"card":     map[string]any{"total": "0.00", "closingDate": nil, "dueDate": nil},
		"loans":    map[string]any{"total": "0.00"},
	}, got)
}

func TestHome_CurrentMonthCountsOnlyRealSpending(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)

	code, got := getHome(t, pool, "?month=2026-10")

	require.Equal(t, http.StatusOK, code)
	assert.Equal(t, "1000.00", got["balance"])
	assert.Equal(t, "6200.50", got["invested"], "investimento ativo + patrimônio manual + reservas da conta, sem o resgatado")
	// financiamento 300 + pix 25 + loja 200 - estorno 50; fora: pagamentos de fatura (categoria, marcador e descrição),
	// salário e a compra de 30/09 às 23h30
	assert.Equal(t, map[string]any{"spent": "475.00", "goal": "0.00", "day": 28.0, "daysInMonth": 31.0, "since": nil}, got["spending"])
	assert.Equal(t, map[string]any{"total": "450.00", "closingDate": "2026-10-02", "dueDate": "2026-10-15"}, got["card"])
	assert.Equal(t, map[string]any{"total": "48900.00"}, got["loans"])
	synced, err := time.Parse(time.RFC3339, got["syncedAt"].(string))
	require.NoError(t, err)
	assert.True(t, synced.Equal(time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)))
}

func TestHome_TransferBetweenFamilyAccountsIsNotSpending(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)
	// PIX de 150 da conta da Ana para a conta do outro dono, que recebe no mesmo dia.
	exec(t, pool, `
		INSERT INTO accounts (id, item_id, type, subtype, name, balance, raw) VALUES
			('55555555-5555-4555-8555-555555555555', '`+itemID+`', 'BANK', 'CHECKING_ACCOUNT', 'Conta 2', 0, '{}');
		INSERT INTO transactions (id, account_id, date, description, amount, type, status, category, raw) VALUES
			(gen_random_uuid(), '`+checkingID+`', '2026-10-20T12:00:00Z', 'Pix enviado', -150.00, 'DEBIT', 'POSTED', 'Transfers', '{}'),
			(gen_random_uuid(), '55555555-5555-4555-8555-555555555555', '2026-10-20T12:00:05Z', 'Pix recebido', 150.00, 'CREDIT', 'POSTED', 'Transfers', '{}');`)

	_, got := getHome(t, pool, "?month=2026-10")

	assert.Equal(t, "475.00", got["spending"].(map[string]any)["spent"])
}

func TestHome_PastMonthRewindsBalanceToItsLastDay(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)

	code, got := getHome(t, pool, "?month=2026-09")

	require.Equal(t, http.StatusOK, code)
	// 1000 hoje, desfazendo as movimentações de outubro (-300 -500 +2000 -700 -80 -25)
	assert.Equal(t, "605.00", got["balance"])
	// a conexão só tem dados a partir de 20/09: mês parcial
	assert.Equal(t, map[string]any{"spent": "170.00", "goal": "0.00", "day": 30.0, "daysInMonth": 30.0, "since": "2026-09-20"}, got["spending"])
	assert.Equal(t, map[string]any{"total": "300.00", "closingDate": "2026-09-02", "dueDate": "2026-09-15"}, got["card"])
}

func TestHome_RejectsInvalidMonth(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)

	code, _ := getHome(t, pool, "?month=outubro")

	assert.Equal(t, http.StatusBadRequest, code)
}

func TestDivergences_FlagsMissingTransactionsAndBillsThatDoNotAddUp(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)
	// Sync seguinte: o banco informa 900, mas só chegou uma saída de 50 desde o snapshot anterior.
	exec(t, pool, `
		INSERT INTO balance_snapshots VALUES ('`+checkingID+`', '2026-10-28T12:00:00Z', 900.00);
		INSERT INTO transactions (id, account_id, date, description, amount, type, status, raw) VALUES
			(gen_random_uuid(), '`+checkingID+`', '2026-10-28T09:00:00Z', 'Farmacia', -50.00, 'DEBIT', 'POSTED', '{}');`)

	got, err := sync.Divergences(context.Background(), pool)

	require.NoError(t, err)
	assert.Equal(t, []sync.Divergence{
		{Kind: "saldo", Account: "Conta", Day: "2026-10-28", Reported: "900.00", Calculated: "950.00", Difference: "-50.00"},
		// ciclo (02/09, 02/10]: só a compra de 30/09 (70) foi lançada, a fatura diz 450
		{Kind: "fatura", Account: "Cartao", Day: "2026-10-02", Reported: "450.00", Calculated: "70.00", Difference: "380.00"},
	}, got)
}

func TestDivergences_ExcludedPurchaseKeepsBillCheckAndAckHidesIt(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedHome(t, pool)
	// Compra cancelada tirada do gasto: a fatura continua sendo comparada com o que o cartão lançou.
	exec(t, pool, `INSERT INTO spending_description_exclusions VALUES ('CREDIT', 'Mercado%', 'compra cancelada')`)

	_, sep := getHome(t, pool, "?month=2026-09")
	divs, err := sync.Divergences(context.Background(), pool)

	require.NoError(t, err)
	assert.Equal(t, "100.00", sep["spending"].(map[string]any)["spent"], "a compra de 30/09 saiu do gasto")
	require.Len(t, divs, 1)
	assert.Equal(t, "70.00", divs[0].Calculated, "a fatura ainda soma a compra excluída")

	exec(t, pool, `INSERT INTO divergence_acks VALUES ('fatura', '`+cardID+`', '2026-10-02', 'explicada')`)
	divs, err = sync.Divergences(context.Background(), pool)
	require.NoError(t, err)
	assert.Empty(t, divs)
}
