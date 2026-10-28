package items

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"time"

	"github.com/jackc/pgx/v5"
)

// Item é o que a tela de Ajustes mostra de cada banco conectado.
type Item struct {
	ID               string     `json:"id"`
	Owner            string     `json:"owner"`
	Connector        string     `json:"connector"`
	Status           string     `json:"status"` // status do item na Pluggy
	ConsentExpiresAt *time.Time `json:"consentExpiresAt"`
	SyncedAt         time.Time  `json:"syncedAt"` // última cópia bem-sucedida para o Postgres
	Accounts         int        `json:"accounts"`
	Sync             State      `json:"sync"`
}

const selectItems = `
	SELECT i.id::text, i.owner, i.connector, i.status, i.consent_expires_at, i.synced_at,
	       (SELECT count(*) FROM accounts a WHERE a.item_id = i.id)
	FROM items i`

func (s *Service) list(ctx context.Context, where string, args ...any) ([]Item, error) {
	rows, err := s.pool.Query(ctx, selectItems+where+` ORDER BY i.owner, i.connector, i.id`, args...)
	if err != nil {
		return nil, err
	}
	out, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (Item, error) {
		var it Item
		return it, r.Scan(&it.ID, &it.Owner, &it.Connector, &it.Status, &it.ConsentExpiresAt, &it.SyncedAt, &it.Accounts)
	})
	for i := range out {
		out[i].Sync = s.state(out[i].ID)
	}
	return out, err
}

func (s *Service) List(ctx context.Context) ([]Item, error) { return s.list(ctx, "") }

func (s *Service) Get(ctx context.Context, id string) (Item, error) {
	its, err := s.list(ctx, ` WHERE i.id = $1::uuid`, id)
	if err != nil {
		return Item{}, err
	}
	if len(its) == 0 {
		return Item{}, ErrNotFound
	}
	return its[0], nil
}

// StartAll dispara o sync de todos os itens (o botão "Sincronizar tudo").
func (s *Service) StartAll(ctx context.Context) ([]Item, error) {
	its, err := s.List(ctx)
	if err != nil {
		return nil, err
	}
	for _, it := range its {
		if _, err := s.Start(ctx, it.ID); err != nil {
			return nil, err
		}
	}
	return s.List(ctx)
}

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/items", h.list)
	mux.HandleFunc("GET /v1/items/{id}", h.get)
	mux.HandleFunc("POST /v1/items/{id}/sync", h.sync)
	mux.HandleFunc("POST /v1/sync", h.syncAll)
}

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, op string, err error) {
	if errors.Is(err, ErrNotFound) {
		http.Error(w, `{"error":"item não encontrado"}`, http.StatusNotFound)
		return
	}
	log.Printf("items %s: %v", op, err)
	http.Error(w, `{"error":"falha ao processar o pedido"}`, http.StatusInternalServerError)
}

// itemID devolve o id da rota; um id que não é UUID não existe, e evita erro de cast no SQL.
func itemID(w http.ResponseWriter, r *http.Request) (string, bool) {
	id := r.PathValue("id")
	if !uuidRe.MatchString(id) {
		fail(w, "id", ErrNotFound)
		return "", false
	}
	return id, true
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	its, err := h.svc.List(r.Context())
	if err != nil {
		fail(w, "list", err)
		return
	}
	writeJSON(w, http.StatusOK, its)
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	id, ok := itemID(w, r)
	if !ok {
		return
	}
	it, err := h.svc.Get(r.Context(), id)
	if err != nil {
		fail(w, "get", err)
		return
	}
	writeJSON(w, http.StatusOK, it)
}

// sync atende POST /v1/items/{id}/sync: 202 com o andamento; acompanhe em GET /v1/items/{id}.
func (h *Handler) sync(w http.ResponseWriter, r *http.Request) {
	id, ok := itemID(w, r)
	if !ok {
		return
	}
	st, err := h.svc.Start(r.Context(), id)
	if err != nil {
		fail(w, "sync", err)
		return
	}
	writeJSON(w, http.StatusAccepted, st)
}

// syncAll atende POST /v1/sync: 202 com todos os itens e o andamento de cada um.
func (h *Handler) syncAll(w http.ResponseWriter, r *http.Request) {
	its, err := h.svc.StartAll(r.Context())
	if err != nil {
		fail(w, "sync all", err)
		return
	}
	writeJSON(w, http.StatusAccepted, its)
}
