#!/usr/bin/env bash
# Sobe as vars do backend/.env para GitHub Secrets (fonte única p/ o deploy).
# Assim todo `git push` já deixa tudo pronto e a Action render-env-sync.yml
# replica no Render automaticamente via API.
# Uso: bash scripts/setup-github-secrets.sh
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="backend/.env"
[ -f "$ENV_FILE" ] || { echo "[erro] $ENV_FILE não encontrado. Copie backend/.env.example e preencha."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "[erro] instale o GitHub CLI: https://cli.github.com (comando 'gh') e rode 'gh auth login'."; exit 1; }

get_kv() { grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2-; }

MONGO_URI="$(get_kv MONGO_URI)"
JWT_SECRET="$(get_kv JWT_SECRET)"
ENCRYPTION_KEY="$(get_kv ENCRYPTION_KEY)"
ADS_DAILY_CAP="$(get_kv ADS_DAILY_CAP)"
ADSENSE_CLIENT_ID="$(get_kv ADSENSE_CLIENT_ID)"
ADMOB_APP_ID="$(get_kv ADMOB_APP_ID)"
FRONTEND_URL="$(get_kv FRONTEND_URL)"
ROBOT_ENABLED="true"

[ -n "$MONGO_URI" ] || { echo "[erro] MONGO_URI vazio no $ENV_FILE"; exit 1; }
case "$MONGO_URI" in *usuario:senha*|*@cluster.mongodb.net/*) echo "[erro] MONGO_URI ainda é placeholder — preencha a URI real do Atlas no $ENV_FILE"; exit 1;; esac
[ "${#JWT_SECRET}" -ge 32 ] || { echo "[erro] JWT_SECRET curto demais (>=32 chars)"; exit 1; }
[[ "$ENCRYPTION_KEY" =~ ^[0-9a-fA-F]{64}$ ]] || { echo "[erro] ENCRYPTION_KEY deve ter 64 hex"; exit 1; }

set_secret() { printf '%s' "$2" | gh secret set "$1" >/dev/null && echo "[ok] secret $1 atualizado"; }
set_secret MONGO_URI "$MONGO_URI"
set_secret JWT_SECRET "$JWT_SECRET"
set_secret ENCRYPTION_KEY "$ENCRYPTION_KEY"
set_secret ADS_DAILY_CAP "${ADS_DAILY_CAP:-20}"
[ -n "${ADSENSE_CLIENT_ID:-}" ] && set_secret ADSENSE_CLIENT_ID "$ADSENSE_CLIENT_ID" || true
[ -n "${ADMOB_APP_ID:-}" ] && set_secret ADMOB_APP_ID "$ADMOB_APP_ID" || true
[ -n "${FRONTEND_URL:-}" ] && set_secret FRONTEND_URL "$FRONTEND_URL" || true
set_secret ROBOT_ENABLED "$ROBOT_ENABLED"

echo ""
echo "[ok] Secrets no GitHub atualizados a partir de $ENV_FILE."
echo "Faltam só as credenciais do Render (uma única vez, nunca vão no git):"
echo "  gh secret set RENDER_API_KEY      # dashboard.render.com/account/api-keys"
echo "  gh secret set RENDER_SERVICE_ID   # srv-... (URL do service no Render)"
