// Comando sync: copia os itens da Pluggy (env ITEMS=itemId,...; "dono:itemId" força o dono) para o Postgres (DATABASE_URL).
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"fyin/internal/pluggy"
	"fyin/internal/sync"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()
	// shortcut: um único par de credenciais; com a conta da esposa (outro app Pluggy) passar a credencial por dono.
	api := pluggy.New(os.Getenv("CLIENT_ID"), os.Getenv("CLIENT_SECRET"))

	pool, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal(err)
	}
	defer pool.Close()

	items := os.Getenv("ITEMS")
	if items == "" {
		log.Fatal("defina ITEMS=itemId[,itemId]")
	}
	failed := false
	for _, spec := range strings.Split(items, ",") {
		owner, id, ok := strings.Cut(strings.TrimSpace(spec), ":")
		if !ok {
			owner, id = "", owner
		}
		if owner == "" {
			full, err := api.Owner(ctx, id)
			if err != nil || full == "" {
				log.Printf("%s: ERRO sem dono (use dono:itemId): %v", id, err)
				failed = true
				continue
			}
			// o dono é um rótulo curto; o nome completo (dado pessoal) não é guardado
			owner = strings.ToLower(strings.Fields(full)[0])
		}
		res, err := sync.Item(ctx, pool, api, owner, id)
		if err != nil {
			log.Printf("%s %s: ERRO %v", owner, id, err)
			failed = true
			continue
		}
		fmt.Printf("%s %s: %d contas, %d faturas, %d transações, %d empréstimos, %d investimentos\n",
			owner, id, res.Accounts, res.Bills, res.Transactions, res.Loans, res.Investments)
	}
	divs, err := sync.Divergences(ctx, pool)
	if err != nil {
		log.Fatal(err)
	}
	for _, d := range divs {
		fmt.Printf("divergência %s %s %s: informado %s, calculado %s (diferença %s)\n",
			d.Kind, d.Account, d.Day, d.Reported, d.Calculated, d.Difference)
	}
	if failed {
		os.Exit(1)
	}
}
