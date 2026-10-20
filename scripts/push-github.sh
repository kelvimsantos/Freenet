#!/usr/bin/env bash
# Sobe o projeto para o GitHub (e garante env vars automáticas no Render).
# Uso: bash scripts/push-github.sh "https://github.com/SEU-USUARIO/internet-gratis.git"
set -euo pipefail
cd "$(dirname "$0")/.."
REMOTE="${1:-}"

[ -f backend/.env ] && echo "[aviso] backend/.env existe mas NÃO será commitado (gitignore)."

# 1) Sobe .env -> GitHub Secrets (fonte única; a Action replica no Render).
if command -v gh >/dev/null 2>&1 && [ -f backend/.env ]; then
  echo "[info] sincronizando backend/.env -> GitHub Secrets..."
  bash scripts/setup-github-secrets.sh || echo "[aviso] falhou sync de secrets (rode 'gh auth login' e tente de novo). Push continua."
else
  echo "[aviso] gh CLI ausente — pulando sync automático de Secrets. Rode bash scripts/setup-github-secrets.sh quando possível."
fi

git init 2>/dev/null || true
git add .
git commit -m "deploy: internet gratis + render.yaml" 2>/dev/null || echo "[info] nada novo para commitar"
git branch -M main
if [ -n "$REMOTE" ]; then
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
  git push -u origin main
  echo "[ok] enviado para $REMOTE"
  echo "[info] A Action 'Sync Render Env Vars' vai aplicar as env vars no Render automaticamente."
else
  echo "Uso: bash scripts/push-github.sh <url-do-repo>"
  echo "Ex:  bash scripts/push-github.sh https://github.com/SEU-USUARIO/internet-gratis.git"
  echo ""
  echo "Ou manual:"
  echo "  git remote add origin <url-do-repo>"
  echo "  git push -u origin main"
fi
