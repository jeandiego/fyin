#!/usr/bin/env bash
# Valida o Meu Pluggy: contas, transações e financiamentos de um item. Uso: ./check.sh <itemId>
set -euo pipefail
cd "$(dirname "$0")"
set -a; source .env; set +a
ITEM=${1:?uso: ./check.sh <itemId>}
API=https://api.pluggy.ai

KEY=$(curl -fsS -X POST $API/auth -H 'Content-Type: application/json' \
  -d "{\"clientId\":\"$CLIENT_ID\",\"clientSecret\":\"$CLIENT_SECRET\"}" | jq -r .apiKey)
get() { curl -fsS "$API/$1" -H "X-API-KEY: $KEY"; }

echo "== item"; get "items/$ITEM" | jq '{status, executionStatus, consentExpiresAt, connector: .connector.name}'

echo "== contas"; ACC=$(get "accounts?itemId=$ITEM")
echo "$ACC" | jq -r '.results[] | "\(.type)/\(.subtype)  \(.name)  saldo=\(.balance)"'

echo "== transações por conta"
for id in $(echo "$ACC" | jq -r '.results[].id'); do
  # shortcut: só a 1ª página (v2 usa cursor em .next); paginar quando o backend de sync existir
  get "v2/transactions?accountId=$id" | jq -r --arg id "$id" '"\($id): \(.results|length) transações, mais antiga \([.results[].date] | min // "-"), próxima página: \(.next != null)"'
done

echo "== financiamentos/empréstimos"
get "loans?itemId=$ITEM" | jq '.results[] | {productName, kind, saldoDevedor: .payments.contractOutstandingBalance, parcelasRestantes: .installments.contractRemainingNumber}'
