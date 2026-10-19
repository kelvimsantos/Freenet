#!/usr/bin/env bash
# Define as variáveis de ambiente no Render via API (automático, sem dashboard).
# Pré-requisito: crie uma API Key em https://dashboard.render.com/account/api-keys
# Uso:
#   RENDER_API_KEY=xxx RENDER_SERVICE_ID=srv-xxx MONGO_URI="mongodb+srv://..." bash scripts/render-env.sh
#   # com frontend custom:
#   RENDER_API_KEY=xxx RENDER_SERVICE_ID=srv-xxx MONGO_URI="..." FRONTEND_URL="https://..." bash scripts/render-env.sh
set -euo pipefail

: "${RENDER_API_KEY:?Faltou RENDER_API_KEY (dashboard.render.com/account/api-keys)}"
: "${RENDER_SERVICE_ID:?Faltou RENDER_SERVICE_ID (srv-... — veja na URL do service)}"
: "${MONGO_URI:?Faltou MONGO_URI (sua connection string do Atlas)}"

# NÃO gere segredo novo a cada execução: trocar JWT_SECRET derruba todas as
# sessões (logout geral) e trocar ENCRYPTION_KEY invalida segredos do robô.
# Reuso: passe JWT_SECRET=/ENCRYPTION_KEY= existentes ou deixe o script buscar
# os valores atuais no Render e reaproveitar.
if [ -z "${JWT_SECRET:-}" ] || [ -z "${ENCRYPTION_KEY:-}" ]; then
  echo "[info] buscando env-vars atuais no Render para reaproveitar segredos..."
  CURRENT_JSON=$(curl -s "https://api.render.com/v1/services/${RENDER_SERVICE_ID}/env-vars" \
    -H "Authorization: Bearer ${RENDER_API_KEY}" -H "Content-Type: application/json") || CURRENT_JSON=""
  get_current() {
    printf '%s' "$CURRENT_JSON" | python3 -c "
import json,sys
try:
  data=json.load(sys.stdin)
except Exception:
  sys.exit(0)
want=sys.argv[1]
for it in data:
  if isinstance(it,dict) and (it.get('key')==want or (it.get('envVar') or {}).get('key')==want):
    v=it.get('value') or (it.get('envVar') or {}).get('value') or ''
    if v: print(v, end='')
    break
" "$1"
  }
  if [ -z "${JWT_SECRET:-}" ]; then
    EXISTING_JWT=$(get_current "JWT_SECRET" || true)
    if [ -n "${EXISTING_JWT:-}" ]; then
      JWT_SECRET="$EXISTING_JWT"
      echo "[ok] JWT_SECRET atual reaproveitado (sessões preservadas)."
    else
      JWT_SECRET="$(openssl rand -hex 32)"
      echo "[aviso] nenhum JWT_SECRET no Render — gerado um novo (primeira instalação)."
    fi
  fi
  if [ -z "${ENCRYPTION_KEY:-}" ]; then
    EXISTING_ENC=$(get_current "ENCRYPTION_KEY" || true)
    if [ -n "${EXISTING_ENC:-}" ]; then
      ENCRYPTION_KEY="$EXISTING_ENC"
      echo "[ok] ENCRYPTION_KEY atual reaproveitada."
    else
      ENCRYPTION_KEY="$(openssl rand -hex 32)"
      echo "[aviso] nenhuma ENCRYPTION_KEY no Render — gerada uma nova (primeira instalação)."
    fi
  fi
fi
ADS_DAILY_CAP="${ADS_DAILY_CAP:-20}"
ADSENSE_CLIENT_ID="${ADSENSE_CLIENT_ID:-}"
ADMOB_APP_ID="${ADMOB_APP_ID:-}"
FRONTEND_URL="${FRONTEND_URL:-}"
ROBOT_ENABLED="${ROBOT_ENABLED:-true}"

# Monta JSON com jq (se existir) ou python3
if command -v jq >/dev/null 2>&1; then
  PAYLOAD=$(jq -n \
    --arg mongo "$MONGO_URI" \
    --arg jwt "$JWT_SECRET" \
    --arg enc "$ENCRYPTION_KEY" \
    --arg cap "$ADS_DAILY_CAP" \
    --arg adsense "$ADSENSE_CLIENT_ID" \
    --arg admob "$ADMOB_APP_ID" \
    --arg front "$FRONTEND_URL" \
    --arg robot "$ROBOT_ENABLED" \
    '[
      {key:"MONGO_URI", value:$mongo},
      {key:"JWT_SECRET", value:$jwt},
      {key:"ENCRYPTION_KEY", value:$enc},
      {key:"ADS_DAILY_CAP", value:$cap},
      {key:"ADSENSE_CLIENT_ID", value:$adsense},
      {key:"ADMOB_APP_ID", value:$admob},
      {key:"FRONTEND_URL", value:$front},
      {key:"ROBOT_ENABLED", value:$robot},
      {key:"ROBOT_MESSAGES_PER_CREDIT", value:"5"},
      {key:"ROBOT_SESSION_BONUS_MINUTES", value:"5"},
      {key:"ROBOT_SESSION_IDLE_MINUTES", value:"15"},
      {key:"ROBOT_CREDITS_DAILY_CAP", value:"3"},
      {key:"ROBOT_HISTORY_MESSAGES", value:"20"},
      {key:"ROBOT_MAX_MESSAGE_CHARS", value:"2000"},
      {key:"ROBOT_XP_PER_LEVEL", value:"10"},
      {key:"USER_DB_CACHE_TTL_MINUTES", value:"30"},
      {key:"USER_DB_TEST_TIMEOUT", value:"5000"}
    ] | map(select(.value != ""))')
else
  PAYLOAD=$(python3 -c "
import os, json
def g(k, d=''): return os.environ.get(k, d)
items = [
  ('MONGO_URI', os.environ['MONGO_URI']),
  ('JWT_SECRET', g('JWT_SECRET')),
  ('ENCRYPTION_KEY', g('ENCRYPTION_KEY')),
  ('ADS_DAILY_CAP', g('ADS_DAILY_CAP','20')),
  ('ADSENSE_CLIENT_ID', g('ADSENSE_CLIENT_ID')),
  ('ADMOB_APP_ID', g('ADMOB_APP_ID')),
  ('FRONTEND_URL', g('FRONTEND_URL')),
  ('ROBOT_ENABLED', g('ROBOT_ENABLED','true')),
  ('ROBOT_MESSAGES_PER_CREDIT','5'),
  ('ROBOT_SESSION_BONUS_MINUTES','5'),
  ('ROBOT_SESSION_IDLE_MINUTES','15'),
  ('ROBOT_CREDITS_DAILY_CAP','3'),
  ('ROBOT_HISTORY_MESSAGES','20'),
  ('ROBOT_MAX_MESSAGE_CHARS','2000'),
  ('ROBOT_XP_PER_LEVEL','10'),
  ('USER_DB_CACHE_TTL_MINUTES','30'),
  ('USER_DB_TEST_TIMEOUT','5000'),
]
print(json.dumps([{'key':k,'value':v} for k,v in items if v != '']))
")
fi

export RENDER_API_KEY RENDER_SERVICE_ID
echo "$PAYLOAD" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'[info] enviando {len(d)} vars para {sys.argv[1]}')" "$RENDER_SERVICE_ID"

curl -s -X PUT "https://api.render.com/v1/services/${RENDER_SERVICE_ID}/env-vars" \
  -H "Authorization: Bearer ${RENDER_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | head -c 2000; echo

echo ""
echo "[ok] Vars enviadas. O Render vai fazer redeploy automático."
echo "Geradas nesta execução (guarde):"
echo "JWT_SECRET=$JWT_SECRET"
echo "ENCRYPTION_KEY=$ENCRYPTION_KEY"
