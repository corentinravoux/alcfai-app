# alcfai-app — design

Date: 2026-10-27. Status: awaiting approval. Repo: `~/Software/alcfai-app`
(remote `github.com/corentinravoux/alcfai-app`).

## Intent

A small Linux desktop app, VS Code side-panel style, that lists the coding
agents installed on this laptop (`claude`, `codex`, `opencode`, `pi`), lets the
user open one in a tab, and switches between them. Agents backed by the ALCF
inference service are configured by `alcf-ai agent configure <agent>` **inside
an app-owned sandbox**, so the Pro (`~/.claude-alt`) and Team (`~/.claude`)
Claude Code setups are never touched.

## Why — the incident this prevents

`alcf-ai agent configure` writes to hard-coded `Path.home()` locations and
writes **through symlinks**:

| agent | file written by alcf-ai | runtime override the app uses |
|---|---|---|
| claude | `~/.claude/settings.json` (env `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, 3× `ANTHROPIC_DEFAULT_*_MODEL`, `apiKeyHelper`) | `CLAUDE_CONFIG_DIR` |
| codex | `~/.codex/config.toml` + `~/.codex/` model catalogs (runs `codex --version`) | `CODEX_HOME` |
| opencode | `~/.config/opencode/opencode.jsonc` (+ clears `~/.cache/opencode` plugin cache) | `OPENCODE_CONFIG` |
| pi | `~/.pi/agent/models.json` | `PI_CODING_AGENT_DIR` |

`~/.claude/settings.json` and `~/.claude-alt/settings.json` are both symlinks
to `~/Software/claude_config/claude/settings.json`. One run of
`alcf-ai agent configure claude` therefore switched **both** accounts to ALCF
with default model `inkling-bf16` (backup
`settings.json.bak.20261027-162743` proves it ran at 16:27 today; the file is
clean again now). That is the "new sessions open inkling-bf16" bug.

## Mechanism (decided)

1. **Configure** = run `alcf-ai agent configure <agent> -m <model> -c <cluster>`
   with `HOME=<sandbox>` and `UV_CACHE_DIR=<real uv cache dir>`. alcf-ai then
   writes only under the sandbox. `<sandbox>/.globus` is a symlink to the real
   `~/.globus` so alcf-ai finds the Globus tokens
   (`~/.globus/app/7f3e61f5-…/alcf_tokens`). The token helper alcf-ai embeds is
   the absolute path `~/.local/bin/alcf-ai auth get-access-token`, so it keeps
   working at runtime.
2. **Launch** keeps the **real `HOME`** (git, ssh, Overleaf credentials keep
   working) and points the agent at the sandbox via the override variable in
   the table above. The app strips `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN` and
   any inherited `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `PI_CODING_AGENT_DIR` /
   `OPENCODE_CONFIG` from the parent env first (VS Code sets
   `CLAUDE_CONFIG_DIR=~/.claude-alt`). Each tab gets a fresh
   `ALCF_SESSION_ID` (uuid), used by alcf-ai's request headers.
3. **Guard**: before and after every configure run, the app hashes the real
   files (resolved through symlinks): `~/Software/claude_config/claude/settings.json`,
   `~/.claude/settings.json`, `~/.claude-alt/settings.json`,
   `~/.codex/config.toml`, `~/.pi/agent/models.json`,
   `~/.config/opencode/opencode.jsonc`. Any change ⇒ red error naming the file
   and its `.bak.*`; the configure is reported as failed.
4. **UI**: left sidebar = profiles; right = tabs, each an embedded terminal
   (`xterm` 4.0.0 + `flutter_pty` 0.4.2) running the agent's own TUI. No custom
   chat UI: every agent already ships a good TUI, and a chat UI would need four
   different headless protocols.

## ALCF Claude shares claude_config (decided 2026-10-27)

The sandbox `.claude/` (`~/.local/share/alcfai/home/.claude`) gets the user's
instructions and skills, but never a shared `settings.json`.

| item | how | default |
|---|---|---|
| `CLAUDE.md`, `commands/`, `skills/{hdr-writing,latex-manuscript,graphify,grant-proposals,manuscript-review}` | symlinks made by `claude_config/install.sh --alcf` (same `HOME_LINKS` table) | on |
| `settings.json` | **real file**, rebuilt by the app on every Claude Configure, then edited by alcf-ai | always |
| plugins + hooks (`hooks`, `enabledPlugins`, `extraKnownMarketplaces` keys + `plugins/` → `~/.claude/plugins` link) | "Include plugins & hooks" checkbox in Configure | **off** (context size) |
| `memory/` | not linked | off; later, if wanted |

Settings seed: start from `claude_config/claude/settings.json`, keep only
`outputStyle` and `theme` (plus `permissions` and `statusLine` if they ever
appear); add the three plugin keys only when the checkbox is on. `model`,
`modelSettings`, `effortLevel` are always dropped (they name Anthropic
models). If the sandbox `settings.json` is a symlink, the app deletes the
link and writes a real file; it never writes through a link.

## Profiles

| profile | backend | launch env |
|---|---|---|
| Claude · ALCF | ALCF, sandbox | `CLAUDE_CONFIG_DIR=<sandbox>/.claude` |
| Pi · ALCF | ALCF, sandbox | `PI_CODING_AGENT_DIR=<sandbox>/.pi/agent` |
| Codex · ALCF | ALCF, sandbox | `CODEX_HOME=<sandbox>/.codex` |
| OpenCode · ALCF | ALCF, sandbox | `OPENCODE_CONFIG=<sandbox>/.config/opencode/opencode.jsonc` |
| Claude · Pro | native, read-only | `CLAUDE_CONFIG_DIR=~/.claude-alt` |
| Claude · Team | native, read-only | `CLAUDE_CONFIG_DIR=~/.claude` |

A profile whose binary is not on `PATH` is shown greyed "not installed"; its
Configure button is disabled (alcf-ai's codex path crashes without `codex`).
Today: `claude` 2.1.311 and `pi` 1.4.0 are installed; `codex` and `opencode`
are not.

## ALCF service facts (from the ALCF docs page, last updated 2026-10-16)

| cluster | hardware | base URL | `/messages` (Claude) | alcf-ai allowlist |
|---|---|---|---|---|
| sophia | A100, vLLM | `/resource_server/sophia/vllm/v1` | yes | `openai/gpt-oss-120b` |
| metis | SN40L | `/resource_server/metis/api/v1` | **no** | disabled (tool-call bug) |
| minerva | B200 | `/resource_server/minerva/api/v1` | yes | `nemotron-3-ultra`, `inkling-bf16`, `gpt-oss-120b`, `muse-spark-bf16` |
| tara | GH200 | `/resource_server/tara/api/v1` | yes | none (experimental only) |

- Login: `alcf-tokens login inference` (inference scopes only). Token check:
  `alcf-tokens get-token inference` (auto-refreshes). Both CLIs are installed
  in `~/.local/bin`.
- Access token 48 h, auto-refreshed; forced re-login every 30 days.
- Tokens: `~/.globus/app/7f3e61f5-e0de-4e8f-9150-0a62c65dda63/alcf_tokens/tokens.json`.
- A model may be offline or queued: first request can time out while it loads.
  `alcf-ai ls-jobs <cluster>` gives status (output is a Python dict repr, not
  JSON).
- Known errors: `IdentityMismatchError` (fix: `alcf-tokens clear-tokens`, then
  login), HTTP 429 (rate limit), permission denied (re-login).

## Goals

- One window, switch agents by clicking; several tabs at once; pick working
  folder per tab (default `~/Documents/Python`).
- Configure an ALCF agent from the app: cluster dropdown `minerva`, `sophia`,
  `tara` (metis left out: no `/messages`, and alcf-ai disables it); model
  dropdown filled from `alcf-ai ls-models <cluster>`, each model tagged
  running / queued / offline from `ls-jobs`; "Include experimental models"
  checkbox → `--include-experimental` (needed for tara). Defaults `minerva` /
  `inkling-bf16`, alcf-ai's own defaults.
- Show ALCF login state (`alcf-tokens get-token inference` exit code); a Login
  button opens a tab running `alcf-tokens login inference`.
- Turn the known errors above into one plain line with the fix.

## Non-goals

- No custom chat UI, no Windows/macOS, no Android.
- No installing codex/opencode.
- No editing of the Pro/Team Claude configs, ever (native profiles only launch).

## Anti-goals (a failure even if it "works")

- Any byte changed in `~/.claude*`, `claude_config/claude/`, `~/.codex`,
  `~/.pi`, `~/.config/opencode` by the app.
- An ALCF tab that silently runs on the Pro/Team Anthropic login, or a
  Pro/Team tab that silently hits ALCF.
- Tokens written into the git repo.

## Constraints

- Flutter `~/Software/flutter/bin/flutter` 3.47.7, Dart 3.13.5 (not on PATH).
- Linux desktop only. Layout and conventions follow `~/Software/easynote`
  (`lib/<area>/…`, `scripts/install-linux.sh`, `flutter_lints`).
- Sandbox root: `~/.local/share/alcfai/home` (outside every git repo; may hold
  an embedded token when no helper is found).
- User pushes; Claude commits locally only.

## Calls made by Claude (check these)

1. Embedded terminal instead of a chat UI.
2. Native Claude Pro/Team profiles included (launch-only).
3. (Replaced by user decision, see "ALCF Claude shares claude_config".)
   Plugins/hooks default off because they eat much of the ALCF models'
   context (131 072 tokens for `gpt-oss-120b`; alcf-ai assumes 65 536 when a
   model does not say).
7. The Claude model dropdown only offers models whose
   `capabilities.api_protocols` contains `messages` (Anthropic API); other
   agents get every model of the cluster.
4. Sandbox location `~/.local/share/alcfai/home`.
5. Extra protection (plan Task 9): a shell guard in `claude_config/dotfiles` that
   refuses `alcf-ai agent configure` when `HOME` is the real home.
6. `OPENCODE_CONFIG` (not `XDG_CONFIG_HOME`), so git's `~/.config/git`
   credential helper keeps working inside opencode. Unverified until opencode
   is installed.
