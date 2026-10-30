package b3

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
)

type Handler struct{ svc *Service }

func NewHandler(svc *Service) *Handler { return &Handler{svc: svc} }

func (h *Handler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/b3/imports", h.list)
	mux.HandleFunc("POST /v1/b3/positions", h.importPositions)
}

func (h *Handler) list(w http.ResponseWriter, r *http.Request) {
	out, err := h.svc.List(r.Context())
	if err != nil {
		log.Printf("b3 list: %v", err)
		http.Error(w, `{"error":"falha ao listar os imports da B3"}`, http.StatusInternalServerError)
		return
	}
	reply(w, out)
}

func (h *Handler) importPositions(w http.ResponseWriter, r *http.Request) {
	// shortcut: 5 MB cobre dezenas de páginas de posição; subir se alguém tiver carteira maior.
	r.Body = http.MaxBytesReader(w, r.Body, 5<<20)
	var in Import
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		fail(w, http.StatusBadRequest, "corpo deve ser {owner, referenceDate, pages}")
		return
	}
	out, err := h.svc.Import(r.Context(), in)
	if errors.Is(err, ErrInvalid) {
		fail(w, http.StatusBadRequest, strings.TrimPrefix(err.Error(), ErrInvalid.Error()+": "))
		return
	}
	if err != nil {
		log.Printf("b3 import %s: %v", in.Owner, err)
		fail(w, http.StatusInternalServerError, "falha ao gravar a posição da B3")
		return
	}
	reply(w, out)
}

func reply(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
