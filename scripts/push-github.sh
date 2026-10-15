#!/usr/bin/env bash
# Sobe o projeto para o GitHub.
# Uso: bash scripts/push-github.sh "https://github.com/SEU-USUARIO/internet-gratis.git"
set -euo pipefail
cd "$(dirname "$0")/.."
REMOTE="${1:-}"

[ -f backend/.env ] && echo "[aviso] backend/.env existe mas NÃO será commitado (gitignore)."

git init 2>/dev/null || true
git add .
git commit -m "deploy: internet gratis + render.yaml" 2>/dev/null || echo "[info] nada novo para commitar"
git branch -M main
if [ -n "$REMOTE" ]; then
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
  git push -u origin main
  echo "[ok] enviado para $REMOTE"
else
  echo "Uso: bash scripts/push-github.sh <url-do-repo>"
  echo "Ex:  bash scripts/push-github.sh https://github.com/SEU-USUARIO/internet-gratis.git"
  echo ""
  echo "Ou manual:"
  echo "  git remote add origin <url-do-repo>"
  echo "  git push -u origin main"
fi
