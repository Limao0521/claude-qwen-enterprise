#!/usr/bin/env bash
# =============================================================================
#  claude-qwen - lanzador de Claude Code + Qwen Enterprise para Linux
#  (Ubuntu 20.04 o superior). Modos: launch | fast | auth | status | test | selftest
#
#  La clave empresarial NUNCA se escribe en este proyecto: se guarda en el
#  keyring (secret-tool/libsecret) si esta disponible, o en
#  ~/.config/claude-qwen-enterprise/api-key con permisos 600. Solo el proceso
#  de Claude Code la recibe, via variable de entorno, mediante exec (este
#  shell desaparece al lanzarlo).
# =============================================================================
set -euo pipefail

MODE="${1:-launch}"
if [ $# -gt 0 ]; then shift; fi
case "$MODE" in
  launch|fast|auth|status|test|selftest) ;;
  *) echo "Modo desconocido: $MODE (launch|fast|auth|status|test|selftest)" >&2; exit 2 ;;
esac

APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="$HOME/.local/share/claude-qwen-enterprise"
CONFIG="$RUNTIME/claude-config"
SETTINGS="$APP/qwen-settings.json"
AGENTS="$APP/qwen-agents.json"
ENDPOINT='https://llm-kcqiiw0if0n8a3fc.ap-southeast-1.maas.aliyuncs.com/apps/anthropic'
KEYFILE="$HOME/.config/claude-qwen-enterprise/api-key"
SECRET_ATTR='application'
SECRET_VAL='claude-qwen-enterprise'

have_secret_tool() { command -v secret-tool >/dev/null 2>&1; }

read_key() {
  local key=''
  if have_secret_tool; then
    key="$(secret-tool lookup "$SECRET_ATTR" "$SECRET_VAL" 2>/dev/null || true)"
  fi
  if [ -z "$key" ] && [ -f "$KEYFILE" ]; then
    key="$(cat "$KEYFILE" 2>/dev/null || true)"
  fi
  if [ -z "$key" ]; then return 1; fi
  printf '%s' "$key"
}

save_key() {
  local key="$1"
  if have_secret_tool && printf '%s' "$key" | secret-tool store --label='Claude Qwen Enterprise API key (Alibaba Singapore)' "$SECRET_ATTR" "$SECRET_VAL" >/dev/null 2>&1; then
    rm -f "$KEYFILE"
    echo 'Clave guardada en el keyring (libsecret/secret-tool).'
  else
    install -d "$(dirname "$KEYFILE")"
    chmod 700 "$(dirname "$KEYFILE")" 2>/dev/null || true
    ( umask 077; printf '%s' "$key" > "$KEYFILE" )
    chmod 600 "$KEYFILE" 2>/dev/null || true
    echo "Clave guardada en $KEYFILE (permisos 600; no hay keyring disponible para tu usuario)."
  fi
}

remove_key() {
  if have_secret_tool; then secret-tool clear "$SECRET_ATTR" "$SECRET_VAL" >/dev/null 2>&1 || true; fi
  rm -f "$KEYFILE"
}

key_present() { read_key >/dev/null 2>&1; }

# --- selftest: ida y vuelta con una credencial ficticia y almacenamiento aislado
if [ "$MODE" = selftest ]; then
  tmp="$(mktemp -d)"
  KEYFILE="$tmp/api-key"
  SECRET_VAL="claude-qwen-enterprise-selftest-$$-$(date +%s)"
  save_key 'dummy-test-only-731' >/dev/null
  roundtrip="$(read_key || true)"
  remove_key
  rm -rf "$tmp"
  if [ "$roundtrip" = 'dummy-test-only-731' ]; then
    echo 'selftest: ida y vuelta de credencial correcta.'
    exit 0
  fi
  echo 'selftest: fallo la ida y vuelta de credencial.' >&2
  exit 1
fi

# --- auth ----------------------------------------------------------------------
if [ "$MODE" = auth ]; then
  if [ "${1:-}" = '--delete' ]; then
    remove_key
    echo 'Credencial empresarial eliminada.'
    exit 0
  fi
  if [ ! -t 0 ]; then
    echo 'Ejecuta claude-qwen-auth en una terminal interactiva. No pegues la clave en el chat ni como argumento.' >&2
    exit 2
  fi
  printf 'Alibaba Model Studio API key: ' >&2
  IFS= read -rs key || true
  printf '\n' >&2
  if [ "${#key}" -lt 8 ]; then
    unset key
    echo 'La clave falta o es demasiado corta.' >&2
    exit 2
  fi
  save_key "$key"
  unset key
  exit 0
fi

# --- status ---------------------------------------------------------------------
if [ "$MODE" = status ]; then
  cli="$(command -v claude || true)"
  version='<missing>'
  if [ -n "$cli" ]; then version="$("$cli" --version 2>/dev/null || echo '<error>')"; fi
  backend='none'
  if have_secret_tool && [ -n "$(secret-tool lookup "$SECRET_ATTR" "$SECRET_VAL" 2>/dev/null || true)" ]; then
    backend='secret-tool (libsecret)'
  elif [ -f "$KEYFILE" ]; then
    backend="archivo $KEYFILE (600)"
  fi
  agent_count=0
  if [ -d "$CONFIG/agents" ]; then
    agent_count="$(find "$CONFIG/agents" -maxdepth 1 -name '*.md' -type f | wc -l)"
  fi
  echo "ClaudeExecutable : ${cli:-<missing>}"
  echo "ClaudeVersion    : $version"
  echo "Endpoint         : $ENDPOINT"
  echo "ConfigDirectory  : $CONFIG"
  echo "Credential       : $backend"
  echo "Primary          : qwen3.8-max"
  echo "Fast             : qwen3.8-flash"
  echo "SubagentDefault  : qwen3.7-plus"
  echo "AgentFiles       : $agent_count"
  exit 0
fi

# --- launch / fast / test ----------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --settings|--settings=*|--setting-sources|--setting-sources=*|--fallback-model|--fallback-model=*)
      echo 'Estos overrides estan bloqueados en el lanzador Qwen para mantener el routing explicito.' >&2
      exit 2 ;;
  esac
done

if ! key_present; then
  echo 'No hay clave empresarial registrada. Ejecuta claude-qwen-auth en una terminal interactiva.' >&2
  exit 2
fi
[ -f "$SETTINGS" ] || { echo 'Falta el archivo de settings de Qwen.' >&2; exit 1; }
[ -f "$AGENTS" ] || { echo 'Falta el archivo de agentes de Qwen.' >&2; exit 1; }
grep -Fq "$ENDPOINT" "$SETTINGS" || { echo 'El endpoint de qwen-settings.json no coincide con el endpoint empresarial fijado.' >&2; exit 1; }

cli="$(command -v claude || true)"
if [ -z "$cli" ]; then
  echo 'claude no esta en PATH. Instala Claude Code: curl -fsSL https://claude.ai/install.sh | bash' >&2
  exit 1
fi

mkdir -p "$CONFIG"

# Borrar variables heredadas de Anthropic/Claude para que nada interfiera.
while IFS= read -r var; do
  case "$var" in
    ANTHROPIC_*|CLAUDE_CODE_USE_*|CLAUDE_CONFIG_DIR|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_OAUTH_REFRESH_TOKEN|DISABLE_LOGIN_COMMAND|DISABLE_LOGOUT_COMMAND)
      unset "$var" ;;
  esac
done < <(compgen -e || true)

export CLAUDE_CONFIG_DIR="$CONFIG"
export ANTHROPIC_BASE_URL="$ENDPOINT"
if ! ANTHROPIC_API_KEY="$(read_key)"; then
  echo 'No se pudo leer la clave empresarial.' >&2
  exit 2
fi
export ANTHROPIC_API_KEY
if [ "$MODE" = fast ]; then
  export ANTHROPIC_MODEL='qwen3.8-flash'
else
  export ANTHROPIC_MODEL='qwen3.8-max'
fi
export DISABLE_LOGIN_COMMAND=1
export DISABLE_LOGOUT_COMMAND=1

if [ "$MODE" = test ]; then
  py="$(command -v python3 || true)"
  if [ -z "$py" ]; then
    echo 'claude-qwen-test necesita python3 (sudo apt install python3).' >&2
    exit 1
  fi
  exec "$py" "$APP/test-qwen.py" --claude "$cli" --settings "$SETTINGS" --agents-file "$AGENTS" --endpoint "$ENDPOINT"
fi

# exec: la clave vive solo en el proceso de Claude Code; este shell desaparece.
exec "$cli" --strict-mcp-config --setting-sources user --settings "$SETTINGS" --agents "$(cat "$AGENTS")" --model "$ANTHROPIC_MODEL" "$@"
