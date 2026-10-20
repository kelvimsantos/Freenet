# 📶 Internet Grátis

Ganhe internet assistindo anúncios, conversando com o Robô Pet e resgatando bônus diário. Troque créditos por pacotes de internet.

## Estrutura

```
backend/   → API (Node.js + Express + MongoDB + JWT)
frontend/  → App web (HTML/CSS/JS puro, sem build)
scripts/   → add-robot.sh (instalador do Robô Pet)
```

## Como rodar (local)

**1. Backend**
```bash
cd backend
cp .env.example .env   # preencha MONGO_URI, JWT_SECRET e ENCRYPTION_KEY
npm install
npm run seed           # cria 3 anúncios de exemplo
npm run dev            # http://localhost:3000 (serve API + frontend)
# Sem MONGO_URI real ele sobe em modo memória (teste, dados voláteis).
```

**2. Frontend** — o próprio backend já serve o app em `http://localhost:3000/` (mesma origem, sem build). Alternativa: `cd frontend && python3 -m http.server 8080` + ajuste `API_BASE` em `frontend/config.js`.

**3. Robô Pet** (opcional — usa sua sessão com seus dados):
```bash
cd backend
bash ../scripts/add-robot.sh   # instala /robot no src/server.js + ROBOT_* no .env.example
```
Depois configure por usuário na aba ⚙️ do frontend (provider grok|gemini|openai|anthropic + sua API key + sua connection string do Atlas).

## Endpoints principais

| Método | Rota | Auth | Descrição |
|---|---|---|---|
| POST | `/api/auth/register` | não | cria conta (+2 boas-vindas) |
| POST | `/api/auth/login` | não | retorna JWT |
| GET | `/api/auth/me` | sim | perfil + saldo |
| GET | `/api/ads` | sim | lista anúncios ativos |
| POST | `/api/ads/:id/complete` | sim | confirma exibição e credita |
| GET | `/api/credits/balance` | sim | saldo |
| GET | `/api/credits/history` | sim | extrato |
| POST | `/api/credits/daily-bonus` | sim | +3/dia |
| POST | `/api/credits/redeem` | sim | troca por internet |
| PUT/GET/DELETE | `/api/robot-config` | sim | chaves do robô (BYOK/BYOD) |
| GET/POST | `/robot/*` | sim | rotas do pet (via add-robot.sh) |

## Anúncios reais (AdSense/AdMob)

- O backend já aceita anúncios externos: cadastre na coleção `Ad` com `network: adsense|admob` e `externalSlot` com o id do slot.
- Preencha `ADSENSE_CLIENT_ID` / `ADMOB_APP_ID` no `.env` — o `GET /api/ads` devolve esses ids para o frontend intercalar.
- A recompensa continua valendo após a exibição confirmada pelo `POST /:id/complete`.

## Deploy automático (git push → Render com env vars)

Fluxo: `backend/.env` → GitHub Secrets → Action `Sync Render Env Vars` → Render API → redeploy.

1. Uma única vez:
```bash
gh auth login
bash scripts/setup-github-secrets.sh   # sobe MONGO_URI/JWT/ENCRYPTION_* do backend/.env p/ GitHub Secrets
gh secret set RENDER_API_KEY           # dashboard.render.com/account/api-keys
gh secret set RENDER_SERVICE_ID        # srv-... (URL do service)
```
2. Todo push já sincroniza sozinho:
```bash
bash scripts/push-github.sh "https://github.com/SEU-USUARIO/internet-gratis.git"
# 1) sobe .env -> Secrets | 2) git push -> Action roda scripts/render-env.sh no Render
```
`render.yaml` está com `MONGO_URI/JWT_SECRET/ENCRYPTION_KEY` em `sync: false` de propósito — o valor vem da API (Secrets), sem `generateValue` (que trocaria e deslogaria todos).

## Variáveis de ambiente

Veja `backend/.env.example` (PORT, MONGO_URI, JWT_SECRET, ENCRYPTION_KEY, ADS_DAILY_CAP, ADSENSE_CLIENT_ID, ADMOB_APP_ID, FRONTEND_URL) + `ROBOT_*` adicionadas pelo instalador do robô.
