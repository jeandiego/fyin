package integrationtests

import (
	"context"
	"encoding/json"
	"sync/atomic"

	"fyin/internal/pluggy"
)

// fakePluggy é uma implementação em memória da API da Pluggy: devolve o que o teste configurou.
type fakePluggy struct {
	item        pluggy.Item
	accounts    []pluggy.Account
	bills       map[string][]pluggy.Bill
	txs         map[string][]pluggy.Transaction
	loans       []pluggy.Loan
	investments []pluggy.Investment

	transactionsErr error

	// Usados pelo sync disparado pela API: Refresh devolve UPDATING; Item devolve cada status de
	// statuses em ordem (depois f.item) e, se gate existir, espera ele abrir.
	statuses     []string
	gate         chan struct{}
	refreshCalls atomic.Int32
	refreshErr   error
}

func (f *fakePluggy) Item(context.Context, string) (pluggy.Item, error) {
	if f.gate != nil {
		<-f.gate
	}
	it := f.item
	if len(f.statuses) > 0 {
		it.Status, f.statuses = f.statuses[0], f.statuses[1:]
	}
	return it, nil
}

func (f *fakePluggy) Refresh(context.Context, string) (pluggy.Item, error) {
	f.refreshCalls.Add(1)
	if f.refreshErr != nil {
		return pluggy.Item{}, f.refreshErr
	}
	it := f.item
	it.Status = "UPDATING"
	return it, nil
}

func (f *fakePluggy) Accounts(context.Context, string) ([]pluggy.Account, error) {
	return f.accounts, nil
}

func (f *fakePluggy) Bills(_ context.Context, accountID string) ([]pluggy.Bill, error) {
	return f.bills[accountID], nil
}

func (f *fakePluggy) Transactions(_ context.Context, accountID string) ([]pluggy.Transaction, error) {
	return f.txs[accountID], f.transactionsErr
}

func (f *fakePluggy) Loans(context.Context, string) ([]pluggy.Loan, error) { return f.loans, nil }

func (f *fakePluggy) Investments(context.Context, string) ([]pluggy.Investment, error) {
	return f.investments, nil
}

const (
	itemID     = "11111111-1111-4111-8111-111111111111"
	checkingID = "22222222-2222-4222-8222-222222222222"
	cardID     = "33333333-3333-4333-8333-333333333333"
	billID     = "44444444-4444-4444-8444-444444444444"
)

// newFake devolve um item com conta corrente e cartão; o cartão tem uma fatura fechada
// com 1 compra parcelada e uma compra pendente na fatura aberta de 2026-04.
func newFake() *fakePluggy {
	return &fakePluggy{
		item: pluggy.Item{ID: itemID, Status: "UPDATED", ConsentExpiresAt: "2027-01-02T03:04:05.000Z"},
		accounts: []pluggy.Account{
			{ID: checkingID, Type: "BANK", Subtype: "CHECKING_ACCOUNT", Name: "Conta Teste", Balance: "100.50", Raw: json.RawMessage(`{}`)},
			{ID: cardID, Type: "CREDIT", Subtype: "CREDIT_CARD", Name: "Cartao Teste", Balance: "700.25", CreditData: &struct {
				CreditLimit json.Number `json:"creditLimit"`
			}{CreditLimit: "5000"}, Raw: json.RawMessage(`{}`)},
		},
		bills: map[string][]pluggy.Bill{cardID: {{
			ID: billID, DueDate: "2026-03-15T00:00:00.000Z", BillClosingDate: "2026-03-02T00:00:00.000Z",
			TotalAmount: "250.10", MinimumPaymentAmount: "25.01", Raw: json.RawMessage(`{"payments":[]}`),
		}}},
		txs: map[string][]pluggy.Transaction{cardID: {
			cardTx("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "250.10", "POSTED", billID, "", 2, 6),
			cardTx("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "80.15", "PENDING", "", "2026-04", 0, 0),
		}},
	}
}

func cardTx(id, amount, status, billID, forecast string, installment, total int) pluggy.Transaction {
	cc := &struct {
		BillID            string `json:"billId"`
		BillForecastDate  string `json:"billForecastDate"`
		InstallmentNumber *int   `json:"installmentNumber"`
		TotalInstallments *int   `json:"totalInstallments"`
	}{BillID: billID, BillForecastDate: forecast}
	if total > 0 {
		cc.InstallmentNumber, cc.TotalInstallments = &installment, &total
	}
	return pluggy.Transaction{
		ID: id, Date: "2026-03-01T12:00:00.000Z", Description: "Compra " + amount, Amount: json.Number(amount),
		Type: "DEBIT", Status: status, Category: "Bookstore", CreditCard: cc, Raw: json.RawMessage(`{}`),
	}
}
