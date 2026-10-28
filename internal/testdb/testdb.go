// Package testdb entrega um banco Postgres isolado por teste, clonado de um template migrado uma única vez.
package testdb

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"sort"
	"sync/atomic"
	"testing"

	"fyin/migrations"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	template string
	counter  atomic.Int64
)

func adminURL() string {
	if u := os.Getenv("TEST_ADMIN_DATABASE_URL"); u != "" {
		return u
	}
	return "postgres://fyin:fyin@localhost:5433/postgres"
}

func withDB(base, name string) string {
	u, err := url.Parse(base)
	if err != nil {
		panic(err)
	}
	u.Path = "/" + name
	return u.String()
}

func admin(ctx context.Context) (*pgx.Conn, error) { return pgx.Connect(ctx, adminURL()) }

// Main constrói o template (migrations rodam aqui, uma vez por pacote), executa os testes e o remove.
// Uso: func TestMain(m *testing.M) { testdb.Main(m) }
func Main(m *testing.M) {
	ctx := context.Background()
	template = fmt.Sprintf("fyin_tmpl_%d", os.Getpid())
	if err := build(ctx); err != nil {
		fmt.Fprintln(os.Stderr, "testdb: ", err)
		os.Exit(1)
	}
	code := m.Run()
	if c, err := admin(ctx); err == nil {
		c.Exec(ctx, "DROP DATABASE IF EXISTS "+template+" WITH (FORCE)")
		c.Close(ctx)
	}
	os.Exit(code)
}

func build(ctx context.Context) error {
	c, err := admin(ctx)
	if err != nil {
		return fmt.Errorf("conectar ao Postgres de teste (make up): %w", err)
	}
	defer c.Close(ctx)
	if _, err := c.Exec(ctx, "CREATE DATABASE "+template); err != nil {
		return err
	}
	t, err := pgx.Connect(ctx, withDB(adminURL(), template))
	if err != nil {
		return err
	}
	defer t.Close(ctx)

	entries, err := migrations.FS.ReadDir(".")
	if err != nil {
		return err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)
	for _, n := range names {
		sql, err := migrations.FS.ReadFile(n)
		if err != nil {
			return err
		}
		if _, err := t.Exec(ctx, string(sql)); err != nil {
			return fmt.Errorf("migration %s: %w", n, err)
		}
	}
	return nil
}

// New clona o template para um banco exclusivo do teste e o remove ao final.
func New(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()
	name := fmt.Sprintf("fyin_test_%d_%d", os.Getpid(), counter.Add(1))

	c, err := admin(ctx)
	if err != nil {
		t.Fatalf("admin: %v", err)
	}
	defer c.Close(ctx)
	if _, err := c.Exec(ctx, fmt.Sprintf("CREATE DATABASE %s TEMPLATE %s", name, template)); err != nil {
		t.Fatalf("clonar template: %v", err)
	}
	pool, err := pgxpool.New(ctx, withDB(adminURL(), name))
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(func() {
		pool.Close()
		if c, err := admin(ctx); err == nil {
			c.Exec(ctx, "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
			c.Close(ctx)
		}
	})
	return pool
}
