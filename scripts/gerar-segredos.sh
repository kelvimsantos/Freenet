#!/usr/bin/env bash
# Gera .env do backend + imprime valores prontos p/ Render Dashboard / API.
# Uso:
#   bash scripts/gerar-segredos.sh
#   MONGO_URI="sua-uri-atlas" bash scripts/gerar-segredos.sh
set -euo pipefail
cd "$(dirname "$0")/../backend"

JWT="${JWT_SECRET:-$(openssl rand -hex 32)}"
ENC="${ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
MONGO="${MONGO_URI:-mongodb+srv://usuario:senha@cluster.mongodb.net/internet_gratis?retryWrites=true&w=majority}"
FRONT="${FRONTEND_URL:-}"

if [ ! -f .env ]; then
  cp .env.example .env
  echo "[ok] .env criado a partir do .env.example"
fi

# atualiza ou adiciona chave no .env
set_kv() {
  local k="$1" v="$2" f=".env"
  if grep -qE "^[[:space:]]*${k}=" "$f"; then
    # escapa para sed
    esc=$(printf '%s' "$v" | sed -e 's/[\/&]/\\&/g')
    sed -i "s/^[[:space:]]*${k}=.*/${k}=${esc}/" "$f"
  else
    printf '%s=%s\n' "$k" "$v" >> "$f"
  fi
}

set_kv "JWT_SECRET" "$JWT"
set_kv "ENCRYPTION_KEY" "$ENC"
if [ -n "$MONGO" ]; then set_kv "MONGO_URI" "$MONGO"; fi
if [ -n "$FRONT" ]; then set_kv "FRONTEND_URL" "$FRONT"; fi

echo ""
echo "=== Copie para o Render (Environment) ==="
echo "MONGO_URI=$MONGO"
echo "JWT_SECRET=$JWT"
echo "ENCRYPTION_KEY=$ENC"
echo "ADS_DAILY_CAP=20"
echo "FRONTEND_URL=${FRONT:-https://SEU-APP.onrender.com}"
echo "ROBOT_ENABLED=true"
echo ""
echo "[ok] .env atualizado. NÃO commite o .env (já está no .gitignore)."
