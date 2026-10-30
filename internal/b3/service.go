// Package b3 grava a posição que o app lê na Área do Investidor da B3 e diz a cada dono quando foi a última leitura.
package b3

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrInvalid marca erro do cliente; a mensagem vai para o app.
var ErrInvalid = errors.New("import inválido")

func invalid(msg string) error { return fmt.Errorf("%w: %s", ErrInvalid, msg) }

// Import é o corpo de POST /v1/b3/positions: as páginas cruas de extrato-posicao/v2/posicao, como a B3 devolveu.
type Import struct {
	Owner         string            `json:"owner"`
	ReferenceDate string            `json:"referenceDate"` // YYYY-MM-DD da última carga da B3 (D-1)
	Pages         []json.RawMessage `json:"pages"`
}

// Result resume o import para o toast do app.
type Result struct {
	Owner         string    `json:"owner"`
	Positions     int       `json:"positions"`
	Total         string    `json:"total"`
	Delta         *string   `json:"delta"` // diferença para o import anterior; nulo no primeiro
	ReferenceDate string    `json:"referenceDate"`
	ImportedAt    time.Time `json:"importedAt"`
}

// Status é a linha de cada dono em Ajustes, inclusive de quem ainda não importou.
type Status struct {
	Owner         string     `json:"owner"`
	ImportedAt    *time.Time `json:"importedAt"`
	ReferenceDate *string    `json:"referenceDate"`
	Positions     int        `json:"positions"`
	Total         string     `json:"total"`
	Stale         bool       `json:"stale"` // mais de 30 dias desde o último import
}

type page struct {
	Itens *[]struct {
		Categoria string            `json:"categoriaProduto"`
		Tipo      string            `json:"tipoProduto"`
		Descricao string            `json:"descricaoTipoProduto"`
		Posicoes  []json.RawMessage `json:"posicoes"`
	} `json:"itens"`
}

// posicao junta os campos que aparecem em algum tipo de produto; cada tipo preenche só parte deles.
type posicao struct {
	Produto           string       `json:"produto"`
	NomeTituloPublico string       `json:"nomeTituloPublico"`
	NomeFundo         string       `json:"nomeFundo"`
	RazaoSocial       string       `json:"razaoSocial"`
	CodigoNegociacao  string       `json:"codigoNegociacao"`
	CodigoIsin        string       `json:"codigoIsin"`
	Instituicao       string       `json:"instituicao"`
	Indexador         string       `json:"indexador"`
	Vencimento        string       `json:"vencimento"`
	Quantidade        *json.Number `json:"quantidade"`
	PrecoFechamento   *json.Number `json:"precoFechamento"`
	ValorAplicado     *json.Number `json:"valorAplicado"`
	ValorBruto        *json.Number `json:"valorBruto"`
	ValorLiquido      *json.Number `json:"valorLiquido"`
	ValorAtualizado   *json.Number `json:"valorAtualizado"`
}

type row struct {
	category, productType, label, name                string
	isin, code, institution, indexer, dueDate         *string
	quantity, closePrice, applied, gross, net, update *string
	raw                                               []byte
}

type Service struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

func NewService(pool *pgxpool.Pool, now func() time.Time) *Service {
	return &Service{pool: pool, now: now}
}

// Import substitui a posição do dono numa transação; nada é gravado se alguma página não fizer sentido.
func (s *Service) Import(ctx context.Context, in Import) (Result, error) {
	ref, err := time.Parse("2006-01-02", in.ReferenceDate)
	if err != nil {
		return Result{}, invalid("referenceDate deve ser YYYY-MM-DD")
	}
	if len(in.Pages) == 0 {
		return Result{}, invalid("nenhuma página de posição")
	}
	rows, err := parse(in.Pages)
	if err != nil {
		return Result{}, err
	}
	var known bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM items WHERE owner = $1)`, in.Owner).Scan(&known); err != nil {
		return Result{}, err
	}
	if !known {
		return Result{}, invalid("dono desconhecido")
	}

	now := s.now().UTC()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Result{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `DELETE FROM b3_positions WHERE owner = $1`, in.Owner); err != nil {
		return Result{}, err
	}
	for _, r := range rows {
		_, err := tx.Exec(ctx, `
			INSERT INTO b3_positions (owner, category, product_type, product_label, name, isin, code, institution, indexer, due_date,
				quantity, close_price, applied, gross, net, updated_value, reference_date, raw)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::date, $11::numeric, $12::numeric, $13::numeric, $14::numeric,
				$15::numeric, $16::numeric, $17, $18::jsonb)`,
			in.Owner, r.category, r.productType, r.label, r.name, r.isin, r.code, r.institution, r.indexer, r.dueDate,
			r.quantity, r.closePrice, r.applied, r.gross, r.net, r.update, ref, string(r.raw))
		if err != nil {
			return Result{}, err
		}
	}
	out := Result{Owner: in.Owner, Positions: len(rows), ReferenceDate: in.ReferenceDate, ImportedAt: now}
	err = tx.QueryRow(ctx, `
		WITH t AS (SELECT coalesce(sum(value) FILTER (WHERE counts), 0)::numeric(14,2) AS total FROM b3_holdings WHERE owner = $1),
		prev AS (SELECT total FROM b3_imports WHERE owner = $1),
		up AS (
			INSERT INTO b3_imports (owner, imported_at, reference_date, positions, total, previous_total)
			SELECT $1, $2, $3, $4, t.total, (SELECT total FROM prev) FROM t
			ON CONFLICT (owner) DO UPDATE SET imported_at = EXCLUDED.imported_at, reference_date = EXCLUDED.reference_date,
				positions = EXCLUDED.positions, total = EXCLUDED.total, previous_total = EXCLUDED.previous_total
		)
		SELECT t.total::text, (t.total - (SELECT total FROM prev))::numeric(14,2)::text FROM t`,
		in.Owner, now, ref, len(rows)).Scan(&out.Total, &out.Delta)
	if err != nil {
		return Result{}, err
	}
	return out, tx.Commit(ctx)
}

// List devolve um status por dono conhecido (os donos dos itens da Pluggy), importado ou não.
func (s *Service) List(ctx context.Context) ([]Status, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT o.owner, i.imported_at, i.reference_date::text, coalesce(i.positions, 0), coalesce(i.total, 0)::numeric(14,2)::text,
			coalesce(i.imported_at < $1::timestamptz - interval '30 days', false)
		FROM (SELECT owner FROM items UNION SELECT owner FROM b3_imports) o
		LEFT JOIN b3_imports i USING (owner)
		ORDER BY o.owner`, s.now())
	if err != nil {
		return nil, err
	}
	out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Status, error) {
		var st Status
		err := r.Scan(&st.Owner, &st.ImportedAt, &st.ReferenceDate, &st.Positions, &st.Total, &st.Stale)
		if st.ImportedAt != nil {
			utc := st.ImportedAt.UTC()
			st.ImportedAt = &utc
		}
		return st, err
	})
	if out == nil {
		out = []Status{}
	}
	return out, err
}

func parse(pages []json.RawMessage) ([]row, error) {
	var out []row
	for i, raw := range pages {
		var p page
		if err := json.Unmarshal(raw, &p); err != nil || p.Itens == nil {
			return nil, invalid(fmt.Sprintf("página %d não é uma posição da B3", i+1))
		}
		for _, it := range *p.Itens {
			if it.Categoria == "" || it.Tipo == "" {
				return nil, invalid(fmt.Sprintf("página %d tem produto sem categoria", i+1))
			}
			for _, pr := range it.Posicoes {
				r, err := toRow(it.Categoria, it.Tipo, it.Descricao, pr)
				if err != nil {
					return nil, invalid(fmt.Sprintf("página %d: %v", i+1, err))
				}
				out = append(out, r)
			}
		}
	}
	return out, nil
}

func toRow(category, productType, label string, raw json.RawMessage) (row, error) {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber() // valores monetários nunca passam por float64
	var doc map[string]any
	if err := dec.Decode(&doc); err != nil {
		return row{}, errors.New("posição ilegível")
	}
	delete(doc, "documento") // CPF do investidor
	clean, err := json.Marshal(doc)
	if err != nil {
		return row{}, err
	}
	var p posicao
	if err := json.Unmarshal(clean, &p); err != nil {
		return row{}, errors.New("posição com campo em formato inesperado")
	}
	name := first(p.Produto, p.NomeTituloPublico, p.NomeFundo, p.RazaoSocial, p.CodigoNegociacao)
	if name == "" {
		return row{}, errors.New("posição sem nome")
	}
	r := row{category: category, productType: productType, label: first(label, productType), name: name, raw: clean,
		isin: opt(p.CodigoIsin), code: opt(p.CodigoNegociacao), institution: opt(p.Instituicao), indexer: opt(p.Indexador),
		quantity: num(p.Quantidade), closePrice: num(p.PrecoFechamento), applied: num(p.ValorAplicado), gross: num(p.ValorBruto),
		net: num(p.ValorLiquido), update: num(p.ValorAtualizado)}
	if p.Vencimento != "" {
		if len(p.Vencimento) < 10 {
			return row{}, errors.New("vencimento inválido")
		}
		d := p.Vencimento[:10]
		if _, err := time.Parse("2006-01-02", d); err != nil {
			return row{}, errors.New("vencimento inválido")
		}
		r.dueDate = &d
	}
	return r, nil
}

func first(vs ...string) string {
	for _, v := range vs {
		if v = strings.TrimSpace(v); v != "" {
			return v
		}
	}
	return ""
}

func opt(v string) *string {
	if v = strings.TrimSpace(v); v == "" {
		return nil
	}
	return &v
}

func num(n *json.Number) *string {
	if n == nil {
		return nil
	}
	s := n.String()
	return &s
}
