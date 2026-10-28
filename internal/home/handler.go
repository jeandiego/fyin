package home

import (
	"encoding/json"
	"log"
	"net/http"
	"time"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(mux *http.ServeMux) { mux.HandleFunc("GET /v1/home", h.get) }

// get atende GET /v1/home?month=YYYY-MM (padrão: mês atual).
func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	month := h.svc.CurrentMonth()
	if q := r.URL.Query().Get("month"); q != "" {
		m, err := time.ParseInLocation("2006-01", q, saoPaulo)
		if err != nil {
			http.Error(w, `{"error":"month deve ser YYYY-MM"}`, http.StatusBadRequest)
			return
		}
		month = m
	}
	sum, err := h.svc.Month(r.Context(), month)
	if err != nil {
		log.Printf("home %s: %v", month.Format("2006-01"), err)
		http.Error(w, `{"error":"falha ao montar a home"}`, http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sum)
}
