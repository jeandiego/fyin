package integrationtests

import (
	"context"
	"encoding/json"
	"errors"
	"testing"

	"fyin/internal/pluggy"
	"fyin/internal/sync"
	"fyin/internal/testdb"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type txRow struct {
	ID, Amount, Status string
	BillID, Forecast   *string
	Installment, Total *int
}

func cardTxs(t *testing.T, pool *pgxpool.Pool) []txRow {
	t.Helper()
	rows, err := pool.Query(context.Background(), `
		SELECT id::text, amount::text, status, bill_id::text, bill_forecast, installment_number, total_installments
		FROM transactions WHERE account_id = $1 ORDER BY transactions.amount DESC`, cardID)
	require.NoError(t, err)
	defer rows.Close()
	var out []txRow
	for rows.Next() {
		var r txRow
		require.NoError(t, rows.Scan(&r.ID, &r.Amount, &r.Status, &r.BillID, &r.Forecast, &r.Installment, &r.Total))
		out = append(out, r)
	}
	require.NoError(t, rows.Err())
	return out
}

func str(s string) *string { return &s }
func num(n int) *int       { return &n }

func TestSync_LinksCardTransactionsToTheirBillOrOpenMonth(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()

	res, err := sync.Item(context.Background(), pool, fake, "ana", itemID)

	require.NoError(t, err)
	assert.Equal(t, sync.Result{Accounts: 2, Bills: 1, Transactions: 2}, res)
	assert.Equal(t, []txRow{
		{ID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", Amount: "250.10", Status: "POSTED", BillID: str(billID), Installment: num(2), Total: num(6)},
		{ID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", Amount: "80.15", Status: "PENDING", Forecast: str("2026-04")},
	}, cardTxs(t, pool))

	var limit, balance *string
	require.NoError(t, pool.QueryRow(context.Background(),
		`SELECT (SELECT credit_limit::text FROM accounts WHERE id=$1), (SELECT credit_limit::text FROM accounts WHERE id=$2)`,
		cardID, checkingID).Scan(&limit, &balance))
	assert.Equal(t, str("5000.00"), limit)
	assert.Nil(t, balance, "conta corrente não tem limite de crédito")
}

func TestSync_RecreatedCardTransactionDoesNotDuplicate(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()
	_, err := sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)

	// Perto do fechamento a Pluggy recria a mesma compra com outro id.
	fake.txs[cardID][0].ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
	_, err = sync.Item(context.Background(), pool, fake, "ana", itemID)

	require.NoError(t, err)
	got := cardTxs(t, pool)
	require.Len(t, got, 2)
	assert.Equal(t, "cccccccc-cccc-4ccc-8ccc-cccccccccccc", got[0].ID)
}

func TestSync_FailedFetchKeepsPreviousData(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()
	_, err := sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)

	fake.transactionsErr = errors.New("pluggy fora do ar")
	_, err = sync.Item(context.Background(), pool, fake, "ana", itemID)

	require.ErrorContains(t, err, "pluggy fora do ar")
	assert.Len(t, cardTxs(t, pool), 2)
}

func TestSync_StoresRawWithoutPersonalData(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()
	fake.accounts[1].Raw = json.RawMessage(`{"name":"Cartao Teste","number":"9988-7","taxNumber":"123.456.789-09","creditData":{"brand":"VISA"}}`)
	fake.txs[cardID][0].Raw = json.RawMessage(`{
		"merchant":{"name":"Livraria Teste","cnpj":"11.222.333/0001-44"},
		"paymentData":{"paymentMethod":"PIX",
			"payer":{"name":"Fulano Pagador","documentNumber":{"type":"CPF","value":"111.222.333-96"},"accountNumber":"4455","branchNumber":"0012","routingNumber":"237"},
			"receiver":{"name":"Beltrana Recebedora","documentNumber":{"type":"CPF","value":"999.888.777-66"}}}}`)

	_, err := sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)

	var accountRaw, txRaw string
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT raw::text FROM accounts WHERE id=$1`, cardID).Scan(&accountRaw))
	require.NoError(t, pool.QueryRow(context.Background(), `SELECT raw::text FROM transactions WHERE id=$1`, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa").Scan(&txRaw))
	assert.JSONEq(t, `{"name":"Cartao Teste","creditData":{"brand":"VISA"}}`, accountRaw)
	assert.JSONEq(t, `{
		"merchant":{"name":"Livraria Teste","cnpj":"11.222.333/0001-44"},
		"paymentData":{"paymentMethod":"PIX","payer":{"routingNumber":"237"},"receiver":{}}}`, txRaw)
}

func TestSync_StoresLoansInvestmentsAndBankBalanceSnapshot(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()
	fake.loans = []pluggy.Loan{{ID: "55555555-5555-4555-8555-555555555555", ProductName: "Financiamento", Payments: &struct {
		ContractOutstandingBalance json.Number `json:"contractOutstandingBalance"`
	}{ContractOutstandingBalance: "48900.10"}, Raw: json.RawMessage(`{}`)}}
	fake.investments = []pluggy.Investment{{ID: "66666666-6666-4666-8666-666666666666", Type: "FIXED_INCOME", Name: "CDB",
		Status: "ACTIVE", Balance: "1234.56", Raw: json.RawMessage(`{"owner":"Fulano"}`)}}

	res, err := sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)
	_, err = sync.Item(context.Background(), pool, fake, "ana", itemID)
	require.NoError(t, err)

	assert.Equal(t, 1, res.Loans)
	assert.Equal(t, 1, res.Investments)
	var loan, invested, invRaw string
	var snapshots int
	require.NoError(t, pool.QueryRow(context.Background(), `
		SELECT (SELECT string_agg(outstanding_balance::text, ',') FROM loans),
		       (SELECT string_agg(balance::text, ',') FROM investments),
		       (SELECT raw::text FROM investments),
		       (SELECT count(*) FROM balance_snapshots WHERE account_id = $1)`, checkingID).Scan(&loan, &invested, &invRaw, &snapshots))
	assert.Equal(t, "48900.10", loan, "reimportar substitui, não duplica")
	assert.Equal(t, "1234.56", invested)
	assert.JSONEq(t, `{}`, invRaw, "nome do titular removido")
	assert.Equal(t, 2, snapshots, "um snapshot de saldo por sync, só da conta BANK")
}

func TestSync_ForeignPurchaseIsStoredInAccountCurrency(t *testing.T) {
	t.Parallel()
	pool := testdb.New(t)
	fake := newFake()
	// Assinatura em dólar: a Pluggy manda 21.80 (USD) em amount e o valor em reais à parte.
	fake.txs[cardID][1].Amount = "21.80"
	fake.txs[cardID][1].AmountInAccountCurrency = "114.53"

	_, err := sync.Item(context.Background(), pool, fake, "ana", itemID)

	require.NoError(t, err)
	assert.Equal(t, "114.53", cardTxs(t, pool)[1].Amount)
}
