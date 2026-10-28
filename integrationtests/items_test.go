package integrationtests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"fyin/internal/items"
	"fyin/internal/sync"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newItemsAPI sobe o sync do app sobre um item já importado uma vez (saldo da conta: 100.50).
func newItemsAPI(t *testing.T, fake *fakePluggy) (*pgxpool.Pool, http.Handler) {
	t.Helper()
	pool := testdb.New(t)
	_, err := sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)
	svc := items.NewService(pool, fake, time.Now)
	svc.Poll = time.Millisecond
	mux := http.NewServeMux()
	items.NewHandler(svc).Register(mux)
	return pool, mux
}

func call(t *testing.T, h http.Handler, method, path string) (int, map[string]any) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, nil))
	var body map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	return rec.Code, body
}

func syncState(t *testing.T, h http.Handler) string {
	t.Helper()
	_, body := call(t, h, "GET", "/v1/items/"+itemID)
	return body["sync"].(map[string]any)["state"].(string)
}

func waitFinished(t *testing.T, h http.Handler) string {
	t.Helper()
	var got string
	require.Eventually(t, func() bool {
		got = syncState(t, h)
		return got == items.Succeeded || got == items.Failed
	}, 5*time.Second, 5*time.Millisecond)
	return got
}

func checkingBalance(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	var b string
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT balance::text FROM accounts WHERE id=$1`, checkingID).Scan(&b))
	return b
}

func TestItemsSync_AsksPluggyToRefreshThenImports(t *testing.T) {
	t.Parallel()
	fake := newFake()
	pool, h := newItemsAPI(t, fake)
	fake.accounts[0].Balance = "250.00"
	fake.statuses = []string{"UPDATING", "UPDATED"}

	code, body := call(t, h, "POST", "/v1/items/"+itemID+"/sync")

	assert.Equal(t, http.StatusAccepted, code)
	assert.Equal(t, items.Running, body["state"])
	assert.Equal(t, items.Succeeded, waitFinished(t, h))
	assert.Equal(t, int32(1), fake.refreshCalls.Load())
	assert.Equal(t, "250.00", checkingBalance(t, pool))
	_, item := call(t, h, "GET", "/v1/items/"+itemID)
	assert.EqualValues(t, 2, item["sync"].(map[string]any)["result"].(map[string]any)["accounts"])
}

func TestItemsSync_BankAskingForActionFailsAndKeepsData(t *testing.T) {
	t.Parallel()
	fake := newFake()
	pool, h := newItemsAPI(t, fake)
	fake.accounts[0].Balance = "999.00"
	fake.statuses = []string{"LOGIN_ERROR"}

	call(t, h, "POST", "/v1/items/"+itemID+"/sync")

	assert.Equal(t, items.Failed, waitFinished(t, h))
	assert.Equal(t, "100.50", checkingBalance(t, pool), "o dado anterior não pode ser trocado")
	_, item := call(t, h, "GET", "/v1/items/"+itemID)
	assert.Equal(t, "LOGIN_ERROR", item["status"])
	assert.Contains(t, item["sync"].(map[string]any)["error"], "LOGIN_ERROR")
}

func TestItemsSync_WhileRunningDoesNotAskPluggyAgain(t *testing.T) {
	t.Parallel()
	fake := newFake()
	_, h := newItemsAPI(t, fake)
	fake.gate = make(chan struct{})

	c1, _ := call(t, h, "POST", "/v1/items/"+itemID+"/sync")
	c2, second := call(t, h, "POST", "/v1/items/"+itemID+"/sync")
	close(fake.gate)

	assert.Equal(t, http.StatusAccepted, c1)
	assert.Equal(t, http.StatusAccepted, c2)
	assert.Equal(t, items.Running, second["state"])
	assert.Equal(t, items.Succeeded, waitFinished(t, h))
	assert.Equal(t, int32(1), fake.refreshCalls.Load())
}

func TestItemsSync_UnknownItemIsNotFound(t *testing.T) {
	t.Parallel()
	_, h := newItemsAPI(t, newFake())

	for _, path := range []string{
		"/v1/items/99999999-9999-4999-8999-999999999999/sync",
		"/v1/items/nao-e-uuid/sync",
		"/v1/items/99999999-9999-4999-8999-999999999999",
	} {
		method := "POST"
		if path[len(path)-4:] != "sync" {
			method = "GET"
		}
		code, _ := call(t, h, method, path)
		assert.Equal(t, http.StatusNotFound, code, path)
	}
}

func TestItems_ListShowsConnectedItemsIdleUntilSynced(t *testing.T) {
	t.Parallel()
	fake := newFake()
	_, h := newItemsAPI(t, fake)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/items", nil))
	var list []map[string]any
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &list))

	require.Len(t, list, 1)
	assert.Equal(t, "ana", list[0]["owner"])
	assert.EqualValues(t, 2, list[0]["accounts"])
	assert.Equal(t, items.Idle, list[0]["sync"].(map[string]any)["state"])
}

func TestItemsSyncAll_StartsEveryItem(t *testing.T) {
	t.Parallel()
	fake := newFake()
	_, h := newItemsAPI(t, fake)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/v1/sync", nil))

	assert.Equal(t, http.StatusAccepted, rec.Code)
	assert.Equal(t, items.Succeeded, waitFinished(t, h))
	assert.Equal(t, int32(1), fake.refreshCalls.Load())
}
