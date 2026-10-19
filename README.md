# claude-qwen — Claude Code + Qwen Enterprise (Windows y Linux)

Usa Claude Code con los modelos Qwen de Alibaba Model Studio (`qwen3.8-max`, `qwen3.7-plus`, `qwen3.8-flash`) a través del endpoint empresarial de Singapur, sin tocar tu perfil oficial de Claude. Funciona en **Windows 10/11** (PowerShell 5.1+) y en **Linux Ubuntu 20.04 o superior** (bash + python3). Cada persona usa **su propia API key**: este repositorio **no contiene ninguna clave**.

## Requisitos previos

1. **Windows 10/11** con PowerShell 5.1+ (el que viene con Windows), o **Ubuntu 20.04+** con bash y python3 (ya vienen instalados; si falta python3: `sudo apt install python3`).
2. Claude Code instalado (`claude --version` debe responder). Si no lo tienes:
   - Windows: `powershell -NoProfile -Command "irm https://claude.ai/install.ps1 | iex"`
   - Linux: `curl -fsSL https://claude.ai/install.sh | bash`
   - Alternativa con Node: `npm install -g @anthropic-ai/claude-code`
3. Tu API key de Alibaba Model Studio para el workspace empresarial de Singapur (pídela al administrador del workspace).

## Instalación — un solo comando

Abre una terminal **normal** (sin administrador/root), pega el comando de tu sistema y presiona Enter.

**Windows** (PowerShell):

```powershell
powershell -NoProfile -Command "irm https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.ps1 | iex"
```

**Linux** (Ubuntu 20.04+):

```bash
curl -fsSL https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.sh | bash
```

El instalador copia la app a una ubicación estable de tu usuario y crea los cinco comandos en una carpeta que ya esté (o que agrega) a tu PATH. No modifica tu instalación oficial de Claude ni requiere permisos de administrador.

| | Windows | Linux |
|---|---|---|
| App | `%LOCALAPPDATA%\ClaudeQwenEnterprise\app` | `~/.local/share/claude-qwen-enterprise/app` |
| Comandos | `%USERPROFILE%\.local\bin\*.cmd` | `~/.local/bin/*` |
| Clave | Administrador de credenciales de Windows | Keyring libsecret (`secret-tool`) o `~/.config/claude-qwen-enterprise/api-key` con permisos 600 |
| Perfil Claude Code | `%LOCALAPPDATA%\ClaudeQwenEnterprise\claude-config` | `~/.local/share/claude-qwen-enterprise/claude-config` |

**Alternativa local** (si te pasaron la carpeta o el zip del repo): descomprime, entra en la carpeta y ejecuta:

```powershell
# Windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

```bash
# Linux
bash ./install.sh
```

## Alta de tu clave (una sola vez)

Abre una **nueva** terminal (para refrescar el PATH) y ejecuta:

```
claude-qwen-status   # comprobación local; no llama a la API
claude-qwen-auth     # pega TU clave en el aviso oculto
claude-qwen-test     # opcional; hace llamadas reales a la API (puede generar cargos)
```

Nunca pegues la clave en un chat, un correo o un argumento de comando: solo en el aviso oculto de `claude-qwen-auth`. La clave queda en el almacenamiento seguro de tu usuario (ver tabla anterior), no en archivos del proyecto ni del repositorio.

## Uso diario

Los mismos comandos en ambos sistemas:

```
claude-qwen                  # sesión interactiva con qwen3.8-max
claude-qwen-fast             # sesión con qwen3.8-flash
claude-qwen --print "Hola"   # los argumentos extra se envían a Claude Code
claude-qwen-auth             # rotar la clave (vuelve a pegarla)
claude-qwen-auth --delete    # borrar la clave de esta máquina
```

El comando oficial `claude` sigue intacto; los comandos Qwen son independientes.

## Modelos y subagentes

| Rol | Modelo |
|---|---|
| Principal y planificación | `qwen3.8-max` |
| Alias Opus; revisión crítica | `qwen3.8-max` |
| Alias Sonnet; implementación; pruebas; subagente general | `qwen3.7-plus` |
| Alias Haiku; exploración; lanzamiento rápido | `qwen3.8-flash` |

`qwen3.8-plus` y `qwen3-coder-plus` no se usan porque el endpoint devuelve HTTP 404 para esos IDs. Hay cinco subagentes listos para usar: `qwen-planner`, `qwen-implementer`, `qwen-explorer`, `qwen-reviewer` y `qwen-tester` (definidos en `agents/` y `qwen-agents.json`). Estas asignaciones son hipótesis de trabajo ajustables.

## Cómo funciona y qué aislamiento tiene

- El lanzador abre un proceso separado, borra las variables `ANTHROPIC_*` y `CLAUDE_*` heredadas, fija el endpoint empresarial y pasa la clave **solo al proceso de Claude Code** como `ANTHROPIC_API_KEY` (en Linux el shell del lanzador es reemplazado por `exec`; en Windows el proceso padre restaura su entorno al terminar). Nada queda en archivos del proyecto.
- Claude Code corre con su propio `CLAUDE_CONFIG_DIR`, `--strict-mcp-config` (no carga tus servidores MCP) y `--setting-sources user`. `qwen-settings.json` desactiva el descubrimiento automático de `CLAUDE.md` y la memoria automática, y el lanzador rechaza `--settings`, `--setting-sources` y `--fallback-model` enviados por el usuario para que el routing al proveedor sea siempre explícito.
- Tu perfil oficial (`~/.claude`, `.claude.json`, `claude`) no se lee ni se modifica; los ajustes locales y compartidos de cada repositorio se excluyen para que nada pueda cambiar la clave o el proveedor.
- Límite conocido: la clave viaja como variable de entorno del proceso Claude Code y sus subprocesos; procesos del mismo usuario con permisos suficientes podrían inspeccionarla. Evita ejecutar comandos no confiables dentro de una sesión Qwen. En Linux sin keyring gráfico, la clave queda en un archivo con permisos 600 (equivalente a lo que hacen npm, docker y otras CLI).
- Si un proyecto necesita sus instrucciones o MCP, incorpóralas explícitamente al prompt o a un archivo de prompts; no se copia nada automáticamente desde tu perfil oficial.

## Diagnóstico

1. **El comando no aparece tras instalar** → abre una terminal NUEVA; si sigue sin aparecer comprueba tu PATH: en Windows `%USERPROFILE%\.local\bin`, en Linux `~/.local/bin` (el instalador agrega la línea a `~/.profile` y `~/.bashrc`).
2. **Falta la clave** → ejecuta `claude-qwen-auth` en una terminal interactiva.
3. **HTTP 401** → la clave debe ser del mismo workspace y región que el host configurado. Rótala con `claude-qwen-auth`.
4. **404 en `/v1/models`** → ese catálogo no existe en la interfaz Anthropic de Alibaba; usa los IDs explícitos. Un 404 en `/v1/messages` sí indica un problema del endpoint.
5. **Claude Code advierte que un modelo Qwen es desconocido** → comprueba que la solicitud siga usando la URL empresarial; la advertencia del catálogo local no equivale a un fallo del endpoint.
6. **Falla un agente** → revisa `qwen-agents.json`, la salida de `claude-qwen-test` y el límite de solicitudes del workspace. Empieza con máximo dos agentes.
7. **Windows: scripts bloqueados por política de ejecución** (equipos administrados) → usa la alternativa local con `-ExecutionPolicy Bypass` o consulta a tu administrador.
8. **Linux: errores TLS/-certificados** → instala certificados: `sudo apt install ca-certificates`. `claude-qwen-test` necesita `python3`.

`claude-qwen-status` solo comprueba archivos y almacenamiento de credenciales; no prueba el servicio. `claude-qwen-test` usa una carpeta temporal fuera de repositorios, hace llamadas a `/v1/messages`, una prueba de herramientas, una continuación multivuelta y sesiones CLI con uno y dos subagentes; resume resultados sin imprimir la clave y borra su carpeta temporal al terminar. El solapamiento real de dos agentes se informa como **no verificado** si no hay evidencia de concurrencia.

## Desinstalación

1. Borra tu clave: `claude-qwen-auth --delete`
2. Quita comandos y app:

   ```powershell
   # Windows
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ClaudeQwenEnterprise\app\install.ps1" -Remove
   ```

   ```bash
   # Linux
   bash "$HOME/.local/share/claude-qwen-enterprise/app/install.sh" --remove
   ```

3. Opcional: inspecciona y elimina la carpeta de datos Qwen a mano (`%LOCALAPPDATA%\ClaudeQwenEnterprise` en Windows, `~/.local/share/claude-qwen-enterprise` en Linux; contiene tu historial de sesiones). **No toques** `~/.claude`, `~/.claude.json` ni el ejecutable oficial `claude`.

## Archivos del proyecto

| Archivo | Función |
|---|---|
| `install-remote.ps1` / `install-remote.sh` | Instaladores de un comando: descargan el repo y ejecutan el instalador local. |
| `install.ps1` / `install.sh` | Instalan o retiran comandos y copian la app a la ubicación estable. |
| `claude-qwen.ps1` / `claude-qwen.sh` | Lanzador, alta/baja de clave, estado y smoke test (Windows / Linux). |
| `test-qwen.ps1` / `test-qwen.py` | Pruebas de extremo a extremo (las ejecuta `claude-qwen-test`). |
| `qwen-settings.json` | Routing del proveedor y variables de aislamiento (sin secretos; compartido por ambos SO). |
| `qwen-agents.json` | Definición JSON de los cinco subagentes (compartido). |
| `agents/*.md` | Definiciones Markdown de los subagentes (compartidas). |
| `.gitattributes` | Fuerza LF en los scripts de Linux aunque el repo se clone en Windows. |
| `VERIFICATION.md` | Auditoría histórica de la instalación original en Windows (19-oct-2026). |

**Nunca** subas a este repositorio una API key ni el archivo de credenciales oficial de Claude.

> **Nota para quien administre el repo:** los instaladores apuntan a `https://github.com/Limao0521/claude-qwen-enterprise` (rama `main`). Si el repo cambia de dueño, nombre o rama, actualiza este README, `install-remote.ps1` (`$RepoOwner`) e `install-remote.sh` (`REPO_OWNER`). Tras editar archivos del lanzador, settings o agentes, vuelve a ejecutar el instalador local en cada máquina para que la copia instalada recoja el cambio.

## Fuentes

- [Variables de entorno de Claude Code](https://code.claude.com/docs/en/env-vars)
- [Autenticación y precedencia de credenciales](https://code.claude.com/docs/en/authentication)
- [Subagentes personalizados](https://code.claude.com/docs/en/sub-agents)
- [Base URLs de Alibaba Model Studio](https://help.aliyun.com/en/model-studio/base-url)
- [Mensajes Anthropic compatibles y encabezados de autenticación](https://help.aliyun.com/en/model-studio/anthropic-api-messages)
