package pluggy_test

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"fyin/internal/pluggy"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// newServer simula a Pluggy: /auth entrega a chave e as demais rotas exigem essa chave.
func newServer(t *testing.T, routes map[string]string) *pluggy.Client {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/auth", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"apiKey":"chave-teste"}`) })
	for path, body := range routes {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("X-API-KEY") != "chave-teste" {
				http.Error(w, `{"message":"sem chave"}`, http.StatusForbidden)
				return
			}
			if after := r.URL.Query().Get("after"); after != "" {
				fmt.Fprint(w, routes[path+"?after"])
				return
			}
			fmt.Fprint(w, body)
		})
	}
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	c := pluggy.New("id", "segredo")
	c.BaseURL = srv.URL
	return c
}

func TestTransactions_FollowsNextCursorToTheLastPage(t *testing.T) {
	t.Parallel()
	c := newServer(t, map[string]string{
		"/v2/transactions":       `{"results":[{"id":"t1"}],"next":"?accountId=acc&after=cursor1"}`,
		"/v2/transactions?after": `{"results":[{"id":"t2"}],"next":null}`,
	})

	got, err := c.Transactions(context.Background(), "acc")

	require.NoError(t, err)
	require.Len(t, got, 2)
	assert.Equal(t, []string{"t1", "t2"}, []string{got[0].ID, got[1].ID})
}

func TestBills_ReadsEveryPage(t *testing.T) {
	t.Parallel()
	mux := http.NewServeMux()
	mux.HandleFunc("/auth", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"apiKey":"k"}`) })
	mux.HandleFunc("/bills", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{"totalPages":2,"results":[{"id":"bill-p%s"}]}`, r.URL.Query().Get("page"))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	c := pluggy.New("id", "segredo")
	c.BaseURL = srv.URL

	got, err := c.Bills(context.Background(), "acc")

	require.NoError(t, err)
	require.Len(t, got, 2)
	assert.Equal(t, []string{"bill-p1", "bill-p2"}, []string{got[0].ID, got[1].ID})
}

func TestItem_ReportsHTTPErrorStatus(t *testing.T) {
	t.Parallel()
	mux := http.NewServeMux()
	mux.HandleFunc("/auth", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"apiKey":"k"}`) })
	mux.HandleFunc("/items/", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"message":"item inexistente"}`, http.StatusNotFound)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	c := pluggy.New("id", "segredo")
	c.BaseURL = srv.URL

	_, err := c.Item(context.Background(), "x")

	require.ErrorContains(t, err, "404")
}

func TestRefresh_PatchesTheItemWithEmptyBody(t *testing.T) {
	t.Parallel()
	mux := http.NewServeMux()
	mux.HandleFunc("/auth", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"apiKey":"k"}`) })
	mux.HandleFunc("/items/abc", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PATCH" || r.Header.Get("X-API-KEY") != "k" {
			http.Error(w, `{"message":"pedido errado"}`, http.StatusBadRequest)
			return
		}
		fmt.Fprint(w, `{"id":"abc","status":"UPDATING"}`)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	c := pluggy.New("id", "segredo")
	c.BaseURL = srv.URL

	it, err := c.Refresh(context.Background(), "abc")

	require.NoError(t, err)
	assert.Equal(t, "UPDATING", it.Status)
}
