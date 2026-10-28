// Package pluggy é um cliente mínimo da API da Pluggy: leitura e o pedido de atualização de um item.
package pluggy

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
)

type Client struct {
	BaseURL                string // padrão https://api.pluggy.ai; sobrescrito nos testes
	clientID, clientSecret string
	mu                     sync.Mutex // protege apiKey: a API chama o cliente de várias goroutines
	apiKey                 string
	http                   *http.Client
}

func New(clientID, clientSecret string) *Client {
	return &Client{BaseURL: "https://api.pluggy.ai", clientID: clientID, clientSecret: clientSecret, http: &http.Client{}}
}

// Valores monetários ficam como json.Number para não passar por float64.
type Item struct {
	ID               string `json:"id"`
	Status           string `json:"status"` // UPDATING | UPDATED | LOGIN_ERROR | WAITING_USER_INPUT | OUTDATED
	ConsentExpiresAt string `json:"consentExpiresAt"`
	Connector        struct {
		Name string `json:"name"`
	} `json:"connector"`
}

type Account struct {
	ID         string      `json:"id"`
	Type       string      `json:"type"`
	Subtype    string      `json:"subtype"`
	Name       string      `json:"name"`
	Balance    json.Number `json:"balance"`
	CreditData *struct {
		CreditLimit json.Number `json:"creditLimit"`
	} `json:"creditData"`
	Raw json.RawMessage `json:"-"`
}

type Bill struct {
	ID                   string          `json:"id"`
	DueDate              string          `json:"dueDate"`
	BillClosingDate      string          `json:"billClosingDate"`
	TotalAmount          json.Number     `json:"totalAmount"`
	MinimumPaymentAmount json.Number     `json:"minimumPaymentAmount"`
	Raw                  json.RawMessage `json:"-"`
}

type Loan struct {
	ID          string `json:"id"`
	ProductName string `json:"productName"`
	Payments    *struct {
		ContractOutstandingBalance json.Number `json:"contractOutstandingBalance"`
	} `json:"payments"`
	Raw json.RawMessage `json:"-"`
}

type Investment struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Name    string          `json:"name"`
	Status  string          `json:"status"`
	Balance json.Number     `json:"balance"`
	Raw     json.RawMessage `json:"-"`
}

type Transaction struct {
	ID          string      `json:"id"`
	Date        string      `json:"date"`
	Description string      `json:"description"`
	Amount      json.Number `json:"amount"`
	// Compra em moeda estrangeira: Amount vem na moeda original e este campo traz o valor em reais.
	AmountInAccountCurrency json.Number `json:"amountInAccountCurrency"`
	Type                    string      `json:"type"`
	Status                  string      `json:"status"`
	Category                string      `json:"category"`
	CreditCard              *struct {
		BillID            string `json:"billId"`
		BillForecastDate  string `json:"billForecastDate"`
		InstallmentNumber *int   `json:"installmentNumber"`
		TotalInstallments *int   `json:"totalInstallments"`
	} `json:"creditCardMetadata"`
	Raw json.RawMessage `json:"-"`
}

func (c *Client) auth(ctx context.Context) error {
	body, _ := json.Marshal(map[string]string{"clientId": c.clientID, "clientSecret": c.clientSecret})
	req, _ := http.NewRequestWithContext(ctx, "POST", c.BaseURL+"/auth", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	var out struct {
		APIKey string `json:"apiKey"`
	}
	if err := c.do(req, &out); err != nil {
		return fmt.Errorf("auth: %w", err)
	}
	c.apiKey = out.APIKey
	return nil
}

func (c *Client) do(req *http.Request, out any) error {
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		return fmt.Errorf("%s %s: %d %s", req.Method, req.URL.Path, resp.StatusCode, b)
	}
	return json.Unmarshal(b, out)
}

// send autentica sob demanda (a API key expira) e decodifica o JSON em out.
func (c *Client) send(ctx context.Context, method, pathAndQuery string, body []byte, out any) error {
	c.mu.Lock()
	if c.apiKey == "" {
		if err := c.auth(ctx); err != nil {
			c.mu.Unlock()
			return err
		}
	}
	key := c.apiKey
	c.mu.Unlock()
	req, _ := http.NewRequestWithContext(ctx, method, c.BaseURL+pathAndQuery, bytes.NewReader(body))
	req.Header.Set("X-API-KEY", key)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return c.do(req, out)
}

func (c *Client) get(ctx context.Context, pathAndQuery string, out any) error {
	return c.send(ctx, "GET", pathAndQuery, nil, out)
}

func (c *Client) Item(ctx context.Context, id string) (Item, error) {
	var it Item
	return it, c.get(ctx, "/items/"+id, &it)
}

// Refresh pede à Pluggy que releia o banco (PATCH /items/{id}, corpo vazio: usa as credenciais salvas).
// A resposta chega com status UPDATING; acompanhe com Item até sair desse status.
func (c *Client) Refresh(ctx context.Context, id string) (Item, error) {
	var it Item
	return it, c.send(ctx, "PATCH", "/items/"+id, []byte("{}"), &it)
}

type list struct {
	Results    []json.RawMessage `json:"results"`
	Next       *string           `json:"next"`
	TotalPages int               `json:"totalPages"`
}

// decodeAll preenche cada elemento e seu payload bruto (o campo Raw de cada struct).
func decodeAll[T any](raws []json.RawMessage, setRaw func(*T, json.RawMessage)) ([]T, error) {
	out := make([]T, len(raws))
	for i, r := range raws {
		if err := json.Unmarshal(r, &out[i]); err != nil {
			return nil, err
		}
		setRaw(&out[i], r)
	}
	return out, nil
}

func (c *Client) Accounts(ctx context.Context, itemID string) ([]Account, error) {
	var l list
	if err := c.get(ctx, "/accounts?itemId="+itemID, &l); err != nil {
		return nil, err
	}
	return decodeAll(l.Results, func(a *Account, r json.RawMessage) { a.Raw = r })
}

// paged percorre as páginas de uma listagem `path?...&page=N`.
func paged[T any](ctx context.Context, c *Client, path string, setRaw func(*T, json.RawMessage)) ([]T, error) {
	var all []T
	for page := 1; ; page++ {
		var l list
		if err := c.get(ctx, fmt.Sprintf("%s&page=%d", path, page), &l); err != nil {
			return nil, err
		}
		xs, err := decodeAll(l.Results, setRaw)
		if err != nil {
			return nil, err
		}
		all = append(all, xs...)
		if page >= l.TotalPages {
			return all, nil
		}
	}
}

func (c *Client) Bills(ctx context.Context, accountID string) ([]Bill, error) {
	return paged(ctx, c, "/bills?accountId="+accountID, func(b *Bill, r json.RawMessage) { b.Raw = r })
}

func (c *Client) Loans(ctx context.Context, itemID string) ([]Loan, error) {
	return paged(ctx, c, "/loans?itemId="+itemID, func(l *Loan, r json.RawMessage) { l.Raw = r })
}

func (c *Client) Investments(ctx context.Context, itemID string) ([]Investment, error) {
	return paged(ctx, c, "/investments?itemId="+itemID, func(i *Investment, r json.RawMessage) { i.Raw = r })
}

// Transactions segue o cursor `next` (query string completa, a anexar a /v2/transactions).
func (c *Client) Transactions(ctx context.Context, accountID string) ([]Transaction, error) {
	var all []Transaction
	next := "?accountId=" + accountID
	for next != "" {
		var l list
		if err := c.get(ctx, "/v2/transactions"+next, &l); err != nil {
			return nil, err
		}
		ts, err := decodeAll(l.Results, func(t *Transaction, r json.RawMessage) { t.Raw = r })
		if err != nil {
			return nil, err
		}
		all = append(all, ts...)
		next = ""
		if l.Next != nil {
			next = *l.Next
		}
	}
	return all, nil
}
