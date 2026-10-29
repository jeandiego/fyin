package integrationtests

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"fyin/internal/cards"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	bradescoItem = "66666666-6666-4666-8666-666666666666"
	bradescoCard = "77777777-7777-4777-8777-777777777777"
)

func getCards(t *testing.T, pool *pgxpool.Pool, now time.Time) cards.Overview {
	t.Helper()
	mux := http.NewServeMux()
	cards.NewHandler(cards.NewStore(pool), func() time.Time { return now }).Register(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/cards", nil))
	require.Equal(t, http.StatusOK, rec.Code)
	var got cards.Overview
	require.NoError(t, json.Unmarshal(rec.Body.Bytes(), &got))
	return got
}

// seedCards: Nubank do Jean (fecha 3, vence 10) com setembro e outubro pagos, novembro aberto e parcelas até janeiro;
// Bradesco da Poliana (fecha 20, vence 25) com outubro sem pagamento e compra sem bill_id (o banco liga errado).
func seedCards(t *testing.T, pool *pgxpool.Pool) {
	exec(t, pool, `
		INSERT INTO items (id, owner, connector, status) VALUES
			('`+itemID+`', 'jean', 'Nubank', 'UPDATED'), ('`+bradescoItem+`', 'poliana', 'MeuPluggy', 'UPDATED');
		INSERT INTO accounts (id, item_id, type, subtype, name, balance, raw) VALUES
			('`+cardID+`', '`+itemID+`', 'CREDIT', 'CREDIT_CARD', 'platinum', 0,
				'{"creditData":{"disaggregatedCreditLimits":[{"identificationNumber":"4821"},{"identificationNumber":"9999"}]}}'),
			('`+bradescoCard+`', '`+bradescoItem+`', 'CREDIT', 'CREDIT_CARD', 'VISA INFINITE', 0, '{}');
		INSERT INTO bills (id, account_id, due_date, closing_date, total, raw) VALUES
			('`+billID+`', '`+cardID+`', '2026-10-10', '2026-10-03', 300.00, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-09-10', '2026-09-03', 1000.00, '{}'),
			(gen_random_uuid(), '`+bradescoCard+`', '2026-10-25', '2026-10-20', 318.60, '{}');
		INSERT INTO transactions (id, account_id, date, description, amount, type, status, category, bill_id, bill_forecast, installment_number, total_installments, raw) VALUES
			(gen_random_uuid(), '`+cardID+`', '2026-09-08T15:00:00Z', 'Pagamento', -1000.00, 'CREDIT', 'POSTED', 'Credit card payment', NULL, NULL, NULL, NULL, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-09-20T15:00:00Z', 'Pão de Açúcar', 200.00, 'DEBIT', 'POSTED', 'Groceries', '`+billID+`', NULL, NULL, NULL, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-09-25T15:00:00Z', 'Netflix', 100.00, 'DEBIT', 'POSTED', 'Digital services', '`+billID+`', NULL, NULL, NULL, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-10-08T15:00:00Z', 'Pagamento', -300.00, 'CREDIT', 'POSTED', 'Credit card payment', NULL, '2026-11', NULL, NULL, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-10-25T15:00:00Z', 'iFood', 64.90, 'DEBIT', 'PENDING', 'Eating out', NULL, '2026-11', NULL, NULL, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-10-27T15:00:00Z', 'Amazon', 83.48, 'DEBIT', 'PENDING', 'Shopping', NULL, '2026-11', 1, 3,
				'{"creditCardMetadata":{"purchaseDate":"2026-10-27T15:00:00Z"}}'),
			(gen_random_uuid(), '`+cardID+`', '2026-11-27T15:00:00Z', 'Amazon', 83.48, 'DEBIT', 'PENDING', 'Shopping', NULL, '2026-12', 2, 3, '{}'),
			(gen_random_uuid(), '`+cardID+`', '2026-12-27T15:00:00Z', 'Amazon', 83.48, 'DEBIT', 'PENDING', 'Shopping', NULL, '2027-01', 3, 3, '{}'),
			(gen_random_uuid(), '`+bradescoCard+`', '2026-10-05T15:00:00Z', 'Smart Fit', 318.60, 'DEBIT', 'POSTED', 'Gym', NULL, NULL, NULL, NULL, '{}');`)
}

func statuses(c cards.Card) map[string]string {
	out := map[string]string{}
	for _, b := range c.Bills {
		out[b.Period] = b.Status
	}
	return out
}

func TestCards_WithoutDataIsEmpty(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)

	got := getCards(t, pool, homeNow)

	assert.Equal(t, cards.Overview{Total: "0.00", Cards: []cards.Card{}}, got)
}

func TestCards_EachCardOpensOnItsCurrentBill(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedCards(t, pool)

	got := getCards(t, pool, homeNow) // 28/10

	require.Len(t, got.Cards, 2)
	brad, nu := got.Cards[0], got.Cards[1]
	assert.Equal(t, "466.98", got.Total, "vencida do Bradesco 318,60 + aberta do Nubank 148,38")

	// Por vencimento da fatura atual: a vencida (25/10) antes da aberta (10/11).
	assert.Equal(t, "Bradesco", brad.Institution)
	assert.Equal(t, "2026-10", brad.Current, "a mais antiga com saldo")
	assert.Equal(t, map[string]string{"2026-10": "overdue", "2026-11": "open", "2026-12": "future"}, statuses(brad))
	oct := brad.Bills[0]
	assert.Equal(t, "2026-09-21", oct.OpeningDate)
	require.Len(t, oct.Lines, 1, "sem bill_id, a compra entra pelo ciclo de datas")
	assert.Equal(t, "Smart Fit", oct.Lines[0].Description)
	assert.Equal(t, cards.Bill{Period: "2026-12", Status: "future", OpeningDate: "2026-11-21", ClosingDate: "2026-12-20",
		DueDate: "2026-12-25", Total: "0.00", Paid: "0.00", Lines: []cards.Line{}}, brad.Bills[2], "futura vazia")

	assert.Equal(t, "Nubank", nu.Institution)
	assert.Equal(t, "jean", nu.Owner)
	assert.Equal(t, "4821", *nu.Last4)
	assert.Equal(t, "2026-11", nu.Current, "sem saldo nas fechadas, vale a aberta")
	assert.Equal(t, map[string]string{"2026-09": "paid", "2026-10": "paid", "2026-11": "open", "2026-12": "future", "2027-01": "future"}, statuses(nu))
	paid := nu.Bills[1]
	assert.Equal(t, "2026-10-08", *paid.PaidOn)
	assert.Len(t, paid.Lines, 2)
	open := nu.Bills[2]
	assert.Equal(t, "148.38", open.Total, "aberta soma os lançamentos, sem o pagamento")
	assert.Equal(t, "2026-11-03", open.ClosingDate, "estimado: fechamento anterior + 1 mês")
	assert.Equal(t, "2026-11-10", open.DueDate)
	assert.Equal(t, cards.Line{Date: "2026-10-27", Description: "Amazon", Amount: "83.48",
		Installment: ptr(1), Installments: ptr(3), PurchaseDate: ptr("2026-10-27")}, open.Lines[0], "mais recente primeiro")
	assert.Equal(t, "83.48", nu.Bills[4].Total, "futura soma só a parcela já lançada")

	_, home := getHome(t, pool, "")
	assert.Equal(t, map[string]any{"total": "466.98", "closingDate": nil, "dueDate": "2026-10-25"}, home["card"],
		"a home mostra o mesmo total do modal")
}

func TestCards_BillBetweenClosingAndDueIsClosed(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	seedCards(t, pool)

	got := getCards(t, pool, time.Date(2026, 10, 22, 13, 0, 0, 0, time.UTC))

	assert.Equal(t, "closed", got.Cards[0].Bills[0].Status)
}

func ptr[T any](v T) *T { return &v }
