package investments

import (
	"encoding/json"
	"log"
	"net/http"
)

type Handler struct{ store *Store }

func NewHandler(store *Store) *Handler { return &Handler{store: store} }

func (h *Handler) Register(mux *http.ServeMux) { mux.HandleFunc("GET /v1/investments", h.get) }

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	p, err := h.store.Portfolio(r.Context())
	if err != nil {
		log.Printf("investments: %v", err)
		http.Error(w, `{"error":"falha ao montar o patrimônio"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(p)
}
