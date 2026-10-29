// Package cards detalha o card "Cartão" da home: cada cartão com todas as faturas e os lançamentos delas.
package cards

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Overview struct {
	Total string `json:"total"` // soma das faturas atuais; igual ao card da home no mês atual
	Cards []Card `json:"cards"`
}

// Card é uma conta CREDIT da Pluggy: cartões do mesmo banco nunca se somam.
type Card struct {
	ID          string  `json:"id"`
	Institution string  `json:"institution"`
	Owner       string  `json:"owner"`
	Name        string  `json:"name"`
	Last4       *string `json:"last4"`
	Current     string  `json:"current"` // período da fatura atual
	Bills       []Bill  `json:"bills"`   // da mais antiga à última futura
}

type Bill struct {
	Period      string  `json:"period"` // YYYY-MM do vencimento
	Status      string  `json:"status"` // paid | partial | closed | overdue | open | future
	OpeningDate string  `json:"openingDate"`
	ClosingDate string  `json:"closingDate"` // aberta e futuras: estimado
	DueDate     string  `json:"dueDate"`
	Total       string  `json:"total"`
	Paid        string  `json:"paid"`
	PaidOn      *string `json:"paidOn"`
	Lines       []Line  `json:"lines"`
}

type Line struct {
	Date         string  `json:"date"`
	Description  string  `json:"description"`
	Amount       string  `json:"amount"` // estorno negativo
	Installment  *int    `json:"installment"`
	Installments *int    `json:"installments"`
	PurchaseDate *string `json:"purchaseDate"` // da compra parcelada
}

type Store struct{ pool *pgxpool.Pool }

func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Overview monta as faturas em `now` (dia em São Paulo). Cartões por vencimento da fatura atual.
func (st *Store) Overview(ctx context.Context, now time.Time) (Overview, error) {
	rows, err := st.pool.Query(ctx, `
		WITH b AS (SELECT * FROM card_bills(($1::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date))
		SELECT a.id::text,
			-- shortcut: o MeuPluggy daqui só conecta o Bradesco; trocar pelo nome da instituição se conectar outro.
			CASE i.connector WHEN 'MeuPluggy' THEN 'Bradesco' ELSE i.connector END, i.owner, a.name,
			-- shortcut: o 1º limite é o do cartão titular; trocar se a Pluggy mandar o número do cartão.
			a.raw#>>'{creditData,disaggregatedCreditLimits,0,identificationNumber}',
			c.period, b.period, b.status, b.opening_date::text, b.closing_date::text, b.due_date::text,
			b.total::text, b.paid::text, b.paid_on::text,
			(SELECT coalesce(sum(total), 0)::numeric(14,2)::text FROM b WHERE is_current),
			t.id IS NOT NULL, coalesce((t.date AT TIME ZONE 'America/Sao_Paulo')::date::text, ''), coalesce(t.description, ''),
			coalesce(t.amount::text, ''), t.installment_number, t.total_installments,
			((t.raw#>>'{creditCardMetadata,purchaseDate}')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date::text
		FROM b JOIN accounts a ON a.id = b.account_id JOIN items i ON i.id = a.item_id
		JOIN b c ON c.account_id = b.account_id AND c.is_current
		LEFT JOIN card_bill_lines l ON l.account_id = b.account_id AND l.period = b.period
		LEFT JOIN transactions t ON t.id = l.transaction_id
		ORDER BY c.due_date, i.connector, a.id, b.period, t.date DESC, t.description`, now)
	if err != nil {
		return Overview{}, err
	}
	defer rows.Close()

	out := Overview{Total: "0.00", Cards: []Card{}}
	for rows.Next() {
		var c Card
		var b Bill
		var l Line
		var hasLine bool
		if err := rows.Scan(&c.ID, &c.Institution, &c.Owner, &c.Name, &c.Last4, &c.Current,
			&b.Period, &b.Status, &b.OpeningDate, &b.ClosingDate, &b.DueDate, &b.Total, &b.Paid, &b.PaidOn, &out.Total,
			&hasLine, &l.Date, &l.Description, &l.Amount, &l.Installment, &l.Installments, &l.PurchaseDate); err != nil {
			return Overview{}, err
		}
		n := len(out.Cards)
		if n == 0 || out.Cards[n-1].ID != c.ID {
			out.Cards = append(out.Cards, c)
			n++
		}
		card := &out.Cards[n-1]
		if m := len(card.Bills); m == 0 || card.Bills[m-1].Period != b.Period {
			b.Lines = []Line{}
			card.Bills = append(card.Bills, b)
		}
		if hasLine {
			last := &card.Bills[len(card.Bills)-1]
			last.Lines = append(last.Lines, l)
		}
	}
	return out, rows.Err()
}
