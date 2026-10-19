# Claude Qwen Enterprise configuration

`claude-qwen.ps1` owns launcher, credential, status, and smoke test commands. `qwen-settings.json` pins nonsecret provider routing. `agents/` contains Qwen-only subagents. `install.ps1` installs command shims into the existing user PATH directory.

Run `powershell -NoProfile -File .\install.ps1` from this directory. Run `claude-qwen-status` for a safe local check and `claude-qwen-test` after enrolling a key. Never copy the official Claude credential file or an API key into this repository.
