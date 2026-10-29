package integrationtests

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"fyin/internal/fx"
	"fyin/internal/testdb"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFx_RefreshStoresLatestPtaxOncePerDay(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		assert.Contains(t, r.URL.Path, "CotacaoDolarPeriodo")
		assert.NotContains(t, r.URL.RawQuery, "+", "o BCB só aceita %20 como espaço")
		// sábado: o BCB devolve a cotação de sexta
		fmt.Fprint(w, `{"value":[{"cotacaoVenda":5.4512,"dataHoraCotacao":"2026-10-30 13:06:52.123"}]}`)
	}))
	t.Cleanup(srv.Close)
	now := time.Date(2026, 10, 31, 15, 0, 0, 0, time.UTC)
	svc := fx.NewService(pool, func() time.Time { return now })
	svc.BaseURL = srv.URL

	require.NoError(t, svc.Refresh(t.Context()))
	require.NoError(t, svc.Refresh(t.Context()))

	var day, rate string
	require.NoError(t, pool.QueryRow(t.Context(), `SELECT day::text, usd_brl::text FROM fx_rates`).Scan(&day, &rate))
	assert.Equal(t, "2026-10-30", day)
	assert.Equal(t, "5.4512", rate)
	assert.EqualValues(t, 1, calls.Load(), "a segunda chamada do dia não busca de novo")
}

func TestFx_FailureKeepsLastRate(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	exec(t, pool, `INSERT INTO fx_rates (day, usd_brl, fetched_at) VALUES ('2026-10-27', 5.0000, '2026-10-27T15:00:00Z')`)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "fora do ar", 503) }))
	t.Cleanup(srv.Close)
	svc := fx.NewService(pool, func() time.Time { return time.Date(2026, 10, 28, 15, 0, 0, 0, time.UTC) })
	svc.BaseURL = srv.URL

	require.Error(t, svc.Refresh(t.Context()))

	var rate string
	require.NoError(t, pool.QueryRow(t.Context(), `SELECT rate::text FROM usd_brl`).Scan(&rate))
	assert.Equal(t, "5.0000", rate)
}
