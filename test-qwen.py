#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pruebas de extremo a extremo de claude-qwen en Linux (Ubuntu 20.04+) y macOS.

Solo usa la biblioteca estandar de python3. Lo ejecuta claude-qwen.sh en modo
test; recibe la clave por la variable de entorno ANTHROPIC_API_KEY. Hace
llamadas reales a la API y sesiones CLI: puede generar cargos. Al terminar
borra su carpeta temporal y no imprime la clave.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

RESULTS = []


def add_result(check, state, note):
    RESULTS.append((check, state, note))


def send_message(endpoint, api_key, messages, tools=None, tool_choice=None):
    body = {"model": "qwen3.8-flash", "max_tokens": 96, "messages": messages}
    if tools:
        body["tools"] = tools
    if tool_choice is not None:
        body["tool_choice"] = tool_choice
    request = urllib.request.Request(
        endpoint.rstrip("/") + "/v1/messages",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))


def error_note(exc):
    code = getattr(exc, "code", None)
    if code is not None:
        return "HTTP or protocol error: HTTP %s" % code
    return "HTTP or protocol error: %s" % type(exc).__name__


def walk_events(node, agent_ids, tool_names):
    if isinstance(node, dict):
        if node.get("type") == "tool_use" and node.get("name"):
            tool_names.add(str(node["name"]))
            if node["name"] == "Agent" and node.get("id"):
                agent_ids.add(str(node["id"]))
        for value in node.values():
            walk_events(value, agent_ids, tool_names)
    elif isinstance(node, list):
        for item in node:
            walk_events(item, agent_ids, tool_names)


def invoke_claude(ctx, prompt, turns):
    command = [
        ctx["claude"],
        "--strict-mcp-config",
        "--setting-sources", "user",
        "--settings", ctx["settings"],
        "--agents", ctx["agents"],
        "--model", "qwen3.8-flash",
        "--print",
        "--output-format", "stream-json",
        "--verbose",
        "--no-session-persistence",
        "--max-turns", str(turns),
        "--allowedTools", "Read,Write,Bash,Agent",
        "--permission-mode", "dontAsk",
        prompt,
    ]
    try:
        proc = subprocess.run(
            command, cwd=ctx["dir"], capture_output=True, text=True, timeout=900
        )
        exit_code = proc.returncode
        raw = (proc.stdout or "") + "\n" + (proc.stderr or "")
    except subprocess.TimeoutExpired as exc:
        exit_code = -1
        raw = exc.stdout if isinstance(exc.stdout, str) else ""
    agent_ids, tool_names = set(), set()
    agent_available = False
    final_result = ""
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if isinstance(event, dict):
            walk_events(event, agent_ids, tool_names)
            if event.get("type") == "system" and event.get("subtype") == "init":
                agent_available = "Agent" in (event.get("tools") or [])
            if event.get("type") == "result" and event.get("result"):
                final_result = str(event["result"])
    preview = re.sub(r"sk-[^\s\"]+", "<redacted>", final_result)
    if len(preview) > 320:
        preview = preview[:320]
    return {
        "exit": exit_code,
        "agent_calls": len(agent_ids),
        "agent_available": agent_available,
        "tool_names": ",".join(sorted(tool_names)),
        "preview": preview,
        "raw": raw,
    }


def print_results():
    width = max([len(check) for check, _, _ in RESULTS] + [5])
    print("Check".ljust(width) + "  State       Note")
    for check, state, note in RESULTS:
        print(check.ljust(width) + "  " + state.ljust(11) + " " + note)


def main():
    parser = argparse.ArgumentParser(description="Smoke test de claude-qwen (Linux/macOS)")
    parser.add_argument("--claude", required=True)
    parser.add_argument("--settings", required=True)
    parser.add_argument("--agents-file", required=True)
    parser.add_argument("--endpoint", required=True)
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        print("ANTHROPIC_API_KEY vacia; el lanzador debe aportar la clave.", file=sys.stderr)
        return 2
    with open(args.agents_file, "r", encoding="utf-8") as handle:
        agents_json = json.dumps(json.load(handle), separators=(",", ":"))

    test_dir = tempfile.mkdtemp(prefix="claude-qwen-smoke-")
    ctx = {
        "claude": args.claude,
        "settings": args.settings,
        "agents": agents_json,
        "dir": test_dir,
    }
    try:
        # 1) Autenticacion y texto plano contra /v1/messages
        try:
            reply = send_message(
                args.endpoint, api_key,
                [{"role": "user", "content": "Reply with PONG only."}],
            )
            texts = [
                block for block in reply.get("content", [])
                if block.get("type") == "text" and str(block.get("text", "")).strip()
            ]
            if texts:
                add_result("Anthropic Messages authentication and text", "PASS",
                           "Authenticated Messages response received.")
            else:
                types = ",".join(str(b.get("type")) for b in reply.get("content", []))
                add_result("Anthropic Messages authentication and text", "FAIL",
                           "No text content; content types=%s; stop_reason=%s; output_tokens=%s" % (
                               types, reply.get("stop_reason"),
                               (reply.get("usage") or {}).get("output_tokens")))
        except (urllib.error.URLError, OSError, ValueError) as exc:
            add_result("Anthropic Messages authentication and text", "FAIL", error_note(exc))
        if RESULTS[-1][1] == "FAIL":
            add_result("Remaining endpoint and Claude Code checks", "UNVERIFIED",
                       "Stopped after the initial connection failure.")
            print_results()
            return 1

        # 2) Solicitud de herramientas (tool use)
        tool = {
            "name": "echo_value",
            "description": "Echo an integer",
            "input_schema": {
                "type": "object",
                "properties": {"value": {"type": "integer"}},
                "required": ["value"],
            },
        }
        tool_call = None
        tool_reply = None
        try:
            tool_reply = send_message(
                args.endpoint, api_key,
                [{"role": "user", "content": "Call echo_value with value 7."}],
                tools=[tool], tool_choice={"type": "tool", "name": "echo_value"},
            )
            calls = [
                block for block in tool_reply.get("content", [])
                if block.get("type") == "tool_use" and block.get("name") == "echo_value"
            ]
            tool_call = calls[0] if calls else None
            if tool_call:
                add_result("Tool-use request", "PASS", "tool_use block returned.")
            else:
                add_result("Tool-use request", "FAIL", "No tool_use block returned.")
        except (urllib.error.URLError, OSError, ValueError) as exc:
            add_result("Tool-use request", "FAIL", error_note(exc))

        # 3) Continuacion multivuelta con tool_result
        if tool_call:
            try:
                follow = send_message(args.endpoint, api_key, [
                    {"role": "user", "content": "Call echo_value with value 7, then say done."},
                    {"role": "assistant", "content": tool_reply.get("content", [])},
                    {"role": "user", "content": [
                        {"type": "tool_result", "tool_use_id": tool_call.get("id"), "content": "7"},
                    ]},
                ])
                if any(b.get("type") == "text" for b in follow.get("content", [])):
                    add_result("Multi-turn tool result", "PASS", "Continuation returned text.")
                else:
                    add_result("Multi-turn tool result", "FAIL", "No continuation text.")
            except (urllib.error.URLError, OSError, ValueError) as exc:
                add_result("Multi-turn tool result", "FAIL", error_note(exc))
        else:
            add_result("Multi-turn tool result", "UNVERIFIED", "Tool-use request did not pass.")

        # 4-6) Sesiones CLI: archivo/terminal, un subagente, dos subagentes
        with open(os.path.join(test_dir, "input.txt"), "w", encoding="utf-8") as handle:
            handle.write("QWEN-SMOKE-731")

        harness = invoke_claude(
            ctx,
            "Use Read to inspect input.txt. Use Write to create output.txt containing exactly "
            "QWEN-SMOKE-731. Use Bash to run a harmless shell command that creates command.txt "
            "containing exactly COMMAND-OK. Then reply done.",
            7,
        )
        output_path = os.path.join(test_dir, "output.txt")
        command_path = os.path.join(test_dir, "command.txt")
        if (harness["exit"] == 0 and os.path.exists(output_path)
                and "QWEN-SMOKE-731" in open(output_path, encoding="utf-8").read()):
            add_result("Claude Code read and write tools", "PASS",
                       "Output file contains expected marker.")
        else:
            add_result("Claude Code read and write tools", "FAIL",
                       "Expected output file not created.")
        if (harness["exit"] == 0 and os.path.exists(command_path)
                and "COMMAND-OK" in open(command_path, encoding="utf-8").read()):
            add_result("Claude Code terminal tool", "PASS",
                       "Terminal command created expected marker.")
        else:
            add_result("Claude Code terminal tool", "FAIL",
                       "Expected command marker not created.")

        one = invoke_claude(
            ctx,
            "Invoke the qwen-explorer subagent to read input.txt and report its exact marker. "
            "Do not read the file yourself. Return the subagent result.",
            5,
        )
        if one["exit"] == 0 and one["agent_calls"] >= 1 and "QWEN-SMOKE-731" in one["raw"]:
            add_result("One Qwen subagent", "PASS", "Agent tool invocation was observed.")
        else:
            add_result("One Qwen subagent", "FAIL",
                       "No Agent tool invocation; exit=%s; available=%s; tools=%s; result=%s" % (
                           one["exit"], one["agent_available"], one["tool_names"], one["preview"]))

        two = invoke_claude(
            ctx,
            "Start exactly two independent qwen-explorer subagents concurrently. Agent one reads "
            "input.txt; agent two lists files in this directory. Wait for both and summarize. "
            "Do not spawn any other agents.",
            6,
        )
        if two["exit"] == 0 and two["agent_calls"] >= 2:
            add_result("Two subagent invocations", "PASS",
                       "Two Agent tool invocation events were observed.")
            add_result("Concurrent overlap", "UNVERIFIED",
                       "Event overlap requires manual inspection or provider telemetry.")
        else:
            add_result("Two subagent invocations", "FAIL",
                       "Fewer than two Agent invocation events; exit=%s; available=%s; calls=%s; tools=%s; result=%s" % (
                           two["exit"], two["agent_available"], two["agent_calls"],
                           two["tool_names"], two["preview"]))
            add_result("Concurrent overlap", "UNVERIFIED",
                       "Two successful invocations are required first.")
    finally:
        resolved = os.path.realpath(test_dir)
        tmp_root = os.path.realpath(tempfile.gettempdir())
        if (resolved.startswith(tmp_root + os.sep)
                and re.match(r"^claude-qwen-smoke-[a-z0-9_]+$", os.path.basename(resolved))
                and os.path.isdir(resolved)):
            shutil.rmtree(resolved, ignore_errors=True)

    print_results()
    if any(state == "FAIL" for _, state, _ in RESULTS):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
