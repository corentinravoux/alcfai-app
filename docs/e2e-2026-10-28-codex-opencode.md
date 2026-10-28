# End-to-end check, codex and opencode, 2026-10-28

codex-cli 0.165.0 (`~/.local/bin`), opencode 1.19.5 (`~/.opencode/bin`, only
on PATH through `~/.bashrc`).

| step | how | result |
|---|---|---|
| configure Codex · ALCF | `PATH=~/.opencode/bin:$PATH dart run tool/e2e_configure.dart codex` | `ok`; providers `alcf-inference-service-minerva-api` only (the only cluster with the `responses` API); profiles `alcf-minerva-{gpt-oss-120b,inkling-bf16,muse-spark-bf16,nemotron-3-ultra}.config.toml` |
| configure OpenCode · ALCF | same tool, `opencode` | `ok`; v1 schema, providers `…-minerva-api`, `…-sophia-vllm`; plugin `alcf-ai-opencode-plugin` with the token helper |
| real files | `sha256sum ~/.codex/config.toml ~/.claude/settings.json ~/.claude-alt/settings.json` before and after | identical |
| Codex answers, as alcf-ai left it | `CODEX_HOME=<sandbox>/.codex codex exec -p alcf-minerva-gpt-oss-120b …` | fails: HTTP 400 three times over, one tool type at a time: grammar-format custom tool (`apply_patch_tool_type: freeform` in the catalog), `namespace` (feature `multi_agent`), `web_search` |
| Codex answers, as the app launches it | catalogs patched to `apply_patch_tool_type: null`, `--disable multi_agent -c web_search="disabled" -p alcf-minerva-<model>` | `OK` with gpt-oss-120b and inkling-bf16; file edits work through the shell (the model tries `apply_patch` once, gets "unsupported call", falls back) |
| OpenCode answers | `OPENCODE_CONFIG=<sandbox>/.config/opencode/opencode.jsonc opencode run -m alcf-inference-service-minerva-api/gpt-oss-120b …` | `OK`, no fix needed |

Also found: `alcf-ai ls-models minerva` printed a raw newline inside a model
description (rich wraps at the terminal width), which broke JSON parsing.
The app now runs it with `COLUMNS=100000` and drops newlines before parsing.
