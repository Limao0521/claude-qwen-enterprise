#!/usr/bin/env bash
# =============================================================================
#  Instalador de claude-qwen para Linux (Ubuntu 20.04+) y macOS.
#  Uso:
#    ./install.sh            instala para el usuario actual
#    ./install.sh --remove   retira shims y app (conserva datos y credencial)
#  No requiere root. No guarda ninguna API key: cada persona registra la suya
#  con claude-qwen-auth. La app queda en ~/.local/share/claude-qwen-enterprise/app
#  y los comandos en ~/.local/bin.
# =============================================================================
set -euo pipefail

REMOVE=0
if [ "${1:-}" = '--remove' ]; then REMOVE=1; fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"
RUNTIME="$HOME/.local/share/claude-qwen-enterprise"
APP="$RUNTIME/app"
CONFIG_AGENTS="$RUNTIME/claude-config/agents"
BIN="$HOME/.local/bin"
APP_SCRIPT="$APP/claude-qwen.sh"
APP_FILES="claude-qwen.sh test-qwen.py install.sh qwen-settings.json qwen-agents.json"
SHIMS="claude-qwen:launch claude-qwen-fast:fast claude-qwen-auth:auth claude-qwen-status:status claude-qwen-test:test"

if [ "$REMOVE" -eq 0 ]; then
  for item in $APP_FILES agents; do
    if [ ! -e "$SRC/$item" ]; then echo "Falta un elemento del proyecto: $item" >&2; exit 1; fi
  done
  install -d "$APP" "$APP/agents" "$CONFIG_AGENTS" "$BIN"
  for item in $APP_FILES; do
    install -m 644 "$SRC/$item" "$APP/$item"
  done
  chmod 755 "$APP_SCRIPT"
  for md in "$SRC"/agents/*.md; do
    install -m 644 "$md" "$APP/agents/"
    install -m 644 "$md" "$CONFIG_AGENTS/"
  done
else
  install -d "$BIN"
fi

for entry in $SHIMS; do
  name="${entry%%:*}"
  mode="${entry##*:}"
  path="$BIN/$name"
  if [ -e "$path" ] && ! grep -q 'claude-qwen\.sh' "$path" 2>/dev/null; then
    echo "No se reemplaza un comando ajeno: $path" >&2
    exit 1
  fi
  if [ "$REMOVE" -eq 1 ]; then rm -f "$path"; continue; fi
  body='#!/usr/bin/env bash
exec "'"$APP_SCRIPT"'" '"$mode"' "$@"
'
  if [ -e "$path" ] && [ "$(cat "$path" 2>/dev/null || true)" = "$(printf '%s' "$body")" ]; then continue; fi
  if [ -e "$path" ]; then cp "$path" "$path.bak-$(date +%Y%m%d-%H%M%S)"; fi
  printf '%s' "$body" > "$path"
  chmod 755 "$path"
done

if [ "$REMOVE" -eq 1 ]; then
  rm -rf "$APP"
  echo 'Comandos claude-qwen retirados y copia de la app eliminada.'
  echo "Los datos de sesion ($RUNTIME/claude-config) y la credencial no se tocaron."
  if [ "$OS" = Darwin ]; then
    echo 'Para borrar la clave: security delete-generic-password -s claude-qwen-enterprise (si usaste el Keychain) o rm ~/.config/claude-qwen-enterprise/api-key'
  else
    echo 'Para borrar la clave: secret-tool clear application claude-qwen-enterprise (si usaste keyring) o rm ~/.config/claude-qwen-enterprise/api-key'
  fi
  exit 0
fi

path_missing=0
case ":$PATH:" in *":$BIN:"*) ;; *) path_missing=1 ;; esac
if [ "$path_missing" -eq 1 ]; then
  if [ "$OS" = Darwin ]; then
    # macOS usa zsh por defecto; los usuarios de bash leen ~/.bash_profile.
    rc_files="$HOME/.zprofile $HOME/.zshrc $HOME/.bash_profile"
    rc_names='~/.zprofile, ~/.zshrc y ~/.bash_profile'
  else
    rc_files="$HOME/.profile $HOME/.bashrc"
    rc_names='~/.profile y ~/.bashrc'
  fi
  for rc in $rc_files; do
    touch "$rc"
    if ! grep -qF '# claude-qwen' "$rc" 2>/dev/null; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH" # claude-qwen\n' >> "$rc"
    fi
  done
  echo "Se agrego $BIN al PATH en $rc_names."
fi

if ! command -v claude >/dev/null 2>&1 && [ ! -x "$BIN/claude" ]; then
  echo 'Aviso: no se encontro claude. Instala Claude Code: curl -fsSL https://claude.ai/install.sh | bash'
fi
if ! command -v python3 >/dev/null 2>&1; then
  if [ "$OS" = Darwin ]; then
    echo 'Aviso: claude-qwen-test necesita python3 (xcode-select --install).'
  else
    echo 'Aviso: claude-qwen-test necesita python3 (sudo apt install python3).'
  fi
fi

echo 'Comandos claude-qwen instalados.'
echo ''
echo 'Pasos siguientes:'
echo '  1. Abre una terminal NUEVA (para refrescar el PATH).'
echo '  2. claude-qwen-status    (comprobacion local, sin llamadas a la API)'
echo '  3. claude-qwen-auth      (pega TU clave empresarial en el aviso oculto)'
echo '  4. claude-qwen           (inicia una sesion con qwen3.8-max)'
