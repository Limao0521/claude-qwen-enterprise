# qwen-crew-mcp — Subagentes Qwen para Claude Desktop

Servidor MCP que expone **subagentes Qwen3.8-Max** (vía el CLI `claude-qwen` de
este repositorio) a un orquestador en Claude Desktop (p. ej. Opus 5.5). Cada
tarea lanza una sesión CLI autónoma (`--print`, stream-json,
`--permission-mode dontAsk`) en el `cwd` indicado.

> **Plataforma**: solo Linux (Ubuntu 20.04+). Usa `os.killpg`,
> `start_new_session` y `notify-send`, que no existen en Windows. En Windows
> `claude-qwen` sí funciona como CLI, pero este servidor MCP aún no está portado.

## Seguridad

- La API key **nunca pasa por este servidor**: el wrapper `claude-qwen` la lee
  por sí mismo desde el keyring del sistema o desde
  `~/.config/claude-qwen-enterprise/.env` (permisos 600).
- Toda salida se redacta (`sk-*` → `<redacted>`) antes de volver al orquestador.

## Tools

| Tool | Uso |
|---|---|
| `qwen_task` | Síncrona: ejecuta y devuelve resultado (tareas < ~2 min) |
| `qwen_task_start` | Asíncrona: devuelve `task_id` al instante (tareas largas / paralelo) |
| `qwen_task_wait` | Bloquea hasta que las tareas indicadas terminen y devuelve todos los resultados (la forma eficiente de esperar tras un fan-out) |
| `qwen_task_status` | Progreso: estado, turno, tools usadas, última actividad, `progress_log` |
| `qwen_task_result` | Resultado final (o hint si sigue corriendo) |
| `qwen_task_cancel` | Mata el grupo de procesos de la tarea |
| `qwen_task_list` | Resumen de todas las tareas de la sesión |

Modelos: `"max"` → `claude-qwen` (qwen3.8-max) · `"fast"` → `claude-qwen-fast`
(qwen3.8-flash).

Cada subagente lleva un **protocolo de reporte** inyectado: escribe su bitácora
(pasos, decisiones, descubrimientos) en `<task_dir>/progress.log`, expuesta por
`qwen_task_status`/`qwen_task_wait` como `progress_log`, y su mensaje final es un
reporte estructurado (qué hizo · decisiones · descubrimientos · archivos ·
pendientes).

## Variables de entorno

| Variable | Default | Función |
|---|---|---|
| `QWEN_CREW_MAX_PARALLEL` | `8` | Semáforo de tareas concurrentes |
| `QWEN_CREW_NOTIFY` | `1` | Notificaciones de escritorio (`notify-send`) al terminar cada subagente; `"0"` silencia |
| `QWEN_CREW_BIN_MAX` | `~/.local/bin/claude-qwen` | Ruta al wrapper (override si tu instalación quedó en otro lado) |
| `QWEN_CREW_BIN_FAST` | `~/.local/bin/claude-qwen-fast` | Ídem para el wrapper fast |

Logs por tarea: `~/.local/share/qwen-crew/tasks/<task_id>/` (`events.jsonl`,
`stderr.log`, `result.txt`, `meta.json`, `progress.log`).

---

# Acople en la máquina de cada usuario

Sigue estos pasos una sola vez. **No requieren root** y no tocan tu Claude
oficial.

## Paso 0 — Prerrequisitos

1. **Linux** (Ubuntu 20.04+), con `python3` y `uv` (o `python3 -m venv`).
2. **Claude Code** instalado (`claude --version` responde).
3. **claude-qwen-enterprise** instalado y autenticado. Si aún no lo tienes,
   desde la rama `main` de este repo:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/Limao0521/claude-qwen-enterprise/main/install-remote.sh | bash
   claude-qwen-auth          # pega TU clave en el aviso oculto
   claude-qwen-status        # debe mostrar Credential: secret-tool o .env
   ```

   Verifica que los wrappers existen (esta ruta es la que el MCP usa por
   defecto):

   ```bash
   ls -l ~/.local/bin/claude-qwen ~/.local/bin/claude-qwen-fast
   ```

   > Si tu clave está solo en el keyring (`secret-tool`), normalmente funciona
   > igual porque Claude Desktop corre dentro de tu sesión de escritorio
   > (D-Bus disponible). Si en tu entorno el keyring no es accesible desde
   > Desktop, guarda la clave también en `.env`: `claude-qwen-auth --env`.

## Paso 1 — Clonar y crear el venv

```bash
git clone https://github.com/Limao0521/claude-qwen-enterprise.git
cd claude-qwen-enterprise
git checkout MCP

cd qwen-crew-mcp
uv venv .venv
uv pip install --python .venv/bin/python "mcp[cli]<2"
```

(Sin `uv`: `python3 -m venv .venv && .venv/bin/pip install "mcp[cli]<2"`.)

> Nota: requiere `mcp<2` (en mcp 2.x `FastMCP` se renombró a `MCPServer`).

El script **no tiene rutas hardcodeadas**: resuelve los wrappers contra tu
propio `~/.local/bin`. Solo necesitas overrides si tu instalación quedó en
otra ruta (ver variables de entorno arriba).

## Paso 2 — Registrar el MCP en Claude Desktop

Edita `~/.config/Claude/claude_desktop_config.json` (créealo si no existe) y
añade el bloque `mcpServers.qwen-crew` con **tus rutas absolutas** — Desktop no
expande `~` ni usa tu PATH, así que no valen rutas relativas:

```bash
# Sustituye TU_USUARIO por tu usuario real (o usa $HOME al pegar en terminal)
```

```json
{
  "mcpServers": {
    "qwen-crew": {
      "command": "/home/TU_USUARIO/claude-qwen-enterprise/qwen-crew-mcp/.venv/bin/python",
      "args": [
        "/home/TU_USUARIO/claude-qwen-enterprise/qwen-crew-mcp/qwen_crew.py"
      ],
      "env": {
        "QWEN_CREW_MAX_PARALLEL": "8"
      }
    }
  }
}
```

Si el archivo ya existe con otros servidores, añade `qwen-crew` dentro del
`mcpServers` existente sin borrar los demás.

## Paso 3 — Reiniciar Claude Desktop y verificar

1. Cierra Claude Desktop por completo y ábrelo de nuevo.
2. En el chat, el servidor debe aparecer con sus 7 tools (`qwen_task`, ...).
3. Prueba mínima: pídele al orquestador *"usa qwen_task con model fast para
   responder PONG en /tmp"*.

### Prueba rápida sin Desktop (recomendada antes de registrar)

```bash
cd qwen-crew-mcp
.venv/bin/python -c "
import sys; sys.path.insert(0,'.')
from qwen_crew import qwen_task
print(qwen_task('Reply with PONG only.','/tmp',model='fast',max_turns=1,timeout_s=120))"
```

Si esto devuelve `status: done`, el acople está completo.

## Solución de problemas

| Síntoma | Causa probable / arreglo |
|---|---|
| `CLI no encontrado o sin permiso de ejecución` | Faltan los wrappers: reinstala claude-qwen-enterprise (Paso 0) o ajusta `QWEN_CREW_BIN_MAX`/`_FAST` |
| `No hay clave empresarial registrada` | Ejecuta `claude-qwen-auth` (o `--env` si Desktop no ve el keyring) |
| El servidor no aparece en Desktop | Rutas del JSON mal escritas (deben ser absolutas y existir); revisa con `jq . ~/.config/Claude/claude_desktop_config.json` y reinicia Desktop |
| Tareas quedan en `orphaned` | El servidor se reinició con tareas corriendo; es esperado (quedan para post-mortem en `~/.local/share/qwen-crew/tasks/`) |
| `ModuleNotFoundError: mcp` | El `command` del JSON no apunta al python del venv; debe ser `.venv/bin/python` de esta carpeta |

## Documentación adicional

- `MODELOS_API.md` — catálogo completo del endpoint: IDs exactos de todos los
  modelos (Qwen, DeepSeek, GLM, Kimi), niveles de razonamiento por modelo,
  precios y política de privacidad/datos.
