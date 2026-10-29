package cards

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

type Handler struct {
	store *Store
	now   func() time.Time
}

func NewHandler(store *Store, now func() time.Time) *Handler { return &Handler{store: store, now: now} }

func (h *Handler) Register(mux *http.ServeMux) { mux.HandleFunc("GET /v1/cards", h.get) }

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	o, err := h.store.Overview(r.Context(), h.now())
	if err != nil {
		log.Printf("cards overview: %v", err)
		http.Error(w, `{"error":"falha ao montar os cartões"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(o)
}
