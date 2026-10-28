// Package items expõe os itens conectados e dispara a sincronização com a Pluggy em segundo plano.
package items

import (
	"context"
	"errors"
	"fmt"
	stdsync "sync"
	"time"

	"fyin/internal/pluggy"
	fsync "fyin/internal/sync"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("item não encontrado")

// Pluggy é a parte da Pluggy usada aqui; *pluggy.Client a satisfaz.
type Pluggy interface {
	fsync.API
	Refresh(ctx context.Context, id string) (pluggy.Item, error)
}

const (
	Idle      = "idle"
	Running   = "running"
	Succeeded = "succeeded"
	Failed    = "failed"

	PhaseRefreshing = "refreshing" // esperando a Pluggy reler o banco
	PhaseImporting  = "importing"  // copiando o resultado para o Postgres
)

// State é o andamento do último sync de um item.
type State struct {
	State      string        `json:"state"`
	Phase      string        `json:"phase,omitempty"`
	Error      string        `json:"error,omitempty"`
	StartedAt  *time.Time    `json:"startedAt,omitempty"`
	FinishedAt *time.Time    `json:"finishedAt,omitempty"`
	Result     *fsync.Result `json:"result,omitempty"`
}

type Service struct {
	pool *pgxpool.Pool
	api  Pluggy
	now  func() time.Time

	Poll    time.Duration // intervalo entre consultas ao status do item na Pluggy
	Timeout time.Duration // limite de um sync inteiro

	mu   stdsync.Mutex
	runs map[string]State
}

func NewService(pool *pgxpool.Pool, api Pluggy, now func() time.Time) *Service {
	return &Service{pool: pool, api: api, now: now, Poll: 2 * time.Second, Timeout: 2 * time.Minute, runs: map[string]State{}}
}

// Start dispara o sync de um item e volta na hora; quem chama acompanha por Get.
// Se o item já está sincronizando devolve o andamento atual, sem pedir outra leitura à Pluggy.
// shortcut: o andamento fica em memória e some se a API reiniciar; persistir se o sync passar a rodar fora do processo da API.
func (s *Service) Start(ctx context.Context, id string) (State, error) {
	owner, err := s.owner(ctx, id)
	if err != nil {
		return State{}, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if cur := s.runs[id]; cur.State == Running {
		return cur, nil
	}
	started := s.now()
	st := State{State: Running, Phase: PhaseRefreshing, StartedAt: &started}
	s.runs[id] = st
	go s.run(id, owner)
	return st, nil
}

func (s *Service) run(id, owner string) {
	ctx, cancel := context.WithTimeout(context.Background(), s.Timeout)
	defer cancel()
	res, err := s.work(ctx, id, owner)

	finished := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()
	st := s.runs[id]
	st.Phase, st.FinishedAt = "", &finished
	if err != nil {
		st.State, st.Error = Failed, err.Error()
	} else {
		st.State, st.Result = Succeeded, &res
	}
	s.runs[id] = st
}

func (s *Service) work(ctx context.Context, id, owner string) (fsync.Result, error) {
	it, err := s.api.Refresh(ctx, id)
	if pluggy.NotRefreshable(err) {
		// Conector que a Pluggy atualiza sozinha: não há o que pedir, só importar o que ela já tem.
		it, err = s.api.Item(ctx, id)
	}
	if err != nil {
		return fsync.Result{}, fmt.Errorf("refresh: %w", err)
	}
	for it.Status == "UPDATING" {
		select {
		case <-ctx.Done():
			return fsync.Result{}, errors.New("a Pluggy demorou demais para atualizar o banco")
		case <-time.After(s.Poll):
		}
		if it, err = s.api.Item(ctx, id); err != nil {
			return fsync.Result{}, fmt.Errorf("item: %w", err)
		}
	}
	if it.Status != "UPDATED" {
		// O dado já salvo fica como está; só o status do item muda, para o app mostrar o que o banco pede.
		_, _ = s.pool.Exec(ctx, `UPDATE items SET status=$2 WHERE id=$1::uuid`, id, it.Status)
		return fsync.Result{}, fmt.Errorf("o banco respondeu %s", it.Status)
	}
	s.setPhase(id, PhaseImporting)
	return fsync.Item(ctx, s.pool, s.api, owner, id)
}

func (s *Service) setPhase(id, phase string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	st := s.runs[id]
	st.Phase = phase
	s.runs[id] = st
}

func (s *Service) state(id string) State {
	s.mu.Lock()
	defer s.mu.Unlock()
	if st, ok := s.runs[id]; ok {
		return st
	}
	return State{State: Idle}
}

func (s *Service) owner(ctx context.Context, id string) (string, error) {
	var owner string
	err := s.pool.QueryRow(ctx, `SELECT owner FROM items WHERE id=$1::uuid`, id).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return owner, err
}
