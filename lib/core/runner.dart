import 'dart:io';

class RunResult {
  const RunResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs a command to completion. [env], when given, is the child's whole
/// environment (the parent's is not merged in).
abstract class Runner {
  Future<RunResult> run(
    String exe,
    List<String> args, {
    Map<String, String>? env,
  });
}

class IoRunner implements Runner {
  const IoRunner({this.timeout = const Duration(minutes: 2)});
  final Duration timeout;

  @override
  Future<RunResult> run(
    String exe,
    List<String> args, {
    Map<String, String>? env,
  }) async {
    try {
      final r = await Process.run(
        exe,
        args,
        environment: env,
        includeParentEnvironment: env == null,
      ).timeout(timeout);
      return RunResult(r.exitCode, '${r.stdout}', '${r.stderr}');
    } on ProcessException catch (e) {
      return RunResult(127, '', e.message);
    } on Exception catch (e) {
      return RunResult(124, '', 'timed out: $e');
    }
  }
}
