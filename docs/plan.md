# alcfai-app Implementation Plan (v2, 2026-10-27)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Linux desktop app that opens any installed coding agent (claude, codex, opencode, pi) in a terminal tab, with ALCF-backed agents configured in an app-owned sandbox that never touches the Pro/Team Claude configs, and an ALCF Claude that shares the user's `claude_config` instructions and skills.

**Architecture:** Pure-Dart core (`lib/core/`) builds sandbox paths, the ALCF Claude settings seed, launch environments and `alcf-ai` commands, and guards the real config files; it is unit-tested through an injectable `Runner` and `Which`. A thin Flutter UI (`lib/ui/`) shows a profile sidebar and tabs, each tab an `xterm` view fed by a `flutter_pty` process. Two small changes in `claude_config` add the shared links (`install.sh --alcf`) and a shell guard.

**Tech Stack:** Flutter 3.47.7 / Dart 3.13.5 (Linux desktop), `xterm` ^4.0.0, `flutter_pty` ^0.4.2, `crypto` ^3.0.7, `path` ^1.9.1, `uuid` ^4.5.1, `flutter_lints` ^6.0.0; bash for `claude_config`.

**Spec:** [design.md](design.md) (same folder; copied to `docs/design.md` in Task 1).

## Global Constraints

- Flutter binary: `~/Software/flutter/bin/flutter` (not on PATH). Every command below writes `flutter` for it.
- Repo: `~/Software/alcfai-app`, Dart package `alcfai_app`, org `dev.ravoux`, platform `linux` only.
- Remote: `git@github.com:corentinravoux/alcfai-app.git`. Commit locally; **never push** (user pushes).
- Sandbox root: `~/.local/share/alcfai/home`; ALCF Claude dir `<sandbox>/.claude`. Never inside a git repo.
- The app must never write under: `~/.claude`, `~/.claude-alt`, `~/Software/claude_config/claude`, `~/.codex`, `~/.pi`, `~/.config/opencode`. It only **reads** `~/Software/claude_config/claude/settings.json`.
- `<sandbox>/.claude/settings.json` is always a real file, never a symlink.
- Memory is **not** linked into the sandbox (deferred).
- Plugins & hooks default **off** for ALCF Claude.
- Launched agents keep the real `HOME`. Only `alcf-ai agent configure` runs with `HOME=<sandbox>`.
- Default cluster `minerva`, default model `inkling-bf16`. Clusters offered: `minerva`, `sophia`, `tara`; never `metis`.
- Login/token commands use `alcf-tokens` (`login inference`, `get-token inference`, `clear-tokens`).
- Tests never touch the real home: each test uses a `Directory.systemTemp.createTempSync()` fake home.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Inherited env from VS Code** (`CLAUDE_CONFIG_DIR=~/.claude-alt`, `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`): an ALCF tab must not use the Pro login; a Pro tab must not hit ALCF. Test: `buildLaunch strips inherited agent env` (Task 3).
2. **Sandbox `settings.json` is a symlink** (someone ran plain `install.sh` against the sandbox, or linked it by hand): the seed must replace the link with a real file, and the shared file must stay byte-identical. Test: `seed replaces a symlinked settings.json without touching its target` (Task 2).
3. **alcf-ai writes to the real home anyway**: configure must report `RealConfigTouched` with the path. Test: `configure reports RealConfigTouched when a guarded file changes` (Task 4).
4. **Expired ALCF login (30-day re-auth) or IdentityMismatchError**: "Login needed" plus a Login button, or `alcf-tokens clear-tokens` advice; no hang, no stack trace. Tests: `configure returns LoginNeeded when token check fails`, `explainError maps known ALCF errors` (Task 4).
5. **Agent not installed / exits at once**: profile greyed, buttons disabled; a tab whose process dies shows `[process exited with code N]`. Tests: `sidebar disables profiles whose binary is missing` (Task 6), `terminal tab shows exit code` (Task 5).

---

### Task 1: Scaffold repo

**Files:** `flutter create` output in `~/Software/alcfai-app/`; `docs/design.md`, `docs/plan.md`, `README.md`; modify `pubspec.yaml`.

- [ ] **Step 1:** `flutter create --platforms=linux --org dev.ravoux --project-name alcfai_app ~/Software/alcfai-app`
- [ ] **Step 2:** `git init -b main`; `git remote add origin git@github.com:corentinravoux/alcfai-app.git`. If `git ls-remote origin` is non-empty, stop and ask the user.
- [ ] **Step 3:** Add deps (`xterm: ^4.0.0`, `flutter_pty: ^0.4.2`, `crypto: ^3.0.7`, `path: ^1.9.1`, `uuid: ^4.5.1`); `flutter pub get`. Expected: resolves.
- [ ] **Step 4:** Copy `design.md`, `plan.md` into `docs/`. README: intent paragraph, the "why" table, build/run commands.
- [ ] **Step 5:** `flutter test` and `flutter build linux --debug`. Expected: both pass.
- [ ] **Step 6:** Remove the counter demo and its test. Commit `chore: scaffold alcfai-app (Flutter linux)`.

### Task 2: Sandbox, Claude settings seed, real-config guard

**Files:**
- Create: `lib/core/agents.dart`, `lib/core/sandbox.dart`, `lib/core/claude_seed.dart`, `lib/core/guard.dart`
- Test: `test/core/sandbox_test.dart`, `test/core/claude_seed_test.dart`, `test/core/guard_test.dart`

**Interfaces:**
- Produces:
  - `enum AgentKind { claude, codex, opencode, pi }` with `String get exe`.
  - `class Sandbox { Sandbox({required String root, required String realHome}); String get home; String get claudeDir; Future<void> ensure(); String overrideValue(AgentKind k); bool isConfigured(AgentKind k); bool get sharedConfigLinked; Future<void> setPluginsLink(bool on); }`
  - `const kSeedKeys = ['outputStyle', 'theme', 'permissions', 'statusLine'];`
  - `const kPluginKeys = ['hooks', 'enabledPlugins', 'extraKnownMarketplaces'];`
  - `const kAlcfKeys = ['env', 'apiKeyHelper'];`
  - `Map<String, dynamic> buildClaudeSeed(Map<String, dynamic> shared, {required bool includePlugins})`
  - `Future<void> writeClaudeSeed({required String sharedSettingsPath, required String sandboxSettingsPath, required bool includePlugins})`
  - `class RealConfigGuard { RealConfigGuard(List<String> paths); static List<String> defaultPaths(String realHome); Future<Map<String, String?>> snapshot(); Future<List<String>> changedSince(Map<String, String?> before); }`

- [ ] **Step 1: Failing tests, `sandbox_test.dart`:**
  - `ensure creates home and globus symlink`: `Link('$home/.globus').targetSync() == '$realHome/.globus'`; second `ensure()` does not throw.
  - `overrideValue per agent`: claude → `$home/.claude`; codex → `$home/.codex`; pi → `$home/.pi/agent`; opencode → `$home/.config/opencode/opencode.jsonc`.
  - `isConfigured`: false on empty sandbox; claude true once `$home/.claude/settings.json` contains `"ANTHROPIC_BASE_URL"`; pi true once `$home/.pi/agent/models.json` contains `alcf-inference-service-`; codex/opencode true once their file exists.
  - `sharedConfigLinked` true only when `$claudeDir/CLAUDE.md` is a symlink.
  - `setPluginsLink(true)` makes `$claudeDir/plugins` → `$realHome/.claude/plugins`; `false` removes the link; neither touches the target dir.
  - `ensure refuses a root inside realHome/.claude*`: throws `StateError`.
- [ ] **Step 2: Failing tests, `claude_seed_test.dart`:**
  - `seed keeps only safe keys`: input = the real key set (`model`, `hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `outputStyle`, `effortLevel`, `modelSettings`, `theme`) → output keys `{outputStyle, theme}`.
  - `seed adds plugin keys when includePlugins`: output keys `{outputStyle, theme, hooks, enabledPlugins, extraKnownMarketplaces}`; never `model`, `modelSettings`, `effortLevel`.
  - `seed keeps alcf-ai keys already in the sandbox file`: existing sandbox `env` and `apiKeyHelper` (`kAlcfKeys`) survive a re-seed; every other old key is dropped (so turning plugins off removes `hooks`/`enabledPlugins`).
  - `seed replaces a symlinked settings.json without touching its target`: sandbox path is a symlink to a fake shared file; after `writeClaudeSeed`, the sandbox path is a regular file and the shared file's bytes are unchanged.
- [ ] **Step 3: Failing tests, `guard_test.dart`:**
  - `defaultPaths lists the six guarded files`: `['$h/Software/claude_config/claude/settings.json', '$h/.claude/settings.json', '$h/.claude-alt/settings.json', '$h/.codex/config.toml', '$h/.pi/agent/models.json', '$h/.config/opencode/opencode.jsonc']`.
  - `snapshot hashes through symlinks`; missing file → `null`.
  - `changedSince detects edit, creation, deletion`; `[]` when untouched.
- [ ] **Step 4:** `flutter test test/core`. Expected: FAIL.
- [ ] **Step 5:** Implement. Seed write: `Link(p).existsSync()` → `Link(p).deleteSync()` before writing; write via temp file + rename in the same dir.
- [ ] **Step 6:** `flutter test test/core`. Expected: PASS.
- [ ] **Step 7:** Commit `feat(core): sandbox, claude settings seed, real-config guard`.

### Task 3: Profiles and launch environment

**Files:** Create `lib/core/profiles.dart`, `lib/core/launch.dart`; test `test/core/launch_test.dart`.

**Interfaces:**
- Consumes: `AgentKind`, `Sandbox` (Task 2).
- Produces:
  - `enum Backend { alcf, native }`
  - `class Profile { final String id; final String label; final AgentKind kind; final Backend backend; final String? nativeConfigDir; }`
  - `List<Profile> defaultProfiles(String realHome)`: ids/labels `claude-alcf` `Claude · ALCF`, `pi-alcf` `Pi · ALCF`, `codex-alcf` `Codex · ALCF`, `opencode-alcf` `OpenCode · ALCF`, `claude-pro` `Claude · Pro` (`'$realHome/.claude-alt'`), `claude-team` `Claude · Team` (`'$realHome/.claude'`).
  - `typedef Which = String? Function(String exe);` and `String? whichOnPath(String exe, Map<String, String> env)`.
  - `const kStrippedEnvKeys = ['CLAUDE_CONFIG_DIR', 'CODEX_HOME', 'PI_CODING_AGENT_DIR', 'OPENCODE_CONFIG', 'CLAUDE_CODE_OAUTH_TOKEN', 'ALCF_SESSION_ID'];` plus every `ANTHROPIC_*` key.
  - `class LaunchSpec { final String executable; final List<String> args; final Map<String, String> env; final String cwd; }`
  - `LaunchSpec buildLaunch(Profile p, {required Sandbox sandbox, required Map<String, String> parentEnv, required String exePath, required String cwd, required String sessionId})`

- [ ] **Step 1: Failing tests:**
  - `buildLaunch strips inherited agent env`: parentEnv `CLAUDE_CONFIG_DIR=/x/.claude-alt`, `ANTHROPIC_API_KEY=k`, `ANTHROPIC_BASE_URL=u`, `PATH=/bin`, `HOME=/h`. For `claude-alcf`: `CLAUDE_CONFIG_DIR == sandbox.claudeDir`, no `ANTHROPIC_*`, `PATH == '/bin'`, `HOME == '/h'`.
  - `native profiles point at their own dir and never at ALCF`: pro → `/h/.claude-alt`, team → `/h/.claude`; no `ALCF_SESSION_ID`.
  - `alcf profiles set override and session id`: pi/codex/opencode get `PI_CODING_AGENT_DIR` / `CODEX_HOME` / `OPENCODE_CONFIG` = `sandbox.overrideValue(kind)`; `ALCF_SESSION_ID == sessionId`.
  - `cwd and args passed through` (cwd with a space kept verbatim; args empty).
  - `whichOnPath finds executables only` (finds in 2nd PATH entry; null for non-executable or missing).
- [ ] **Step 2:** `flutter test test/core/launch_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): profiles and isolated launch environment`.

### Task 4: alcf-ai wrapper

**Files:** Create `lib/core/runner.dart`, `lib/core/alcf_cli.dart`; test `test/core/alcf_cli_test.dart`, `test/support/fake_runner.dart`.

**Interfaces:**
- Consumes: `AgentKind`, `Sandbox`, `writeClaudeSeed`, `RealConfigGuard` (Task 2).
- Produces:
  - `class RunResult { final int exitCode; final String stdout; final String stderr; }`
  - `abstract class Runner { Future<RunResult> run(String exe, List<String> args, {Map<String, String>? env}); }`, `class IoRunner implements Runner`.
  - `class AlcfModel { final String id; final String displayName; final List<String> protocols; final int? contextTokens; }`
  - `const kClusters = ['minerva', 'sophia', 'tara'];`
  - `enum ModelStatus { running, queued, offline, unknown }`
  - `sealed class ConfigureResult`: `ConfigureOk`, `LoginNeeded`, `ConfigureFailed(String message)`, `RealConfigTouched(List<String> paths)`.
  - `class AlcfCli { AlcfCli({required Runner runner, required Sandbox sandbox, required RealConfigGuard guard, required String alcfExe, required String tokensExe, required String uvCacheDir, required String sharedSettingsPath, required Map<String, String> parentEnv}); Future<bool> tokenOk(); List<String> get loginCommand; Future<List<AlcfModel>> listModels(String cluster, {AgentKind? forAgent}); Future<Map<String, ModelStatus>> modelStatus(String cluster); Future<ConfigureResult> configure(AgentKind kind, {String model = 'inkling-bf16', String cluster = 'minerva', bool experimental = false, bool includePlugins = false}); }`
  - `String explainError(String stderr)`

- [ ] **Step 1: Failing tests:**
  - `configure runs alcf-ai with sandbox HOME`: args `['agent', 'configure', 'claude', '-m', 'inkling-bf16', '-c', 'minerva']`, `env['HOME'] == sandbox.home`, `env['UV_CACHE_DIR'] == uvCacheDir`, no `CLAUDE_CONFIG_DIR`; result `ConfigureOk`.
  - `configure seeds claude settings before alcf-ai`: when FakeRunner's `agent configure` handler runs, the sandbox `settings.json` already holds `outputStyle` from the fake shared file and no `model`.
  - `configure passes includePlugins to seed and plugins link`: with `includePlugins: true`, the seed has `enabledPlugins` and `$claudeDir/plugins` is a link; with `false`, neither.
  - `configure does not seed for pi/codex/opencode`.
  - `configure adds --include-experimental when asked`.
  - `configure returns LoginNeeded when token check fails` (`tokensExe get-token inference` exit 1; `agent configure` never called).
  - `configure reports RealConfigTouched when a guarded file changes`.
  - `configure maps non-zero exit to ConfigureFailed(explainError(stderr))`.
  - `loginCommand is [tokensExe, 'login', 'inference']`.
  - `explainError maps known ALCF errors`: `IdentityMismatchError` → contains `alcf-tokens clear-tokens`; `429` → `rate limit, wait and retry`; `Permission denied` → `run alcf-tokens login inference`; timeout → `model may be queued: check its status and retry`; other → last non-empty stderr line.
  - `listModels parses ls-models JSON`; `forAgent: claude` keeps only models whose protocols contain `messages`; bad JSON → `[]`.
  - `modelStatus parses ls-jobs repr` (Python-dict text: regex `'Models': '<id>'` under each top-level key `running`/`queued`/…); unparseable → `{}`.
- [ ] **Step 2:** `flutter test test/core/alcf_cli_test.dart`. Expected: FAIL.
- [ ] **Step 3:** Implement. `configure` order: `sandbox.ensure()` → `tokenOk()` → `guard.snapshot()` → (claude only) `writeClaudeSeed` + `setPluginsLink` → run alcf-ai → `guard.changedSince()` → result. Guard result wins over exit code.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(core): sandboxed alcf-ai configure with seed and guard`.

### Task 5: Terminal tab

**Files:** Create `lib/core/pty.dart`, `lib/ui/terminal_tab.dart`; test `test/ui/terminal_tab_test.dart`.

**Interfaces:**
- Consumes: `LaunchSpec` (Task 3).
- Produces:
  - `abstract class PtySession { Stream<Uint8List> get output; Future<int> get exitCode; void write(Uint8List data); void resize(int rows, int cols); void kill(); }`
  - `typedef PtyStarter = PtySession Function(LaunchSpec spec);`, `PtySession startFlutterPty(LaunchSpec spec)` (full env map, not merged with parent).
  - `class TerminalTab extends StatefulWidget { TerminalTab({required LaunchSpec spec, required PtyStarter start, required String title}); }`

- [ ] **Step 1: Failing widget tests:** `terminal tab shows exit code` (fake emits `hello`, exits 3 → buffer has `hello` and `[process exited with code 3]`); `typing is forwarded`; `dispose kills the process`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement with `Terminal` + `TerminalView`; `utf8.decoder` with `allowMalformed: true`; `terminal.onResize` → `session.resize`.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit `feat(ui): embedded terminal tab`.

### Task 6: Home page and app wiring

**Files:** Create `lib/app/app_state.dart`, `lib/ui/home_page.dart`, `lib/ui/sidebar.dart`, `lib/ui/new_session_dialog.dart`, `lib/ui/theme.dart`; modify `lib/main.dart`; test `test/ui/home_page_test.dart`.

**Interfaces:**
- Consumes: everything above.
- Produces: `class AppState extends ChangeNotifier { AppState({required List<Profile> profiles, required Which which, required Sandbox sandbox, required AlcfCli alcf, required PtyStarter start, required Map<String, String> parentEnv}); List<ProfileStatus> get statuses; List<OpenTab> get tabs; int active; bool alcfLoggedIn; Future<void> refresh(); void open(Profile p, String cwd); void close(int i); }`, `class ProfileStatus { Profile profile; String? exePath; bool configured; }` (native → `configured` true).

- [ ] **Step 1: Failing widget tests:**
  - `sidebar disables profiles whose binary is missing` (`Codex · ALCF` shows `not installed`; Open + Configure disabled).
  - `unconfigured ALCF profile offers Configure, not Open`.
  - `open adds a tab and selects it`; `close removes it`; duplicate titles `Claude · ALCF (2)`.
  - `login banner shows when alcfLoggedIn is false`; Login opens a tab running `alcf.loginCommand`.
  - `shared-config hint shows when sandbox.sharedConfigLinked is false`: text `Run ~/Software/claude_config/install.sh --alcf to share CLAUDE.md, commands and skills` on the `Claude · ALCF` tile (Open still allowed).
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. `main.dart`: `realHome` from env; sandbox root `$realHome/.local/share/alcfai/home`; `alcfExe`/`tokensExe` via `whichOnPath` (missing → banner `uv tool install alcf-ai` / `uv tool install alcf-tokens`, ALCF profiles disabled); `uvCacheDir` from `uv cache dir` (fallback `$realHome/.cache/uv`); `sharedSettingsPath = '$realHome/Software/claude_config/claude/settings.json'`. New-session dialog: folder default `$realHome/Documents/Python`, must exist. Layout: 260 px sidebar, `TabBar` + `IndexedStack`. Dark theme.
- [ ] **Step 4:** `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(ui): profile sidebar and tabbed sessions`.

### Task 7: Configure dialog

**Files:** Create `lib/ui/configure_dialog.dart`; test `test/ui/configure_dialog_test.dart`.

**Interfaces:** Consumes `AlcfCli.listModels`, `modelStatus`, `configure`, `explainError`, `ConfigureResult`, `kClusters` (Task 4); `AppState.refresh` (Task 6).

- [ ] **Step 1: Failing widget tests:**
  - `cluster dropdown offers kClusters`, default `minerva`, no `metis`.
  - `model dropdown is filled from listModels(forAgent)`; default `inkling-bf16` if present else first; status badge per model (`running` green, `queued` amber, `offline`/`unknown` grey).
  - `experimental checkbox is passed to configure`.
  - `plugins checkbox shows only for Claude · ALCF`, unchecked by default, label `Include plugins & hooks (uses much more context)`, value passed as `includePlugins`.
  - `each ConfigureResult renders`: Ok → close + refresh; LoginNeeded → message + Login button; Failed → `explainError` text; RealConfigTouched → red list of paths + `a .bak.* copy sits next to it: restore it`.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `flutter test`. Expected: PASS.
- [ ] **Step 5:** Commit `feat(ui): ALCF configure dialog`.

### Task 8: `install.sh --alcf` (claude_config)

**Files:** Modify `~/Software/claude_config/install.sh`; modify `~/Software/claude_config/README.md` (one usage line).

- [ ] **Step 1:** Add flag `--alcf` and `ALCF_CLAUDE_HOME="${ALCF_CLAUDE_HOME:-$HOME/.local/share/alcfai/home/.claude}"`. In link / `--check` / `--uninstall` modes, when `--alcf` is given, apply `HOME_LINKS` to `$ALCF_CLAUDE_HOME`, **skipping** the `claude/settings.json` entry and every `memory/*` entry (`mkdir -p` parents). Without `--alcf`, behaviour is unchanged.
- [ ] **Step 2:** Test with a throwaway target: `ALCF_CLAUDE_HOME=<scratch>/c ./install.sh --alcf --no-alt`. Expected: `<scratch>/c/CLAUDE.md`, `commands`, the five `skills/*` are links into the repo; `<scratch>/c/settings.json` and `<scratch>/c/projects` do not exist. `./install.sh --check` output for `~/.claude` and `~/.claude-alt` is identical before and after.
- [ ] **Step 3:** Run for real: `./install.sh --alcf --no-alt`. Expected: links under `~/.local/share/alcfai/home/.claude`; `git status` in `claude_config` shows only `install.sh` and `README.md` changes.
- [ ] **Step 4:** Commit in `claude_config`: `feat(install): --alcf links instructions and skills into the alcfai sandbox`.

### Task 9: Shell guard against `alcf-ai agent configure` in the real home (claude_config)

**Files:** Create `~/Software/claude_config/dotfiles/alcf-ai-guard.sh`; modify `install.sh` (link + source it like the other dotfiles).

- [ ] **Step 1:** Shell function `alcf-ai()`: if `$1 == agent && $2 == configure && $HOME == <real home>` → print `alcf-ai agent configure would edit ~/.claude/settings.json (shared by Pro and Team). Use the ALCF AI app, or HOME=~/.local/share/alcfai/home alcf-ai …` and return 1; else `command alcf-ai "$@"`. The app calls the binary by absolute path, so it is not affected.
- [ ] **Step 2:** Test in a fresh `bash -i`: `alcf-ai agent configure claude` → refused, exit 1; `alcf-ai ls-models minerva` → works; `HOME=~/.local/share/alcfai/home alcf-ai agent configure --help` → passes through.
- [ ] **Step 3:** Commit in `claude_config`: `feat(dotfiles): guard alcf-ai agent configure`.

### Task 10: Install script and end-to-end check

**Files:** Create `scripts/install-linux.sh` (pattern of `~/Software/easynote/scripts/install-linux.sh`), `assets/icon/alcfai.png`; modify `README.md`; create `docs/e2e-2026-10-27.md`.

- [ ] **Step 1:** Script: `flutter build linux --release`, copy bundle to `~/.local/opt/alcfai-app`, write `~/.local/share/applications/alcfai-app.desktop` (`Name=ALCF AI`).
- [ ] **Step 2:** Run it. Expected: app in the launcher.
- [ ] **Step 3: Manual E2E**, results into `docs/e2e-2026-10-27.md`:
  1. `sha256sum ~/Software/claude_config/claude/settings.json ~/.pi/agent/models.json` → note.
  2. Configure `Claude · ALCF` (minerva / inkling-bf16, plugins off). Expected: Ok; sandbox `settings.json` is a regular file with `outputStyle`, `theme`, `env.ANTHROPIC_BASE_URL`, `apiKeyHelper`, and no `hooks`/`enabledPlugins`/`model`.
  3. Configure `Pi · ALCF`. Expected: Ok.
  4. Re-run step 1. Expected: identical hashes.
  5. Open `Claude · ALCF` in `~/Documents/Python`. Expected: `/status` shows `inkling-bf16` and the ALCF base URL; `/skills` lists `hdr-writing`; `/memory` shows the global CLAUDE.md but no auto-memory from `claude_config/memory`.
  6. Open `Claude · Pro`. Expected: Pro login, Anthropic model, plugins as usual.
  7. Open `Pi · ALCF`, send `hi`. Expected: ALCF model answers.
  8. Re-configure `Claude · ALCF` with plugins on, reopen. Expected: plugins listed; step 1 hashes still identical.
- [ ] **Step 4:** Commit `chore: linux install script and e2e record`.
