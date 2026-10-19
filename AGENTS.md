# Claude Qwen Enterprise configuration

Cross-platform project: Windows 10/11 (PowerShell 5.1+) and Ubuntu 20.04+ (bash, python3 stdlib). Both platforms share `qwen-settings.json`, `qwen-agents.json`, and `agents/`.

- `claude-qwen.ps1` (Windows) and `claude-qwen.sh` (Linux) own launcher, credential, status, and smoke-test commands. Windows stores the key in Windows Credential Manager; Linux uses libsecret (`secret-tool`) when available and falls back to `~/.config/claude-qwen-enterprise/api-key` (0600).
- `test-qwen.ps1` (Windows) and `test-qwen.py` (Linux) are the end-to-end smoke tests run by `claude-qwen-test`. Keep their checks and result names in sync.
- `install.ps1` / `install.sh` copy the app to a stable per-user location (`%LOCALAPPDATA%\ClaudeQwenEnterprise\app` / `~/.local/share/claude-qwen-enterprise/app`) and install shims into `%USERPROFILE%\.local\bin` / `~/.local/bin` (creating it and adding it to PATH if needed).
- `install-remote.ps1` / `install-remote.sh` are the one-command entry points (`irm ... | iex` / `curl ... | bash`): they download this repository and run the local installer. Keep their owner/name/branch variables and the README one-liners in sync with the published repository URL; both refuse to run while the `TU-USUARIO` placeholder is present.

Install with `powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1` (Windows) or `bash ./install.sh` (Linux) from this directory. After editing launcher, settings, test, or agent files, re-run the installer so the installed app copy picks up the change. Run `claude-qwen-status` for a safe local check and `claude-qwen-test` after enrolling a key.

Conventions: keep `.sh`/`.py` files LF-only (enforced by `.gitattributes`) and keep console messages in the `.ps1`/`.sh` installers and launchers ASCII-only so they render correctly under Windows PowerShell 5.1 code pages and minimal Linux locales. Never copy the official Claude credential file or an API key into this repository.
