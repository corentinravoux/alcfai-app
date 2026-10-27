/// The coding agents the app knows how to launch and configure.
enum AgentKind {
  claude('claude'),
  codex('codex'),
  opencode('opencode'),
  pi('pi');

  const AgentKind(this.exe);

  /// Executable name looked up on PATH; also the `alcf-ai agent configure` name.
  final String exe;
}
