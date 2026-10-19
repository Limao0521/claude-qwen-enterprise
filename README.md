# Claude Code + Qwen Enterprise (Windows)

## Uso

En una ventana normal de PowerShell:

```powershell
claude-qwen-status
claude-qwen-auth                 # pegar la clave en el aviso oculto
claude-qwen-test                 # pruebas con consumo de API
claude-qwen                      # qwen3.8-max
claude-qwen-fast                 # qwen3.8-flash
claude-qwen --print "Hola"      # los argumentos se envían a Claude Code
claude-qwen-auth --delete        # borrar la clave; ejecutar sin --delete para rotarla
```

`claude` sigue siendo el ejecutable oficial sin alias ni modificación. Los cinco comandos Qwen son archivos `.cmd` en `%USERPROFILE%\.local\bin`, una ruta que ya estaba en `PATH`. Se instalaron mediante `install.ps1` desde este proyecto. La configuración temporal de Claude Qwen vive en `%LOCALAPPDATA%\ClaudeQwenEnterprise\claude-config`; la clave vive en **Windows Credential Manager**, bajo `Codex/ClaudeQwenEnterprise/AlibabaSingapore`.

## Separación y modelos

El lanzador crea un proceso PowerShell separado, exige una clave Qwen almacenada, borra variables Anthropic heredadas, fija el endpoint empresarial de Singapur y pasa la clave solo al proceso hijo como `ANTHROPIC_API_KEY`. Alibaba acepta `x-api-key` para su API Anthropic. Claude Code corre con `--bare`, `--strict-mcp-config`, `--setting-sources user` y `CLAUDE_CONFIG_DIR` propio. `--bare` excluye el inicio de sesión OAuth y la lectura del almacén de credenciales oficial. El proceso padre no recibe la clave. `qwen-settings.json` fija la URL y las asignaciones, y el lanzador rechaza `--settings`, `--setting-sources` y `--fallback-model` enviados por el usuario.

| Papel | Modelo inicial |
|---|---|
| Principal y planificación | `qwen3.8-max` |
| Alias Opus; revisión crítica | `qwen3.8-max` |
| Alias Sonnet; implementación; pruebas; subagente general | `qwen3.7-plus` |
| Alias Haiku; exploración; lanzamiento rápido | `qwen3.8-flash` |

Estas asignaciones son hipótesis de trabajo. `qwen3.8-plus` y `qwen3-coder-plus` no se usan porque el historial proporcionado indica HTTP 404. Los cinco agentes reutilizables están en `agents/`; el lanzador pasa `qwen-agents.json` de forma explícita para que también estén disponibles en modo `--bare`. No se activó Agent Teams experimental. Una solicitud de dos subagentes es distinta de probar que sus llamadas se solapan en tiempo.

## Funciones y límites

El modo `--bare` conserva las herramientas integradas de archivo y terminal y admite agentes explícitos, según la ayuda de Claude Code 2.1.296. Desactiva descubrimiento automático de `CLAUDE.md`, hooks, sincronización de plugins, LSP, memoria automática y ciertas tareas de fondo. `--strict-mcp-config` evita cargar servidores MCP existentes. Las skills pueden llamarse de forma explícita, pero no se ha probado su funcionamiento con Qwen. Los ajustes locales y compartidos de un repositorio se excluyen para impedir que cambien la clave o el proveedor. Si un proyecto necesita sus instrucciones, incorpórelas explícitamente al prompt o a un archivo de prompt de sesión; no se copian automáticamente secretos ni configuraciones MCP del perfil oficial.

La entrega de una clave mediante variable de entorno tiene límites: el proceso Claude Code y sus subprocesos pueden leerla; procesos con permisos suficientes del mismo usuario o un administrador podrían inspeccionar su memoria o entorno. No queda en el PowerShell padre ni en archivos del proyecto. Evite ejecutar comandos no confiables dentro de una sesión Qwen.

`claude-qwen-status` solo comprueba archivos y Credential Manager; no prueba el servicio. `claude-qwen-test` usa una carpeta temporal fuera de repositorios y hace llamadas a `/v1/messages`, una prueba de herramientas y una continuación multivuelta, más tres sesiones CLI para archivo/terminal, un agente y dos agentes. La prueba puede generar cargos. El script resume resultados sin imprimir la clave y elimina su carpeta temporal al terminar. El solapamiento real de dos agentes requiere telemetría o inspección manual; se informa como **no verificado** si no hay evidencia de concurrencia.

## Diagnóstico

1. Si falta la clave, ejecute `claude-qwen-auth` en una terminal interactiva. No la pegue en el chat ni en un argumento de comando.
2. Si hay HTTP 401, compruebe que la clave sea del mismo workspace y región que el host configurado. Rote con `claude-qwen-auth`.
3. Si hay 404 en `/v1/models`, ese catálogo no existe en la interfaz Anthropic de Alibaba; use los IDs explícitos. Un 404 en `/v1/messages` sí indica un problema del endpoint.
4. Si Claude Code advierte que un modelo Qwen es desconocido, compruebe que la solicitud siga usando la URL empresarial. La advertencia del catálogo local no equivale a un fallo del endpoint.
5. Si falla un agente, revise `qwen-agents.json`, la salida de `claude-qwen-test` y el límite de solicitudes del workspace. Comience con un máximo de dos agentes.

## Reversión

1. Ejecute `claude-qwen-auth --delete` para borrar la clave empresarial del Administrador de credenciales.
2. Ejecute `powershell.exe -NoProfile -File .\install.ps1 -Remove` desde este proyecto. El instalador verifica que cada `.cmd` sea suyo y crea copia con fecha antes de quitarlo.
3. Si desea eliminar el historial Qwen, inspeccione primero `%LOCALAPPDATA%\ClaudeQwenEnterprise` y elimínelo manualmente. No toque `%USERPROFILE%\.claude`, `%USERPROFILE%\.claude.json` ni `claude.exe`.

## Fuentes

- [Variables de entorno de Claude Code](https://code.claude.com/docs/en/env-vars)
- [Autenticación y precedencia de credenciales](https://code.claude.com/docs/en/authentication)
- [Subagentes personalizados](https://code.claude.com/docs/en/sub-agents)
- [Base URLs de Alibaba Model Studio](https://help.aliyun.com/en/model-studio/base-url)
- [Mensajes Anthropic compatibles y encabezados de autenticación](https://help.aliyun.com/en/model-studio/anthropic-api-messages)
