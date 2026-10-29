// Package fx mantém a cotação diária do dólar (PTAX de venda, Banco Central) em fx_rates.
package fx

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var saoPaulo = mustLoc("America/Sao_Paulo")

func mustLoc(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return loc
}

const retryAfter = 10 * time.Minute

type Service struct {
	BaseURL string // padrão do Olinda/BCB; sobrescrito nos testes
	pool    *pgxpool.Pool
	http    *http.Client
	now     func() time.Time
	mu      sync.Mutex // serializa a busca: várias requisições do app chegam juntas
	lastTry time.Time
}

func NewService(pool *pgxpool.Pool, now func() time.Time) *Service {
	return &Service{
		BaseURL: "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata",
		pool:    pool, http: &http.Client{Timeout: 5 * time.Second}, now: now,
	}
}

// Refresh busca a cotação se ainda não buscou hoje. Falha não derruba ninguém: o app segue com a última gravada,
// e uma nova tentativa só acontece depois de retryAfter.
func (s *Service) Refresh(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := s.now()
	today := now.In(saoPaulo).Format(time.DateOnly)
	var done bool
	if err := s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM fx_rates WHERE (fetched_at AT TIME ZONE 'America/Sao_Paulo')::date = $1::date)`, today).Scan(&done); err != nil || done {
		return err
	}
	if now.Sub(s.lastTry) < retryAfter {
		return nil
	}
	s.lastTry = now

	day, rate, err := s.latest(ctx, now)
	if err != nil {
		return err
	}
	// Em fim de semana a última cotação é a de sexta: o upsert só renova o fetched_at.
	_, err = s.pool.Exec(ctx, `
		INSERT INTO fx_rates (day, usd_brl, fetched_at) VALUES ($1::date, $2::numeric, $3)
		ON CONFLICT (day) DO UPDATE SET usd_brl = EXCLUDED.usd_brl, fetched_at = EXCLUDED.fetched_at`, day, rate, now)
	return err
}

// latest devolve a PTAX de venda mais recente dos últimos 10 dias (cobre feriados prolongados).
func (s *Service) latest(ctx context.Context, now time.Time) (day, rate string, err error) {
	end := now.In(saoPaulo)
	q := url.Values{}
	q.Set("@dataInicial", "'"+end.AddDate(0, 0, -10).Format("01-02-2006")+"'")
	q.Set("@dataFinalCotacao", "'"+end.Format("01-02-2006")+"'")
	q.Set("$top", "1")
	q.Set("$orderby", "dataHoraCotacao desc")
	q.Set("$select", "cotacaoVenda,dataHoraCotacao")
	q.Set("$format", "json")
	req, err := http.NewRequestWithContext(ctx, "GET",
		// O Olinda rejeita "+" como espaço no $orderby: só aceita %20.
		s.BaseURL+"/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)?"+strings.ReplaceAll(q.Encode(), "+", "%20"), nil)
	if err != nil {
		return "", "", err
	}
	resp, err := s.http.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", "", fmt.Errorf("ptax: status %d", resp.StatusCode)
	}
	var body struct {
		Value []struct {
			Sell json.Number `json:"cotacaoVenda"`
			At   string      `json:"dataHoraCotacao"` // "2026-10-28 13:06:52.123"
		} `json:"value"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", "", err
	}
	if len(body.Value) == 0 || len(body.Value[0].At) < 10 {
		return "", "", fmt.Errorf("ptax: sem cotação nos últimos 10 dias")
	}
	return body.Value[0].At[:10], body.Value[0].Sell.String(), nil
}

// Refresher atualiza a cotação antes de cada requisição; a requisição segue mesmo se a busca falhar.
func Refresher(s *Service, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := s.Refresh(r.Context()); err != nil {
			log.Printf("fx refresh: %v", err)
		}
		next.ServeHTTP(w, r)
	})
}
