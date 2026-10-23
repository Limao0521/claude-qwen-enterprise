#!/usr/bin/env bash
# =============================================================================
#  Instalador de un solo comando - claude-qwen (Linux Ubuntu 20.04+ y macOS)
#
#  Uso (desde cualquier carpeta):
#    curl -fsSL https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.sh | bash
#  o, si no tienes curl:
#    wget -qO-  https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.sh | bash
#
#  Si el repositorio cambia de dueno, nombre o rama, edita REPO_OWNER/
#  REPO_NAME/REPO_BRANCH y las URLs del README.
# =============================================================================
set -euo pipefail

REPO_OWNER='Limao0521'
REPO_NAME='claude-qwen-enterprise'
REPO_BRANCH='main'

if [ "$REPO_OWNER" = 'TU-USUARIO' ]; then
  echo 'install-remote.sh still has the placeholder owner. Set REPO_OWNER to the real GitHub user or organization, then publish again.' >&2
  exit 1
fi

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
else
  echo 'Necesitas curl o wget (Linux: sudo apt install curl; macOS ya trae curl).' >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://github.com/$REPO_OWNER/$REPO_NAME/archive/refs/heads/$REPO_BRANCH.tar.gz"
echo "Descargando $url"
fetch "$url" "$tmp/repo.tar.gz"
tar -xzf "$tmp/repo.tar.gz" -C "$tmp"

project="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "$project" ] || [ ! -f "$project/install.sh" ]; then
  echo 'El archivo descargado no contiene install.sh. Verifica la URL y que el repositorio sea accesible para tu cuenta.' >&2
  exit 1
fi
bash "$project/install.sh"
