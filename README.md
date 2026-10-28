# alcfai-app

A small Linux desktop app that opens the coding agents installed on this
machine (`claude`, `pi`, `codex`, `opencode`) in terminal tabs, and lets you
switch between them. Agents served by the
[ALCF Inference Endpoints](https://docs.alcf.anl.gov/services/inference-endpoints/)
are configured with `alcf-ai agent configure <agent>` **inside an app-owned
sandbox** (`~/.local/share/alcfai/home`), so your normal Claude Code setups
(`~/.claude`, `~/.claude-alt`) are never touched.

## Why a sandbox

`alcf-ai agent configure` writes to fixed files in your home directory, and
writes through symlinks:

| agent | file alcf-ai writes | how the app redirects it |
|---|---|---|
| claude | `~/.claude/settings.json` | `CLAUDE_CONFIG_DIR` |
| codex | `~/.codex/config.toml` | `CODEX_HOME` |
| opencode | `~/.config/opencode/opencode.jsonc` | `OPENCODE_CONFIG` |
| pi | `~/.pi/agent/models.json` | `PI_CODING_AGENT_DIR` |

The app runs `alcf-ai` with `HOME` set to the sandbox, then launches each
agent with your real `HOME` and the variable above pointing into the sandbox.
Before and after every configure run it hashes your real config files and
reports any change.

## In a session

| keys | does |
|---|---|
| Ctrl+Shift+C / Ctrl+Shift+V | copy selection / paste |
| Ctrl+Shift+A | select all output |
| Ctrl+Shift+F | find in output (Enter next, Shift+Enter previous, Esc close) |
| Ctrl+= / Ctrl+- / Ctrl+0 | bigger / smaller / default text |
| Ctrl+click on a link | open it in the browser |

Plain Ctrl+A, Ctrl+C and Ctrl+V go to the agent. Configure remembers the
cluster and model per agent (Pi and OpenCode start on it with `--model`,
Codex with `-p alcf-<cluster>-<model>`). The app warns
when that model is queued or offline, asks before closing a running session,
offers Restart on an ended one, and offers to reopen last run's sessions.
It re-checks the ALCF login every 3 hours. Its own state lives in
`~/.local/share/alcfai/state.json`.

## Build and run

```bash
~/Software/flutter/bin/flutter pub get
~/Software/flutter/bin/flutter test
~/Software/flutter/bin/flutter run -d linux
./scripts/install-linux.sh        # release build + desktop entry
```

Agents are looked up on `PATH` plus `~/.local/bin`, `~/.opencode/bin`,
`~/.bun/bin`, `~/.npm-global/bin` and `~/.cargo/bin`, since a menu launch
does not read `~/.bashrc`.

Codex needs three workarounds for the ALCF gateway, which the app applies
(sandbox only): after configure it sets `apply_patch_tool_type` to null in
`<sandbox>/.codex/catalogs/*.json`, and it launches codex with
`--disable multi_agent -c web_search="disabled"`. Codex only gets Minerva
models (the only cluster serving the `responses` API). See
[docs/e2e-2026-10-28-codex-opencode.md](docs/e2e-2026-10-28-codex-opencode.md).

On Ubuntu 23.10+ codex's command sandbox (bubblewrap) fails inside the app
with `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`, because
unconfined programs may not use user namespaces. Run
`./scripts/install-apparmor.sh` once (sudo): it installs the same
userns-only profile Ubuntu ships for VS Code.

Needs `alcf-ai` and `alcf-tokens` on `PATH` (`uv tool install alcf-ai`,
`uv tool install alcf-tokens`) and a login (`alcf-tokens login inference`).

To share your `claude_config` instructions and skills with the ALCF Claude:
`~/Software/claude_config/install.sh --alcf --no-alt`.

Design: [docs/design.md](docs/design.md). Plan: [docs/plan.md](docs/plan.md).
