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
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'instance.dart';

/// Spawns a process, yielding a handle to it. Defaults to [Process.start].
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Runs a process to completion. Defaults to [Process.run].
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// The parent of process [pid], or null when it is gone.
typedef ProcessParent = int? Function(int pid);

/// This process's environment as libc has it now. [Platform.environment], and
/// so a plain [Process.start], keeps the one the process started with, and
/// misses what native code set later with setenv(3): a compositor embedded in
/// the caller sets WAYLAND_DISPLAY that way, for the apps it launches.
/// An entry that is not valid UTF-8 is decoded leniently rather than failing
/// every launch.
Map<String, String> _liveEnvironment() {
  final environ = DynamicLibrary.process()
      .lookup<Pointer<Pointer<Utf8>>>('environ')
      .value;
  final env = <String, String>{};
  for (var i = 0; environ[i] != nullptr; i++) {
    final p = environ[i];
    final entry = utf8.decode(
      p.cast<Uint8>().asTypedList(p.length),
      allowMalformed: true,
    );
    final eq = entry.indexOf('=');
    if (eq > 0) env[entry.substring(0, eq)] = entry.substring(eq + 1);
  }
  return env;
}

/// Starts a child that writes straight to this process's stdout and stderr,
/// as the in-process launch's app did: nothing is copied through Dart, and
/// the app's writes never fail because this side stopped reading.
Future<Process> _startWithLiveEnvironment(
  String executable,
  List<String> args,
) => Process.start(
  executable,
  args,
  environment: _liveEnvironment(),
  includeParentEnvironment: false,
  mode: ProcessStartMode.inheritStdio,
);

int? _procParent(int pid) {
  try {
    // The command name, in parentheses, may itself hold spaces and ')'.
    final stat = File('/proc/$pid/stat').readAsStringSync();
    final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
    return int.tryParse(fields[1]);
  } on FileSystemException {
    return null;
  }
}

/// Column order requested from `flatpak ps`. [parseHostPsOutput] is positional,
/// so the two must stay in step.
///
/// `runtime`/`runtime-branch` are requested so this path can report the same
/// full runtime ref libflatpak gives the in-process path. flatpak splits them
/// into a bare id and a branch, so the ref is reassembled in the parse.
const hostPsColumns =
    'application,instance,arch,branch,commit,runtime,runtime-branch,pid,child-pid';

/// Drives the host's `flatpak` CLI through `flatpak-spawn --host`, or, made
/// with [HostFlatpak.child], as a child process of this one.
class HostFlatpak {
  HostFlatpak({
    ProcessStarter? start,
    ProcessRunner? run,
    Duration launchSettle = const Duration(milliseconds: 1500),
    Duration launchPollInterval = const Duration(milliseconds: 100),
    Map<String, String>? environment,
  }) : _start = start ?? Process.start,
       _run = run ?? Process.run,
       _launchSettle = launchSettle,
       _launchPollInterval = launchPollInterval,
       _environment = environment ?? Platform.environment,
       _via = const ['flatpak-spawn', '--host'],
       _scope = const [],
       _parentOf = null;

  /// Runs `flatpak` as a child of this process, for a caller on the host.
  ///
  /// libflatpak's in-process launch moves its caller into the app's systemd
  /// scope: it asks systemd for the scope with its own pid, before it spawns
  /// bwrap. A long-lived caller (a launcher or a shell) then lives in the
  /// first app's scope, and stopping that app stops the caller too. A child
  /// `flatpak run` is the process that moves instead.
  ///
  /// [installation] is `user` or `system`. The child gets this process's
  /// environment as it is at the launch, which is also what the in-process
  /// launch passes on, and this process's stdout and stderr, so the app logs
  /// where it would have. A failed run's message is then in that log, not in
  /// the exception.
  HostFlatpak.child({
    required String installation,
    ProcessStarter? start,
    ProcessRunner? run,
    Duration launchSettle = const Duration(milliseconds: 1500),
    Duration launchPollInterval = const Duration(milliseconds: 100),
    ProcessParent? parentOf,
  }) : _start = start ?? _startWithLiveEnvironment,
       _run = run ?? Process.run,
       _launchSettle = launchSettle,
       _launchPollInterval = launchPollInterval,
       _environment = const {},
       _via = const [],
       _scope = ['--$installation'],
       _parentOf = parentOf ?? _procParent;

  final ProcessStarter _start;
  final ProcessRunner _run;

  /// What runs `flatpak`: the portal, or nothing for a child process.
  final List<String> _via;

  /// The `flatpak run` option naming the installation, for a child process.
  /// Through the portal there is none, and `flatpak run` takes the app from
  /// whichever installation has it.
  final List<String> _scope;

  /// For a child process, the parent of a pid, to tell this launch's
  /// instance from an earlier one of the same app.
  final ProcessParent? _parentOf;

  final Map<String, String> _environment;

  /// What an app launched on the host inherits from this process, so it opens
  /// where this app is: `flatpak-spawn --host` runs the command in the session
  /// helper's environment, not ours, and without these the app lands on the
  /// session's own display rather than the compositor this app is shown on.
  static const forwardedEnvironment = <String>[
    'WAYLAND_DISPLAY',
    // Chromium/Electron choose Wayland over X11 only in a wayland session.
    'XDG_SESSION_TYPE',
  ];

  /// The name flatpak gives the Wayland socket inside a sandbox whenever it
  /// cannot keep the host's: a host name that does not start with `wayland-`,
  /// or that contains a `/` (gamescope's `gamescope-0`, for one). Seeing it,
  /// the host's real name is unknown, so nothing is forwarded and the launch
  /// keeps the session helper's environment.
  static const _sandboxDefaultWaylandDisplay = 'wayland-0';

  /// `flatpak-spawn --env=` options for [forwardedEnvironment]. They are
  /// forwarded only with a Wayland display: without one, claiming a Wayland
  /// session would only steer Chromium/Electron away from the X11 the helper
  /// already describes. With one, the session's X11 display is cleared too, so
  /// an app that would fall back to X11 cannot open on the session's desktop
  /// either. An X11-only app then fails to start rather than opening there.
  List<String> _forwardedEnv() {
    final display = _environment['WAYLAND_DISPLAY'];
    if (display == null ||
        display.isEmpty ||
        display == _sandboxDefaultWaylandDisplay) {
      return const [];
    }
    return [
      for (final name in forwardedEnvironment)
        if (_environment[name] case final String value when value.isNotEmpty)
          '--env=$name=$value',
      '--env=DISPLAY=',
    ];
  }

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

  /// Run [command] on the host through the Flatpak portal, or as a child.
  Future<ProcessResult> _runOnHost(List<String> command) async {
    final argv = [..._via, ...command];
    try {
      return await _run(argv.first, argv.sublist(1));
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        '${argv.first} ${command.first} failed: ${e.message}',
      );
    }
  }

  /// Launch [appId] on the host via `flatpak-spawn --host flatpak run`.
  ///
  /// Returns the instance flatpak registered for the launch. When it has not
  /// appeared in `flatpak ps` yet the returned instance carries only what is
  /// known at spawn time and [FlatpakInstance.instanceId] is empty.
  ///
  /// [activationToken] is passed to the app as `XDG_ACTIVATION_TOKEN`, so the
  /// compositor gives its first window focus. It has to be a fresh token,
  /// requested through `xdg_activation_v1` against the caller's own surface
  /// just before the launch. The token this process was started with has
  /// already been used, which is why nothing is read from the environment.
  /// Empty launches without one.
  Future<FlatpakInstance> launch(
    String appId, {
    String arch = '',
    String branch = '',
    String commit = '',
    String activationToken = '',
  }) async {
    // A child inherits this process's environment and needs none forwarded;
    // the token then goes to the app through `flatpak run` itself.
    final child = _via.isEmpty;
    final args = <String>[
      ..._via,
      if (!child) ..._forwardedEnv(),
      if (!child && activationToken.isNotEmpty)
        '--env=XDG_ACTIVATION_TOKEN=$activationToken',
      'flatpak',
      'run',
      ..._scope,
      if (child && activationToken.isNotEmpty)
        '--env=XDG_ACTIVATION_TOKEN=$activationToken',
    ];
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
      proc = await _start(args.first, args.sublist(1));
    } on ProcessException catch (e) {
      throw FlatpakLaunchException(
        '${args.first} failed for "$appId": ${e.message}',
      );
    } on Exception catch (e) {
      throw FlatpakLaunchException('${args.first} failed for "$appId": $e');
    }

    // `flatpak run` forwards the app's stderr for its whole lifetime, so the
    // capture has to stop once the settle window decides the launch survived —
    // otherwise a chatty app grows this buffer without bound. The stream is
    // still drained rather than cancelled: closing the read end would hand the
    // app EPIPE on its next write.
    //
    // A child shares this process's stdout and stderr instead: there is
    // nothing to read.
    final stderrBuf = StringBuffer();
    var capturing = true;
    var stderrDone = Future<void>.value();
    if (!child) {
      stderrDone = proc.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .forEach((chunk) {
            if (!capturing) return;
            // Truncate within the chunk, not just between chunks: a pipe
            // read can deliver far more than the cap in one go.
            final room = _stderrCap - stderrBuf.length;
            if (room <= 0) return;
            stderrBuf.write(
              chunk.length <= room ? chunk : chunk.substring(0, room),
            );
          })
          .catchError((_) {});
      unawaited(proc.stdout.drain<void>().catchError((_) {}));
    }

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
      started = _instanceOf(
        appId,
        proc.pid,
        await listRunning(),
        ownOnly: true,
      );
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
    // A run still going is not that: it gets its own instance or none, not
    // an older one of the same app.
    final instance = _instanceOf(
      appId,
      proc.pid,
      await listRunning(),
      ownOnly: !exited,
    );
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

  /// This launch's instance of [appId]. A child `flatpak run` execs the
  /// instance's bwrap, so the instance has the child's pid (a run that spawns
  /// bwrap instead is its parent); that tells it from an earlier instance of
  /// the same app. Through the portal the pids are the host's, so the first
  /// instance is taken, as it is for an instance `flatpak run` only
  /// activated.
  ///
  /// With [ownOnly], a child process takes only its own instance, so that
  /// the settle loop keeps waiting for it rather than settling on another.
  FlatpakInstance? _instanceOf(
    String appId,
    int launcherPid,
    List<FlatpakInstance> instances, {
    bool ownOnly = false,
  }) {
    final parentOf = _parentOf;
    if (parentOf != null) {
      for (final instance in instances) {
        if (instance.appId == appId &&
            (instance.pid == launcherPid ||
                parentOf(instance.pid) == launcherPid)) {
          return instance;
        }
      }
      if (ownOnly) return null;
    }
    return _firstInstanceOf(appId, instances);
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
  const columnCount = 9;
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
    final pid = int.tryParse(cols[7]);
    final childPid = int.tryParse(cols[8]);
    if (pid == null || childPid == null) continue;
    instances.add(
      FlatpakInstance(
        appId: cols[0],
        instanceId: cols[1],
        arch: cols[2],
        branch: cols[3],
        commit: cols[4],
        runtime: _runtimeRef(cols[5], cols[2], cols[6]),
        pid: pid,
        childPid: childPid,
        isRunning: true,
      ),
    );
  }
  return instances;
}

/// Reassembles the full runtime ref `flatpak ps` splits across columns, in the
/// shape `flatpak_instance_get_runtime()` hands the in-process path:
/// `runtime/org.freedesktop.Platform/x86_64/25.08`. Empty when flatpak names
/// no runtime, rather than a half-built `runtime///` that only looks like one.
String _runtimeRef(String id, String arch, String branch) {
  if (id.isEmpty) return '';
  return 'runtime/$id/$arch/$branch';
}
