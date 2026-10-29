// Comando api: serve o app iOS a partir do Postgres (DATABASE_URL), protegido por API_TOKEN.
// CLIENT_ID e CLIENT_SECRET (Pluggy) servem ao botão de sincronizar.
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"net/http"
	"os"
	"time"

	"fyin/internal/cards"
	"fyin/internal/fx"
	"fyin/internal/home"
	"fyin/internal/investments"
	"fyin/internal/items"
	"fyin/internal/pluggy"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	token := os.Getenv("API_TOKEN")
	if token == "" {
		log.Fatal("defina API_TOKEN")
	}
	// shortcut: só localhost (Simulator); ao subir na nuvem, trocar por TLS e auth por usuário.
	addr := os.Getenv("API_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8080"
	}

	pool, err := pgxpool.New(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	mux := http.NewServeMux()
	home.NewHandler(home.NewService(home.NewStore(pool), time.Now)).Register(mux)
	investments.NewHandler(investments.NewStore(pool)).Register(mux)
	cards.NewHandler(cards.NewStore(pool), time.Now).Register(mux)
	// shortcut: um único par de credenciais Pluggy, como no cmd/sync.
	items.NewHandler(items.NewService(pool, pluggy.New(os.Getenv("CLIENT_ID"), os.Getenv("CLIENT_SECRET")), time.Now)).Register(mux)

	log.Printf("api em http://%s", addr)
	log.Fatal(http.ListenAndServe(addr, bearer(token, fx.Refresher(fx.NewService(pool, time.Now), mux))))
}

func bearer(token string, next http.Handler) http.Handler {
	want := []byte("Bearer " + token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), want) != 1 {
			http.Error(w, `{"error":"não autorizado"}`, http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}
