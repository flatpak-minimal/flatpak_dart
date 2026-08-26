// Host-delegated flatpak operations, for when this process is itself sandboxed.
//
// libflatpak launches by exec'ing bwrap, and enumerates instances by reading
// $XDG_RUNTIME_DIR/.flatpak. Neither works from inside a sandbox: bwrap is not
// on this side of the boundary, and the runtime dir holds only our own
// instance. So launch/stop/list are delegated to the host `flatpak` CLI over
// the Flatpak portal, which needs --talk-name=org.freedesktop.Flatpak in the
// caller's finish-args.
//
// Process spawning is injected rather than called directly so the delegation —
// the argv it builds, the settle window, the exit-code and stderr handling —
// is testable without a sandbox, a portal, or a real app to launch.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'exceptions.dart';
import 'instance.dart';

/// Spawns a process, yielding a handle to it. Defaults to [Process.start].
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Runs a process to completion. Defaults to [Process.run].
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Column order requested from `flatpak ps`. [parseHostPsOutput] is positional,
/// so the two must stay in step.
const hostPsColumns = 'application,instance,arch,branch,commit,pid,child-pid';

/// Drives the host's `flatpak` CLI through `flatpak-spawn --host`.
class HostFlatpak {
  HostFlatpak({
    ProcessStarter? start,
    ProcessRunner? run,
    Duration launchSettle = const Duration(milliseconds: 1500),
    Duration launchPollInterval = const Duration(milliseconds: 100),
  }) : _start = start ?? Process.start,
       _run = run ?? Process.run,
       _launchSettle = launchSettle,
       _launchPollInterval = launchPollInterval;

  final ProcessStarter _start;
  final ProcessRunner _run;

  /// Upper bound on how long a host-delegated `flatpak run` is given to either
  /// fail or register an instance. Only a launch that does neither — no error,
  /// no instance in `flatpak ps` — waits this out in full.
  final Duration _launchSettle;

  /// How often that wait re-checks `flatpak ps`. A failure is noticed the
  /// moment it happens regardless; this only paces the success check, which
  /// costs a subprocess each time.
  final Duration _launchPollInterval;

  /// Upper bound on captured stderr. Only the first lines of a failed
  /// `flatpak run` carry the diagnosis; the rest is the app's own logging.
  static const _stderrCap = 8 * 1024;

  /// True when this process is itself running inside a Flatpak sandbox.
  static bool get isSandboxed => File('/.flatpak-info').existsSync();

  /// Run [command] on the host through the Flatpak portal.
  Future<ProcessResult> _runOnHost(List<String> command) async {
    try {
      return await _run('flatpak-spawn', ['--host', ...command]);
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        'flatpak-spawn --host ${command.first} failed: ${e.message}',
      );
    }
  }

  /// Launch [appId] on the host via `flatpak-spawn --host flatpak run`.
  ///
  /// Returns the instance flatpak registered for the launch. When it has not
  /// appeared in `flatpak ps` yet the returned instance carries only what is
  /// known at spawn time and [FlatpakInstance.instanceId] is empty.
  Future<FlatpakInstance> launch(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
  }) async {
    final args = <String>['--host', 'flatpak', 'run'];
    if (arch.isNotEmpty) args.add('--arch=$arch');
    if (branch.isNotEmpty) args.add('--branch=$branch');
    if (commit.isNotEmpty) args.add('--commit=$commit');
    // `--` terminates option parsing: without it an appId of "--command=..."
    // is consumed by `flatpak run` as a flag, and this command line runs on
    // the *host*. The in-process path hands appId to libflatpak, which
    // validates it as a ref; this one must not be looser than that.
    args.add('--');
    args.add(appId);

    final Process proc;
    try {
      proc = await _start('flatpak-spawn', args);
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        'flatpak-spawn --host failed for "$appId": ${e.message}',
      );
    }

    // `flatpak run` forwards the app's stderr for its whole lifetime, so the
    // capture has to stop once the settle window decides the launch survived —
    // otherwise a chatty app grows this buffer without bound. The stream is
    // still drained rather than cancelled: closing the read end would hand the
    // app EPIPE on its next write.
    final stderrBuf = StringBuffer();
    var capturing = true;
    final stderrDone = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach((chunk) {
          if (!capturing) return;
          // Truncate within the chunk, not just between chunks: a pipe read
          // can deliver far more than the cap in one go.
          final room = _stderrCap - stderrBuf.length;
          if (room <= 0) return;
          stderrBuf.write(
            chunk.length <= room ? chunk : chunk.substring(0, room),
          );
        })
        .catchError((_) {});
    unawaited(proc.stdout.drain<void>().catchError((_) {}));

    // A successful `flatpak run` never exits — it stays in the foreground for
    // the app's lifetime — so there is no success code to wait for. What does
    // resolve is the run failing, or the app registering an instance. Waiting
    // on whichever comes first means a good launch is not charged the
    // worst-case failure latency; only a run that neither fails nor registers
    // sits out the full window.
    //
    // exitCode stays nullable rather than taking a sentinel: Dart reports a
    // signal-terminated child as a negative exit code, so -1 (SIGHUP) is a
    // real value here.
    int? exitCode;
    var exited = false;
    final exitSignal = proc.exitCode
        .then<void>((code) {
          exitCode = code;
          exited = true;
        })
        .catchError((_) {});

    FlatpakInstance? started;
    final deadline = DateTime.now().add(_launchSettle);
    while (!exited) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      await Future.any<void>([
        exitSignal, // resolves the instant the run fails
        Future<void>.delayed(
          remaining < _launchPollInterval ? remaining : _launchPollInterval,
        ),
      ]);
      if (exited) break;
      started = _firstInstanceOf(appId, await listRunning());
      if (started != null) break;
    }

    final code = exitCode;
    if (code != null && code != 0) {
      await stderrDone; // flush what the failed run wrote before reading it
      final detail = stderrBuf.toString().trim();
      throw FlatpakLaunchException(
        'flatpak run "$appId" on the host exited $code'
        '${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    capturing = false; // decided: keep draining stderr, but stop buffering it

    if (started != null) return started;
    // Exit code 0 lands here too: `flatpak run` returns immediately when it
    // activates an instance that was already up, and that instance is in ps.
    final instance = _firstInstanceOf(appId, await listRunning());
    if (instance != null) return instance;

    return FlatpakInstance(
      appId: appId,
      instanceId: '',
      arch: arch,
      branch: branch,
      commit: commit,
      pid: proc.pid,
      isRunning: !exited,
    );
  }

  static FlatpakInstance? _firstInstanceOf(
    String appId,
    List<FlatpakInstance> instances,
  ) {
    for (final instance in instances) {
      if (instance.appId == appId) return instance;
    }
    return null;
  }

  /// `flatpak ps` on the host, parsed into instances.
  Future<List<FlatpakInstance>> listRunning() async {
    final result = await _runOnHost([
      'flatpak',
      'ps',
      '--columns=$hostPsColumns',
    ]);
    if (result.exitCode != 0) {
      throw FlatpakLaunchException(
        'flatpak ps on the host exited ${result.exitCode}: '
        '${(result.stderr as String).trim()}',
      );
    }

    return parseHostPsOutput(result.stdout as String);
  }

  /// `flatpak kill` on the host.
  Future<void> stop(String appId) async {
    // `--` for the same reason as in [launch]: appId must not be able to
    // present itself as a flag to a command running on the host.
    final result = await _runOnHost(['flatpak', 'kill', '--', appId]);
    if (result.exitCode == 0) return;
    final detail = (result.stderr as String).trim();
    if (detail.contains('not running') || detail.contains('No such instance')) {
      throw FlatpakNotFoundException('no running instance for "$appId"');
    }
    throw FlatpakStopException(
      'flatpak kill "$appId" on the host exited ${result.exitCode}'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }
}

/// Parses `flatpak ps --columns=[hostPsColumns]` output.
///
/// Piped (non-tty) flatpak separates cells with a single tab, so a tab-bearing
/// row is split on tabs — collapsing runs of whitespace would fold an empty
/// cell (an instance with no registered branch or commit, as `flatpak-builder
/// --run` and bundle launches produce) into its neighbour, drop the row to six
/// columns, and silently lose a running instance. Space-aligned output, which
/// flatpak emits to a tty, still falls back to the whitespace split.
///
/// Rows that do not match the expected shape — a header row, or output from a
/// flatpak whose column set differs — are skipped rather than mis-bound to the
/// wrong fields.
List<FlatpakInstance> parseHostPsOutput(String stdout) {
  const columnCount = 7;
  final instances = <FlatpakInstance>[];

  for (final line in const LineSplitter().convert(stdout)) {
    // Only the line terminator is stripped up front: trimming a tab-separated
    // row would eat a trailing empty cell along with it.
    final row = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    if (row.trim().isEmpty) continue;
    final cols = row.contains('\t')
        ? [for (final c in row.split('\t')) c.trim()]
        : row.trim().split(RegExp(r'\s+'));
    if (cols.length != columnCount) continue;
    final pid = int.tryParse(cols[5]);
    final childPid = int.tryParse(cols[6]);
    if (pid == null || childPid == null) continue;
    instances.add(
      FlatpakInstance(
        appId: cols[0],
        instanceId: cols[1],
        arch: cols[2],
        branch: cols[3],
        commit: cols[4],
        pid: pid,
        childPid: childPid,
        isRunning: true,
      ),
    );
  }
  return instances;
}
