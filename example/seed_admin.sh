#!/usr/bin/env bash
# Crea sull'emulatore di Auth l'utente admin dell'esempio: email verificata e
# claim `admin`, come chiedono le regole. Da lanciare con gli emulatori accesi.
# Creates the example's admin user on the Auth emulator (run with emulators up).
set -euo pipefail
HOST="${AUTH_EMULATOR:-127.0.0.1:9099}"
BASE="http://$HOST/identitytoolkit.googleapis.com/v1/projects/demo-perfect-board"
H=(-H 'Authorization: Bearer owner' -H 'Content-Type: application/json')

# L'utente, con l'email già verificata…
ID=$(curl -sf --noproxy '*' -X POST "$BASE/accounts" "${H[@]}" \
  -d '{"email":"admin@example.com","password":"password","emailVerified":true,"displayName":"Demo Admin"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["localId"])')

# …poi il claim: in creazione l'emulatore non lo prende.
curl -sf --noproxy '*' -X POST "$BASE/accounts:update" "${H[@]}" \
  -d "{\"localId\":\"$ID\",\"customAttributes\":\"{\\\"admin\\\":true}\"}" > /dev/null

echo "admin@example.com / password"
