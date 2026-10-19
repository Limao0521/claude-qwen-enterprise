# Verificación — 19 de octubre de 2026

| Comprobación | Estado | Evidencia o límite |
|---|---|---|
| Claude Code instalado | PASS | `claude --version`: 2.1.296. |
| Perfil oficial autenticado | PASS | `claude auth status --json`: `loggedIn=true`, `authMethod=oauth_token`. No se hizo una llamada de inferencia oficial. |
| Ajustes y credencial oficiales | PASS | `settings.json` y `.credentials.json` conservaron sus SHA-256 iniciales. |
| Archivo global `.claude.json` | OBSERVADO | Su SHA-256 cambió durante la auditoría mientras existía una sesión Claude activa. No se editó manualmente ni se restauró para evitar sobrescribir estado concurrente. |
| Comandos Qwen instalados | PASS | `claude-qwen-status` encontró CLI, endpoint y cinco agentes. |
| Fallo seguro sin clave | PASS | `claude-qwen-test` terminó con código 2 antes de abrir Claude Code; no apareció un archivo de credenciales Qwen. |
| Credencial Qwen aislada | PASS local | Prueba de ida y vuelta con una credencial ficticia temporal en Windows Credential Manager; se borró después. La clave real todavía no está inscrita. |
| OAuth excluido en modo seguro | PASS local | `claude --bare auth status --json` bajo `CLAUDE_CONFIG_DIR` Qwen devolvió `loggedIn=false`, `authMethod=none`; no quedó `.credentials.json` en ese directorio. |
| Definiciones de agentes | PASS sintaxis | `claude plugin validate` pasó para los cinco archivos Markdown; JSON también se analizó. |
| JSON de agentes en Windows PowerShell | PASS local | Se comprobó que la conversión y escape para argumentos nativos conserva cinco definiciones al recibirlas un proceso Node. |
| Análisis de PowerShell y JSON | PASS | Cero errores de parser en tres scripts; ambos JSON se analizaron. |
| CLI oficial sin cambio de comando | PASS local | `Get-Command claude` sigue apuntando a `%USERPROFILE%\.local\bin\claude.exe`. |
| Clave empresarial real | UNVERIFIED | Requiere `claude-qwen-auth` interactivo; no se solicitó ni expuso en chat. |
| Endpoint Anthropic, texto, herramientas y multivuelta | UNVERIFIED | Requiere la clave real y `claude-qwen-test`. Los éxitos previos OpenAI no prueban esta interfaz. |
| Archivo, edición y terminal bajo Qwen | UNVERIFIED | Requiere la clave real y `claude-qwen-test`. |
| Un subagente Qwen y dos invocaciones | UNVERIFIED | Requiere la clave real y `claude-qwen-test`. |
| Solapamiento paralelo real | UNVERIFIED | Dos invocaciones no prueban concurrencia; revisar trazas o métricas del proveedor. |
| Agent Teams | UNVERIFIED | No habilitado; capacidad experimental separada de subagentes estándar. |

El requisito de operación completa queda pendiente hasta inscribir la clave y ejecutar las pruebas de red. `claude-qwen` se niega a iniciar sin clave empresarial; no cambia al perfil personal.

**Copias:** no se reemplazó ningún archivo original ni había comandos Qwen previos en `%USERPROFILE%\.local\bin`, por lo que no quedó una copia con fecha. Un archivo OAuth de MCP generado en la configuración Qwen durante una prueba exploratoria se retiró tras verificar una copia temporal; esa copia también se retiró. La configuración y credencial oficiales no se copiaron al proyecto.
