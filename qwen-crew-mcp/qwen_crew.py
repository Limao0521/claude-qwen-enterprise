#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""qwen-crew: servidor MCP que expone subagentes Qwen3.8-Max (CLI claude-qwen)
a un orquestador (Claude Desktop / Opus 5.5).

Seguridad: la API key NUNCA pasa por este proceso. El wrapper claude-qwen la
lee por sí mismo desde ~/.config/claude-qwen-enterprise/.env. Toda salida se
redacta (sk-* -> <redacted>) antes de devolverse al orquestador.

Env:
  QWEN_CREW_MAX_PARALLEL  semáforo de tareas concurrentes (default 8)
"""

import json
import os
import re
import signal
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------- constantes

QWEN_BIN = {
    # Rutas absolutas: el entorno de Claude Desktop es mínimo (sin PATH de usuario).
    # Por defecto usa ~/.local/bin del usuario actual (lo que crea install.sh de
    # claude-qwen-enterprise). Override por env si el instalador usó otra ruta:
    #   QWEN_CREW_BIN_MAX / QWEN_CREW_BIN_FAST
    "max": os.environ.get(
        "QWEN_CREW_BIN_MAX",
        str(Path.home() / ".local" / "bin" / "claude-qwen")),          # qwen3.8-max
    "fast": os.environ.get(
        "QWEN_CREW_BIN_FAST",
        str(Path.home() / ".local" / "bin" / "claude-qwen-fast")),     # qwen3.8-flash
}
ALLOWED_TOOLS = "Read,Write,Edit,Bash,Glob,Grep,Agent"
TASKS_DIR = Path.home() / ".local" / "share" / "qwen-crew" / "tasks"
RESULT_LIMIT = 30_000          # chars máximos devueltos al orquestador
ACTIVITY_LIMIT = 200           # chars para "última actividad"
SECRET_RE = re.compile(r"sk-\S+")

MAX_PARALLEL = max(1, int(os.environ.get("QWEN_CREW_MAX_PARALLEL", "8")))
_SEM = threading.Semaphore(MAX_PARALLEL)
NOTIFY = os.environ.get("QWEN_CREW_NOTIFY", "1") != "0"  # avisos de escritorio al terminar


def _notify_desktop(task: "Task"):
    """Aviso al usuario (no al orquestador): notify-send es best-effort."""
    if not NOTIFY:
        return
    try:
        subprocess.Popen(
            ["notify-send", "-a", "qwen-crew",
             f"Subagente Qwen: {task.status}",
             f"Tarea {task.id} en {task.cwd}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


def redact(text: str) -> str:
    """Elimina cualquier secreto con forma sk-* del texto."""
    return SECRET_RE.sub("<redacted>", text or "")


# ---------------------------------------------------------------- modelo de tarea

@dataclass
class Task:
    id: str
    prompt: str
    cwd: str
    model: str
    max_turns: int
    timeout_s: int
    dir: Path
    status: str = "queued"   # queued | running | done | failed | cancelled | timeout
    created_at: float = field(default_factory=time.time)
    started_at: float = 0.0
    ended_at: float = 0.0
    exit_code: int = None
    turns: int = 0
    tools_used: set = field(default_factory=set)
    result: str = ""
    error: str = ""
    last_activity: str = ""
    proc: subprocess.Popen = None
    _kill_flag: str = ""     # "" | "timeout" | "cancelled"
    lock: threading.RLock = field(default_factory=threading.RLock)  # reentrante:
    # summary()/persist_meta() pueden llamarse con la lock ya tomada por el thread

    # -- serialización -------------------------------------------------------

    def summary(self) -> dict:
        with self.lock:
            elapsed = (self.ended_at or time.time()) - (self.started_at or self.created_at)
            return {
                "task_id": self.id,
                "status": self.status,
                "model": self.model,
                "cwd": self.cwd,
                "turns": self.turns,
                "tools_used": sorted(self.tools_used),
                "elapsed_s": round(elapsed, 1),
                "last_activity": self.last_activity,
                "progress_log": _read_progress(self),  # bitácora escrita por el subagente
                "error": self.error,
                "task_dir": str(self.dir),
            }

    def persist_meta(self):
        meta = self.summary()
        meta.update({
            "prompt_preview": redact(self.prompt[:500]),
            "exit_code": self.exit_code,
            "created_at": self.created_at,
            "started_at": self.started_at,
            "ended_at": self.ended_at,
        })
        try:
            (self.dir / "meta.json").write_text(
                json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass


TASKS: dict = {}
TASKS_LOCK = threading.Lock()


def _register(task: Task) -> Task:
    with TASKS_LOCK:
        TASKS[task.id] = task
    return task


def _get(task_id: str):
    with TASKS_LOCK:
        return TASKS.get(task_id)


# ---------------------------------------------------------------- ejecución

def _reporting_protocol(task: Task) -> str:
    """Instrucciones de reporte inyectadas al final de cada prompt: el subagente
    rinde bitácora en vivo (progress.log, leído por qwen_task_status/wait) y su
    mensaje final debe ser un reporte estructurado para el orquestador."""
    log = task.dir / "progress.log"
    return (
        "\n\n[PROTOCOLO DE REPORTE — obligatorio]\n"
        f"1. BITÁCORA: antes de cada paso importante (y al descubrir algo clave), "
        f"añade UNA línea corta con Bash: echo \"<paso> | <detalle>\" >> '{log}'  "
        f"(ejemplos de línea: 'explorando | leyendo src/foo.py', "
        f"'decisión | uso pytest en vez de unittest porque...', "
        f"'hallazgo | el bug está en la línea 42 de bar.py', 'tests | 12/14 pasan'). "
        f"No narices trivialidades; solo pasos, decisiones y descubrimientos.\n"
        "2. MENSAJE FINAL: tu última respuesta es el reporte al orquestador (que no "
        "ve tu sesión). Debe incluir, en texto plano y en este orden: "
        "QUÉ HICISTE (1-3 líneas) · DECISIONES CLAVE y por qué · DESCUBRIMIENTOS "
        "relevantes (archivos, bugs, patrones) · ARCHIVOS MODIFICADOS (rutas) · "
        "PENDIENTES/RIESGOS. Sé conciso pero completo."
    )


def _build_cmd(task: Task) -> list:
    """Comando del subagente. NUNCA pasar --settings/--setting-sources/
    --fallback-model/--model: el wrapper los gestiona (y los primeros los rechaza)."""
    return [
        QWEN_BIN[task.model],
        "--print",
        "--output-format", "stream-json",
        "--verbose",
        "--no-session-persistence",
        "--max-turns", str(task.max_turns),
        "--allowedTools", ALLOWED_TOOLS,
        "--permission-mode", "dontAsk",
        task.prompt + _reporting_protocol(task),
    ]


def _read_progress(task: Task, lines: int = 8) -> list:
    """Cola de la bitácora del subagente (redactada), para status/wait."""
    try:
        content = (task.dir / "progress.log").read_text(encoding="utf-8", errors="replace")
        tail = [ln.strip() for ln in content.splitlines() if ln.strip()][-lines:]
        return [redact(ln)[:ACTIVITY_LIMIT] for ln in tail]
    except OSError:
        return []


def _killpg(proc: subprocess.Popen, sig=signal.SIGTERM):
    try:
        os.killpg(os.getpgid(proc.pid), sig)
    except (ProcessLookupError, PermissionError, OSError):
        pass


def _handle_event(task: Task, event: dict, events_fh):
    """Procesa un evento stream-json; actualiza progreso y captura resultado."""
    events_fh.write(json.dumps(event, ensure_ascii=False) + "\n")
    etype = event.get("type")
    if etype == "system" and event.get("subtype") == "init":
        task.last_activity = f"init: modelo={event.get('model', '?')}"
    elif etype == "assistant":
        task.turns += 1
        message = event.get("message") or {}
        for block in message.get("content") or []:
            if isinstance(block, dict):
                if block.get("type") == "tool_use" and block.get("name"):
                    task.tools_used.add(str(block["name"]))
                    task.last_activity = f"tool: {block['name']}"[:ACTIVITY_LIMIT]
                elif block.get("type") == "text" and block.get("text"):
                    task.last_activity = redact(str(block["text"]).strip()[:ACTIVITY_LIMIT])
    elif etype == "result":
        result_text = str(event.get("result") or "")
        task.result = redact(result_text)
        if event.get("is_error"):
            task.error = redact(str(event.get("result") or "error sin detalle"))[:500]
        task.last_activity = "result recibido"


def _run_task(task: Task):
    """Worker completo: semáforo -> Popen -> lectura stream -> cierre.
    Corre en un thread (async) o en el thread de la tool (sync)."""
    task.dir.mkdir(parents=True, exist_ok=True)
    stderr_path = task.dir / "stderr.log"
    events_path = task.dir / "events.jsonl"

    _SEM.acquire()
    try:
        with task.lock:
            if task.status != "queued":       # cancelada antes de arrancar
                task.ended_at = task.ended_at or time.time()
                task.persist_meta()
                _notify_desktop(task)
                return
            task.status = "running"
            task.started_at = time.time()
        try:
            cmd = _build_cmd(task)
            with open(events_path, "w", encoding="utf-8") as events_fh, \
                 open(stderr_path, "wb") as stderr_fh:
                proc = subprocess.Popen(
                    cmd,
                    cwd=task.cwd,
                    stdin=subprocess.DEVNULL,   # CRÍTICO: no heredar el stdin MCP,
                    # o el CLI competiría con el servidor por los requests JSON-RPC
                    stdout=subprocess.PIPE,
                    stderr=stderr_fh,
                    text=True,
                    start_new_session=True,   # process group propio -> killpg
                )
                with task.lock:
                    task.proc = proc

                # Timer de timeout: mata el grupo de procesos al expirar
                def _on_timeout():
                    with task.lock:
                        if task.status == "running":
                            task._kill_flag = "timeout"
                    _killpg(proc)

                timer = threading.Timer(task.timeout_s, _on_timeout)
                timer.daemon = True
                timer.start()
                try:
                    for line in proc.stdout:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            event = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(event, dict):
                            with task.lock:
                                _handle_event(task, event, events_fh)
                    proc.wait()
                finally:
                    timer.cancel()

            with task.lock:
                task.exit_code = proc.returncode
                task.ended_at = time.time()
                if task._kill_flag == "timeout":
                    task.status = "timeout"
                    task.error = f"Timeout tras {task.timeout_s}s; procesos terminados."
                elif task._kill_flag == "cancelled":
                    task.status = "cancelled"
                elif proc.returncode == 0 and task.result:
                    task.status = "failed" if task.error else "done"
                elif proc.returncode == 0:
                    task.status = "done"      # sin evento result pero exitoso
                else:
                    task.status = "failed"
                    if not task.error:
                        try:
                            tail = stderr_path.read_text(encoding="utf-8", errors="replace")
                            task.error = redact(tail[-800:]) or f"exit={proc.returncode}"
                        except OSError:
                            task.error = f"exit={proc.returncode}"
            task.persist_meta()
        except OSError as exc:
            with task.lock:
                task.status = "failed"
                task.error = redact(f"No se pudo lanzar el CLI: {exc}")
                task.ended_at = time.time()
            task.persist_meta()
    finally:
        _SEM.release()

    # resultado completo a disco + aviso de escritorio al usuario
    try:
        (task.dir / "result.txt").write_text(task.result, encoding="utf-8")
    except OSError:
        pass
    _notify_desktop(task)


def _start_worker(task: Task):
    thread = threading.Thread(target=_run_task, args=(task,), daemon=True,
                              name=f"qwen-task-{task.id[:8]}")
    thread.start()


def _validate(prompt: str, cwd: str, model: str, max_turns: int, timeout_s: int):
    if not prompt or not prompt.strip():
        return "El prompt no puede estar vacío."
    if not os.path.isdir(cwd):
        return f"cwd no existe o no es un directorio: {cwd}"
    if model not in QWEN_BIN:
        return f"model debe ser 'max' o 'fast' (recibido: {model!r})"
    if not 1 <= int(max_turns) <= 200:
        return "max_turns debe estar entre 1 y 200."
    if not 10 <= int(timeout_s) <= 3600:
        return "timeout_s debe estar entre 10 y 3600."
    for name in ("max", "fast"):
        if not os.access(QWEN_BIN[name], os.X_OK):
            return f"CLI no encontrado o sin permiso de ejecución: {QWEN_BIN[name]}"
    return None


def _new_task(prompt, cwd, model, max_turns, timeout_s) -> Task:
    task_id = uuid.uuid4().hex[:12]
    return _register(Task(
        id=task_id, prompt=prompt, cwd=os.path.abspath(cwd), model=model,
        max_turns=int(max_turns), timeout_s=int(timeout_s),
        dir=TASKS_DIR / task_id,
    ))


def _result_payload(task: Task) -> dict:
    with task.lock:
        result = task.result
        truncated = len(result) > RESULT_LIMIT
        payload = task.summary()
    if truncated:
        result = result[:RESULT_LIMIT] + (
            f"\n\n[... truncado a {RESULT_LIMIT} chars; resultado completo en "
            f"{task.dir / 'result.txt'}]")
    payload["result"] = result
    return payload


# ---------------------------------------------------------------- tools MCP

mcp = FastMCP(
    "qwen-crew",
    instructions=(
        "Subagentes Qwen3.8-Max para delegar trabajo de código. Usa qwen_task para "
        "tareas cortas (<2 min). Para tareas largas o en paralelo: lanza con "
        "qwen_task_start y luego llama a qwen_task_wait con los task_ids — esa tool "
        "bloquea hasta que todas terminan y devuelve los resultados de una vez "
        "(no hagas polling manual con qwen_task_status). Cada subagente trabaja de "
        "forma autónoma en el cwd indicado (puede leer, escribir y ejecutar); no ve "
        "tu conversación, así que dale prompts autocontenidos con criterio de éxito."
    ),
)


@mcp.tool()
def qwen_task(prompt: str, cwd: str, model: str = "max",
              max_turns: int = 30, timeout_s: int = 900) -> dict:
    """Ejecuta UNA tarea de código con un subagente Qwen3.8-Max y espera el resultado.

    El subagente es autónomo: puede leer, escribir, editar y ejecutar comandos en
    `cwd`. Úsalo para implementación, tests, refactorización o exploración profunda
    de un proyecto. Para tareas que puedan superar ~2 minutos, o para lanzar varias
    en paralelo, prefiere qwen_task_start (asíncrona).

    Args:
        prompt: Instrucción completa y autocontenida para el subagente (no ve esta
            conversación). Incluye contexto, archivos relevantes y criterio de éxito.
        cwd: Directorio de trabajo absoluto (el proyecto donde operar).
        model: "max" (qwen3.8-max, tareas difíciles) o "fast" (qwen3.8-flash, tareas simples).
        max_turns: Límite de turnos agénticos (1-200, default 30).
        timeout_s: Timeout en segundos (10-3600, default 900).

    Returns: dict con status, result (texto final del subagente), turns, tools_used,
        elapsed_s y task_dir (logs completos).
    """
    error = _validate(prompt, cwd, model, max_turns, timeout_s)
    if error:
        return {"status": "failed", "error": error}
    task = _new_task(prompt, cwd, model, max_turns, timeout_s)
    _run_task(task)   # síncrono, en el thread que FastMCP asigna a esta tool
    return _result_payload(task)


@mcp.tool()
def qwen_task_start(prompt: str, cwd: str, model: str = "max",
                    max_turns: int = 30, timeout_s: int = 900) -> dict:
    """Lanza un subagente Qwen3.8-Max en SEGUNDO PLANO y devuelve su task_id al instante.

    Úsalo para: (a) tareas largas (>2 min), (b) lanzar varias tareas en paralelo
    (llama a esta tool N veces seguidas y luego consulta con qwen_task_status /
    qwen_task_result). El subagente trabaja autónomo en `cwd`.

    Args: mismas que qwen_task (prompt autocontenido, cwd absoluto, model "max"|"fast",
        max_turns 1-200, timeout_s 10-3600).

    Returns: dict con task_id y status inicial ("queued" o "running").
    """
    error = _validate(prompt, cwd, model, max_turns, timeout_s)
    if error:
        return {"status": "failed", "error": error}
    task = _new_task(prompt, cwd, model, max_turns, timeout_s)
    _start_worker(task)
    return {"task_id": task.id, "status": task.status,
            "hint": "Consulta el progreso con qwen_task_status y el resultado con qwen_task_result."}


@mcp.tool()
def qwen_task_status(task_id: str) -> dict:
    """Consulta el estado de un subagente Qwen lanzado con qwen_task_start.

    Returns: dict con status (queued|running|done|failed|cancelled|timeout), turno
        actual, tools usadas, elapsed_s, última actividad observada y `progress_log`:
        la bitácora que el propio subagente escribe mientras trabaja (pasos,
        decisiones y descubrimientos clave, ~8 últimas líneas).
    """
    task = _get(task_id)
    if task is None:
        return {"status": "failed", "error": f"task_id desconocido: {task_id}"}
    return task.summary()


@mcp.tool()
def qwen_task_result(task_id: str) -> dict:
    """Obtiene el resultado final de un subagente Qwen. Si aún no terminó, devuelve
    el estado actual y un hint para esperar; vuelve a llamar más tarde.

    Returns: dict con status, result (texto final redactado y truncado si es enorme;
        el completo está en task_dir/result.txt), error si falló, y stats.
    """
    task = _get(task_id)
    if task is None:
        return {"status": "failed", "error": f"task_id desconocido: {task_id}"}
    payload = _result_payload(task)
    if task.status in ("queued", "running"):
        payload["hint"] = "La tarea sigue en curso; espera y vuelve a consultar."
    return payload


@mcp.tool()
def qwen_task_wait(task_ids: list = None, timeout_s: int = 600) -> dict:
    """ESPERA (bloquea) hasta que las tareas indicadas terminen y devuelve todos
    sus resultados de una vez. Esta es la forma eficiente de "ser notificado":
    tras lanzar N tareas con qwen_task_start, llama a qwen_task_wait con sus
    task_ids y tu turno se reanuda cuando todas hayan terminado.

    Args:
        task_ids: Lista de task_ids a esperar. Si se omite, espera TODAS las
            tareas activas de la sesión.
        timeout_s: Espera máxima en segundos (10-3600, default 600). Si expira,
            devuelve el estado parcial y puedes volver a llamar para seguir esperando.

    Returns: dict con all_done (bool), tasks (estado+resultado de cada una) y,
        si no terminaron, las que siguen activas.
    """
    ids = list(task_ids) if task_ids else None
    with TASKS_LOCK:
        if ids:
            unknown = [i for i in ids if i not in TASKS]
            tasks = [TASKS[i] for i in ids if i in TASKS]
        else:
            unknown, tasks = [], list(TASKS.values())
    if not tasks:
        return {"all_done": True, "tasks": [],
                "error": ("task_ids desconocidos: %s" % unknown) if unknown
                         else "No hay tareas en esta sesión."}

    timeout_s = min(max(10, int(timeout_s)), 3600)
    deadline = time.time() + timeout_s
    terminal = ("done", "failed", "cancelled", "timeout")
    while time.time() < deadline:
        with TASKS_LOCK:
            active = [t for t in tasks if t.status not in terminal]
        if not active:
            break
        time.sleep(1.5)
    else:
        active = [t for t in tasks if t.status not in terminal]

    payload = {
        "all_done": not active,
        "tasks": [_result_payload(t) for t in tasks],
    }
    if unknown:
        payload["unknown_task_ids"] = unknown
    if active:
        payload["still_running"] = [t.id for t in active]
        payload["hint"] = ("Timeout de espera alcanzado; vuelve a llamar a "
                           "qwen_task_wait para seguir esperando.")
    return payload


@mcp.tool()
def qwen_task_cancel(task_id: str) -> dict:
    """Cancela un subagente Qwen en curso (termina su grupo de procesos)."""
    task = _get(task_id)
    if task is None:
        return {"status": "failed", "error": f"task_id desconocido: {task_id}"}
    with task.lock:
        if task.status in ("done", "failed", "cancelled", "timeout"):
            return {"status": task.status, "note": "La tarea ya había terminado."}
        task._kill_flag = "cancelled"
        if task.status == "queued" and task.proc is None:
            # aún no arrancó: el worker la descartará al tomarla
            task.status = "cancelled"
            task.ended_at = time.time()
            task.persist_meta()
            return {"status": "cancelled", "task_id": task_id}
        proc = task.proc
    if proc is not None:
        _killpg(proc)

        def _force():
            time.sleep(5)
            with task.lock:
                still_running = task.status in ("queued", "running")
            if still_running:
                _killpg(proc, signal.SIGKILL)

        threading.Thread(target=_force, daemon=True).start()
    return {"status": "cancelling", "task_id": task_id}


@mcp.tool()
def qwen_task_list() -> dict:
    """Lista todas las tareas Qwen de esta sesión del servidor (para no perder el
    hilo de los task_ids). Incluye estado, modelo, cwd y duración de cada una."""
    with TASKS_LOCK:
        tasks = [t.summary() for t in TASKS.values()]
    return {"count": len(tasks), "max_parallel": MAX_PARALLEL,
            "tasks": sorted(tasks, key=lambda s: s["task_id"])}


# ---------------------------------------------------------------- arranque

def _mark_orphans():
    """Al arrancar, marca como orphan las tareas que quedaron 'running' de una
    sesión anterior (el servidor no sobrevive tareas; quedan para post-mortem)."""
    if not TASKS_DIR.is_dir():
        return
    for meta_path in TASKS_DIR.glob("*/meta.json"):
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            if meta.get("status") in ("running", "queued"):
                meta["status"] = "orphaned"
                meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False),
                                     encoding="utf-8")
        except (OSError, ValueError):
            continue


if __name__ == "__main__":
    import logging
    logging.getLogger("mcp").setLevel(logging.WARNING)  # stderr limpio para Desktop
    TASKS_DIR.mkdir(parents=True, exist_ok=True)
    _mark_orphans()
    mcp.run()   # stdio
