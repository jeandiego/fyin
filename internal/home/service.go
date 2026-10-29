// Package home monta o resumo do mês exibido na tela inicial do app.
package home

import (
	"context"
	"time"
)

var saoPaulo = mustLoad("America/Sao_Paulo")

func mustLoad(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return loc
}

// monthsShown é quantos meses os seletores da home oferecem, terminando no mês atual.
const monthsShown = 3

type Summary struct {
	Month    string     `json:"month"`  // YYYY-MM
	Months   []string   `json:"months"` // seletores, do mais antigo ao atual
	SyncedAt *time.Time `json:"syncedAt"`
	Balance  string     `json:"balance"`  // saldo em contas no último dia do mês (ou agora, no mês atual)
	Invested string     `json:"invested"` // investimentos + patrimônio manual, valor atual
	Spending struct {
		Spent       string `json:"spent"`
		Goal        string `json:"goal"` // shortcut: sempre 0 até existir a funcionalidade de meta
		Day         int    `json:"day"`  // dia corrente no mês atual; último dia nos meses passados
		DaysInMonth int    `json:"daysInMonth"`
		// Since é o 1º dia com dados quando uma conexão começa no meio do mês ("Mês com dados parciais"); nil se o mês está completo.
		Since *string `json:"since"`
	} `json:"spending"`
	Card struct {
		Total       string  `json:"total"` // mês atual: faturas atuais (GET /v1/cards); passado: última fatura fechada de cada cartão
		ClosingDate *string `json:"closingDate"`
		DueDate     *string `json:"dueDate"`
	} `json:"card"`
	Loans struct {
		Total string `json:"total"` // saldo devedor atual
	} `json:"loans"`
}

type Service struct {
	store *Store
	now   func() time.Time
}

func NewService(store *Store, now func() time.Time) *Service { return &Service{store: store, now: now} }

// Month devolve o resumo de `month` (primeiro dia do mês, em São Paulo).
func (s *Service) Month(ctx context.Context, month time.Time) (Summary, error) {
	start := time.Date(month.Year(), month.Month(), 1, 0, 0, 0, 0, saoPaulo)
	end := start.AddDate(0, 1, 0)
	now := s.now().In(saoPaulo)
	current := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, saoPaulo)

	var sum Summary
	sum.Month = start.Format("2006-01")
	for i := monthsShown - 1; i >= 0; i-- {
		sum.Months = append(sum.Months, current.AddDate(0, -i, 0).Format("2006-01"))
	}
	sum.Spending.Goal = "0.00"
	sum.Spending.DaysInMonth = end.AddDate(0, 0, -1).Day()
	sum.Spending.Day = sum.Spending.DaysInMonth
	if start.Equal(current) {
		sum.Spending.Day = now.Day()
	}
	if err := s.store.figures(ctx, start, end, &sum); err != nil || !start.Equal(current) {
		return sum, err
	}
	return sum, s.store.currentCard(ctx, now, &sum)
}

// CurrentMonth é o mês corrente em São Paulo, o padrão quando o app não escolhe.
func (s *Service) CurrentMonth() time.Time { return s.now().In(saoPaulo) }
