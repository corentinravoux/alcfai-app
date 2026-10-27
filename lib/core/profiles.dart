import 'agents.dart';

enum Backend { alcf, native }

/// One entry in the sidebar: an agent plus where its config lives.
class Profile {
  const Profile({
    required this.id,
    required this.label,
    required this.kind,
    required this.backend,
    this.nativeConfigDir,
  });

  final String id;
  final String label;
  final AgentKind kind;
  final Backend backend;

  /// For native Claude profiles: the existing Claude home, launch-only.
  final String? nativeConfigDir;

  bool get isAlcf => backend == Backend.alcf;
}

List<Profile> defaultProfiles(String realHome) => [
  const Profile(
    id: 'claude-alcf',
    label: 'Claude · ALCF',
    kind: AgentKind.claude,
    backend: Backend.alcf,
  ),
  const Profile(
    id: 'pi-alcf',
    label: 'Pi · ALCF',
    kind: AgentKind.pi,
    backend: Backend.alcf,
  ),
  const Profile(
    id: 'codex-alcf',
    label: 'Codex · ALCF',
    kind: AgentKind.codex,
    backend: Backend.alcf,
  ),
  const Profile(
    id: 'opencode-alcf',
    label: 'OpenCode · ALCF',
    kind: AgentKind.opencode,
    backend: Backend.alcf,
  ),
  Profile(
    id: 'claude-pro',
    label: 'Claude · Pro',
    kind: AgentKind.claude,
    backend: Backend.native,
    nativeConfigDir: '$realHome/.claude-alt',
  ),
  Profile(
    id: 'claude-team',
    label: 'Claude · Team',
    kind: AgentKind.claude,
    backend: Backend.native,
    nativeConfigDir: '$realHome/.claude',
  ),
];
