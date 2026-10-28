# Carrega .env (CLIENT_ID, CLIENT_SECRET, DATABASE_URL, ITEMS, API_TOKEN) e roda os comandos.
RUN = set -a; . ./.env; set +a;

up:
	docker compose up -d db

sync:
	$(RUN) go run ./cmd/sync

api:
	$(RUN) go run ./cmd/api

test:
	go test ./...

psql:
	$(RUN) psql "$$DATABASE_URL"

.PHONY: up sync api test psql
