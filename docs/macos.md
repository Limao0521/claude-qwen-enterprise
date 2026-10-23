# Soporte macOS — documentación técnica y reproducibilidad

Este documento describe la feature de soporte para macOS agregada el 22-oct-2026 en los commits `0c31141337aabc9249c716bd99da5c8608dd1d9c` ("Add macOS support with Keychain credentials and bash 3.2 compatibility") y `e59ad59a397789a26e4f14639a05a0c291151cbb` ("Guard optional tool_reply in multi-turn smoke check"), ambos en `main`.

Antes de esta feature el proyecto solo soportaba Windows (PowerShell) y Linux Ubuntu 20.04+ (bash). Los scripts `.sh` existentes casi funcionaban en macOS, con tres bloqueos reales que motivaron los cambios:

1. macOS no tiene `secret-tool`/libsecret; su almacén seguro es el **Keychain**, accesible con el CLI `security`.
2. macOS ships **bash 3.2.57** (licencia GPLv3); `claude-qwen.sh` usaba `compgen -e`, que solo existe desde bash 4+.
3. El shell por defecto es **zsh** desde Catalina; `install.sh` solo agregaba PATH a `~/.profile` y `~/.bashrc`, que zsh no lee.

Además, los `.sh` estaban registrados en git sin bit ejecutable (modo `100644`), lo que impedía `./install.sh` en un clon de Unix.

## Cambios por archivo (qué y por qué)

### `claude-qwen.sh` (lanzador; Linux y macOS)

| Cambio | Por qué |
|---|---|
| `OS="$(uname -s)"` + helpers `have_keychain()` (solo si `Darwin` y existe `security`) y `have_secret_tool()` (solo si NO es `Darwin`) | Un único script para ambos Unix; cada backend de credencial se activa solo donde existe. En Linux el comportamiento es idéntico al anterior. |
| `kc_account()` → `${USER:-$(id -un)}` | El ítem del Keychain se indexa por servicio `claude-qwen-enterprise` + cuenta; `id -un` cubre shells donde `$USER` no está definida. |
| `read_key()`: rama Keychain (`security find-generic-password -a ... -s ... -w`) antes que `secret-tool`, con el archivo 600 como respaldo final | Jerarquía análoga a Windows Credential Manager; el respaldo permite Macs sin Keychain desbloqueado. |
| `save_key()`: rama `security add-generic-password -U -a ... -s claude-qwen-enterprise -l "$KC_LABEL" -w "$key"` | `-U` actualiza si el ítem ya existe (rotación de clave). Etiqueta: `Claude Qwen Enterprise API key (Alibaba Singapore)`. |
| `remove_key()`: `security delete-generic-password ... \|\| true` + `rm -f "$KEYFILE"` | Borrado idempotente: no falla si el ítem no existe (código 44 del `security` real). |
| `selftest`: también sobrescribe `KC_SERVICE` con el nombre único por corrida | El selftest debe escribir/leer/borrar en un servicio aislado para no tocar la credencial real ni colisionar entre corridas paralelas. |
| `status`: backend `Keychain de macOS (security)` cuando `find-generic-password` devuelve clave | Diagnóstico honesto de dónde vive la credencial. |
| `compgen -e` → `compgen -A export 2>/dev/null \|\| env \| cut -d= -f1`, y `unset "$var" 2>/dev/null \|\| true` | `-A export` existe desde bash 2.x (ok en 3.2); el fallback con `env` cubre shells sin compgen, y el `unset` tolerante evita que líneas basura (valores multi-línea en `env`) maten el script bajo `set -e`. |

**Nota de seguridad (aceptada y consistente con el modelo de amenazas del README):** `security add-generic-password -w "$key"` pasa la clave por argv, brevemente visible para `ps` del mismo usuario. Es la única interfaz no interactiva del CLI `security`; el README ya documenta que procesos del mismo usuario pueden inspeccionar `ANTHROPIC_API_KEY` durante una sesión. La lectura posterior (`find-generic-password -w`) no expone nada por argv.

**Convención:** todo lo nuevo en este archivo debe mantenerse compatible con bash 3.2 (sin `mapfile`, `declare -A`, `${var,,}`, `|&`, `&>>`).

### `install.sh` (instalador; Linux y macOS)

| Cambio | Por qué |
|---|---|
| `OS="$(uname -s)"` | Ramificar solo lo específico de cada sistema; rutas (`~/.local/share/...`, `~/.local/bin`) y shims son idénticos en ambos. |
| En `Darwin`, PATH se agrega a `~/.zprofile`, `~/.zshrc` y `~/.bash_profile`; en Linux se conserva `~/.profile` + `~/.bashrc` | zsh (login shell en Terminal.app) lee `.zprofile`/`.zshrc`; `.bash_profile` cubre usuarios de bash en macOS (bash lo lee en shells de login y, si existe, toma precedencia sobre `.profile`). |
| Aviso python3: `xcode-select --install` en macOS, `sudo apt install python3` en Linux | En macOS python3 viene con las Command Line Tools, no con apt. |
| Mensaje de `--remove`: pista `security delete-generic-password -s claude-qwen-enterprise` en macOS | Coherente con el backend usado; el flujo de borrado recomendado sigue siendo `claude-qwen-auth --delete` **antes** de desinstalar. |

Lo demás (`install -d`, `install -m 644`, `chmod 755`, `find -maxdepth`, `mktemp -d`) ya es compatible con las versiones BSD de macOS; no se cambió.

### `install-remote.sh` (instalador de un comando)

Solo comentarios y el mensaje de curl/wget (`macOS ya trae curl`). La lógica (descargar tarball de GitHub, `tar -xzf`, ejecutar `install.sh`) ya era portable. Este es el entry point recomendado en Mac.

### `test-qwen.py` (smoke test E2E)

- Docstring y `argparse` actualizados a "Linux/macOS" (commit `0c31141`).
- `(tool_reply or {}).get("content", [])` (commit `e59ad59`): guarda defensiva para Pyright; en runtime la rama `if tool_call:` ya garantizaba `tool_reply` no nulo. Sin cambio de comportamiento.
- El resto del archivo ya era portable (solo stdlib: `urllib`, `subprocess`, `tempfile`). En macOS, `python3` de las CLT trae certificados del sistema, así que TLS al endpoint funciona sin configuración extra.

### `README.md` / `AGENTS.md`

Documentación de usuario y de agentes: macOS en título/intro/requisitos, columna macOS en la tabla de rutas, nota sobre el estado de validación (stub-testing desde Windows), ítem 9 de diagnóstico (python3 vía `xcode-select --install`, permiso de Keychain en Terminal), desinstalación, convención bash 3.2 y de bits ejecutables, y referencia a este documento.

### Índice de git (modos de archivo)

`git update-index --chmod=+x claude-qwen.sh install.sh install-remote.sh` → modos `100644` ⇒ `100755` en el commit `0c31141`. En Windows el bit no se refleja en el working tree (NTFS no lo soporta); lo que viaja a los clones de macOS/Linux es el modo del índice. `test-qwen.py` se dejó en `644` porque siempre se invoca como `python3 test-qwen.py`, nunca directamente.

## Instalación y verificación en un Mac real (paso a paso)

Requisitos: macOS 11+, bash (incluido), Claude Code (`claude --version`), tu API key del workspace empresarial de Singapur. Si `python3` no responde: `xcode-select --install` (solo necesario para `claude-qwen-test`).

1. **Instalar** (Terminal normal, sin sudo):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.sh | bash
   ```

   Alternativa con clon local (los `.sh` ya son ejecutables en el índice):

   ```bash
   git clone https://github.com/Limao0521/claude-qwen-enterprise.git
   cd claude-qwen-enterprise && ./install.sh
   ```

2. **Abrir una terminal NUEVA** (refresca PATH desde `~/.zprofile`).
3. `claude-qwen-status` → comprobar: `ClaudeExecutable` distinto de `<missing>`, `Endpoint` empresarial, `Credential: none` (aún sin clave), `AgentFiles: 5` (el instalador ya copió los subagentes al perfil Qwen).
4. `claude-qwen-auth` → pegar la clave en el aviso oculto. Resultado esperado: `Clave guardada en el Keychain de macOS (login).` Verificar en *Acceso a Llaveros.app* → ítem `claude-qwen-enterprise`.
5. `claude-qwen-status` → `Credential : Keychain de macOS (security)`.
6. `claude-qwen --print "responde OK"` → debe devolver texto del modelo `qwen3.8-max` sin tocar `~/.claude`.
7. `claude-qwen-fast --print "responde OK"` → modelo `qwen3.8-flash`.
8. `claude-qwen-test` → smoke E2E completo (llamadas reales a la API; puede generar cargos). Esperado: PASS en autenticación, tool-use, multivuelta, herramientas de Claude Code y subagentes.
9. Primera vez que un comando lee la clave: si macOS muestra un diálogo pidiendo permiso para acceder al ítem del Keychain, elegir **Permitir siempre** para que `security` no vuelva a preguntar.
10. **Desinstalación**: `claude-qwen-auth --delete` (borra la clave del Keychain) y luego `bash "$HOME/.local/share/claude-qwen-enterprise/app/install.sh" --remove`.

## Reproducir las pruebas con stubs desde Windows

La feature se validó sin Mac físico usando **Git Bash** y stubs que simulan `uname`, `security` y `claude`. Esto verifica la *lógica de los scripts* (ramas Darwin, flujos de credencial, scrubbing de entorno, instalador), no los binarios reales de Apple. Cualquier persona puede repetirlo:

1. Crear una carpeta de stubs, p. ej. `%TEMP%\cqtest\stubs`, con estos tres archivos (LF, sin BOM):

   `uname`:

   ```bash
   #!/usr/bin/env bash
   echo Darwin
   ```

   `security` (emula el Keychain con un directorio de estado; `-w` imprime/guarda la contraseña; exit 44 = ítem ausente, como el real):

   ```bash
   #!/usr/bin/env bash
   if [ -z "${CQ_FAKE_KEYCHAIN:-}" ]; then echo "stub security: CQ_FAKE_KEYCHAIN no definida" >&2; exit 3; fi
   mkdir -p "$CQ_FAKE_KEYCHAIN"
   cmd="${1:-}"; shift || true
   svc=''; pass=''; want_w=0
   while [ $# -gt 0 ]; do
     case "$1" in
       -a) shift 2 ;;
       -s) svc="${2:-}"; shift 2 ;;
       -l) shift 2 ;;
       -w) if [ $# -ge 2 ] && [ -n "${2:-}" ]; then pass="$2"; shift 2; else want_w=1; shift; fi ;;
       -U|-T) shift ;;
       *) shift ;;
     esac
   done
   item="$CQ_FAKE_KEYCHAIN/$(printf '%s' "$svc" | tr '/' '_')"
   case "$cmd" in
     add-generic-password) [ -n "$pass" ] || exit 1; printf '%s' "$pass" > "$item" ;;
     find-generic-password) [ -f "$item" ] || exit 44; if [ "$want_w" -eq 1 ]; then cat "$item"; echo; fi ;;
     delete-generic-password) [ -f "$item" ] || exit 44; rm -f "$item" ;;
     *) exit 1 ;;
   esac
   ```

   `claude` (revela argumentos y entorno recibido):

   ```bash
   #!/usr/bin/env bash
   if [ "${1:-}" = '--version' ]; then echo '9.9.9-stub (Claude Code)'; exit 0; fi
   echo "ARGS: $*"
   echo "BASE_URL=${ANTHROPIC_BASE_URL:-<unset>}"
   echo "MODEL=${ANTHROPIC_MODEL:-<unset>}"
   echo "CONFIG_DIR=${CLAUDE_CONFIG_DIR:-<unset>}"
   case "${ANTHROPIC_API_KEY:-}" in
     dummy-*) echo "API_KEY=present ${#ANTHROPIC_API_KEY} chars" ;;
     '') echo 'API_KEY=<unset>' ;;
     *) echo 'API_KEY=<unexpected-value>' ;;
   esac
   echo "OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN:-<unset>}"
   ```

2. Dar permisos y correr la matriz desde la raíz del repo (`STUBS`, `KC` = keychain falsa, `H` = HOME falso):

   ```bash
   chmod +x "$STUBS"/*
   # A. Sintaxis y scan anti-bash4
   bash -n claude-qwen.sh install.sh install-remote.sh
   grep -nE 'compgen -e|declare -A|mapfile|readarray|\|&|&>>' claude-qwen.sh install.sh install-remote.sh
   # B. selftest backend archivo (sin stubs) y backend Keychain (con stubs)
   bash claude-qwen.sh selftest
   CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh selftest && ls -A "$KC"   # dir vacía tras borrar
   # C. status con clave sembrada en la keychain falsa
   mkdir -p "$KC"; printf 'dummy-key-123456789' > "$KC/claude-qwen-enterprise"
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh status
   # D. launch con entorno hostil heredado + fast
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" ANTHROPIC_BASE_URL='https://evil.example' ANTHROPIC_MODEL='otro' \
     CLAUDE_CODE_OAUTH_TOKEN=ghost PATH="$STUBS:$PATH" bash claude-qwen.sh launch --print hola
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh fast --print hola
   # E. override bloqueado / F. sin clave / G. delete idempotente
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh launch --settings x; echo "exit:$?"
   rm -f "$KC"/*; HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh launch; echo "exit:$?"
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" bash claude-qwen.sh auth --delete
   # H. instalador como Darwin + shims instalados + remove
   HOME="$H" PATH="$STUBS:$PATH" bash install.sh
   HOME="$H" CQ_FAKE_KEYCHAIN="$KC" PATH="$STUBS:$PATH" "$H/.local/bin/claude-qwen-status"
   HOME="$H" PATH="$STUBS:$PATH" bash "$H/.local/share/claude-qwen-enterprise/app/install.sh" --remove
   # I. Regresión Linux: mismos comandos SIN los stubs → rutas .profile/.bashrc y selftest archivo
   ```

3. **Resultados esperados** (todos obtenidos el 22-oct-2026):

   | Prueba | Esperado |
   |---|---|
   | A | `bash -n` sin errores; grep solo puede dar comentarios |
   | B | `selftest: ida y vuelta de credencial correcta.` ×2; `$KC` queda vacío |
   | C | `Credential : Keychain de macOS (security)` |
   | D | `BASE_URL=https://llm-kcqiiw0if0n8a3fc...` (no el hostil), `MODEL=qwen3.8-max`, `OAUTH_TOKEN=<unset>`, `API_KEY=present 19 chars`; fast → `MODEL=qwen3.8-flash` |
   | E/F | mensaje de bloqueo / `No hay clave empresarial registrada...`, ambos `exit:2` |
   | G | `Credencial empresarial eliminada.` incluso sin ítem |
   | H | PATH agregado a `~/.zprofile, ~/.zshrc y ~/.bash_profile`; 5 shims `755`; app completa; status del shim con `AgentFiles: 5`; remove conserva `claude-config` y muestra la pista de `security` |
   | I | `.profile`/`.bashrc` (no `.zprofile`), mensaje de `secret-tool` en remove |

## Verificado con stubs vs. pendiente en Mac real

**Verificado (lógica):** todo lo de la tabla anterior.

**Pendiente en hardware real:** semántica exacta del `security` de Apple (ACL y diálogo de permiso de la primera lectura, `-U` sobre ítem existente, códigos de salida), bash 3.2.57 real (la revisión fue estática: sin construcciones bash 4+, pero no se ejecutó), utilidades BSD (`install`, `find -maxdepth`, `mktemp -d` — todas documentadas como compatibles), y el smoke E2E (`claude-qwen-test`) con Claude Code real en macOS. El README señala esta limitación; al validar en un Mac real, actualizar el README/AGENTS.md y este documento.

## Cómo revertir

- **Revertir la feature completa** (desde la raíz del repo, orden más-nuevo-primero):

  ```bash
  git revert --no-edit e59ad59a397789a26e4f14639a05a0c291151cbb 0c31141337aabc9249c716bd99da5c8608dd1d9c
  git push origin main
  ```

  Esto restaura también los modos `100644` de los `.sh`. En máquinas donde ya se haya ejecutado el instalador nuevo, volver a correr `install.sh` tras el revert para que la copia instalada pierda las ramas macOS.

- **Revertir solo los bits ejecutables** (conservando la feature): `git update-index --chmod=-x claude-qwen.sh install.sh install-remote.sh` + commit.

- **Revertir solo un archivo**: `git checkout 0c31141^ -- <archivo>` + commit (el revert por archivo de los modos requiere `update-index` explícito).

Nunca usar force-push en `main`: los instaladores de un comando apuntan a `raw.githubusercontent.com/.../main` y un histórico reescrito rompería descargas en curso.
