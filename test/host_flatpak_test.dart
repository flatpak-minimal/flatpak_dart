@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flatpak_dart/src/exceptions.dart';
import 'package:flatpak_dart/src/host_flatpak.dart';
import 'package:flatpak_dart/src/installation.dart';
import 'package:test/test.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

/// A Process whose exit, stdout and stderr the test drives directly.
class _FakeProcess implements Process {
  _FakeProcess({
    this.pid = 4242,
    Future<int>? exitCode,
    Stream<List<int>>? stdout,
    Stream<List<int>>? stderr,
  }) : _exitCode = exitCode ?? Completer<int>().future, // never exits
       _stdout = stdout ?? const Stream<List<int>>.empty(),
       _stderr = stderr ?? const Stream<List<int>>.empty();

  @override
  final int pid;
  final Future<int> _exitCode;
  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;

  @override
  Future<int> get exitCode => _exitCode;
  @override
  Stream<List<int>> get stdout => _stdout;
  @override
  Stream<List<int>> get stderr => _stderr;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

/// Records every spawn and answers from a script.
class _Spawns {
  final started = <({String exe, List<String> args})>[];
  final ran = <({String exe, List<String> args})>[];

  /// Keyed by the host subcommand (`run`, `ps`, `kill`).
  final Map<String, ProcessResult> results = {};
  _FakeProcess? process;
  Object? startThrows;
  Object? runThrows;

  Future<Process> start(String exe, List<String> args) async {
    started.add((exe: exe, args: args));
    if (startThrows != null) throw startThrows!;
    return process ?? _FakeProcess();
  }

  Future<ProcessResult> run(String exe, List<String> args) async {
    ran.add((exe: exe, args: args));
    if (runThrows != null) throw runThrows!;
    // args is ['--host', 'flatpak', <subcommand>, ...]
    final sub = args.length > 2 ? args[2] : '';
    return results[sub] ?? ProcessResult(0, 0, '', '');
  }
}

Stream<List<int>> _chunks(List<String> parts) =>
    Stream.fromIterable(parts.map(utf8.encode));

HostFlatpak _host(
  _Spawns spawns, {
  Duration settle = const Duration(milliseconds: 20),
  Duration poll = const Duration(milliseconds: 2),
}) => HostFlatpak(
  start: spawns.start,
  run: spawns.run,
  launchSettle: settle,
  launchPollInterval: poll,
);

void main() {
  group('parseHostPsOutput', () {
    test('column constant matches the positional parse', () {
      expect(hostPsColumns.split(','), [
        'application',
        'instance',
        'arch',
        'branch',
        'commit',
        'pid',
        'child-pid',
      ]);
    });

    // Captured verbatim from `flatpak ps --columns=<hostPsColumns>` on
    // flatpak 1.18.1 with the output piped (non-tty): tab separated, no header,
    // commit truncated to 12 chars by flatpak itself.
    test('parses real flatpak ps output', () {
      const sample =
          'org.gnome.Chess\t4127712988\taarch64\tstable\t2ebb126e84c4\t1020423\t1020425\n';

      final got = parseHostPsOutput(sample);
      expect(got, hasLength(1));
      expect(got.single.appId, 'org.gnome.Chess');
      expect(got.single.instanceId, '4127712988');
      expect(got.single.arch, 'aarch64');
      expect(got.single.branch, 'stable');
      expect(got.single.commit, '2ebb126e84c4');
      expect(got.single.pid, 1020423);
      expect(got.single.childPid, 1020425);
      expect(got.single.isRunning, isTrue);
    });

    test('parses several rows', () {
      const sample =
          'org.gnome.Chess\t4127712988\taarch64\tstable\t2ebb126e84c4\t1020423\t1020425\n'
          'md.obsidian.Obsidian\t884413309\taarch64\tstable\tfeedface1234\t5100\t5108\n';
      final got = parseHostPsOutput(sample);
      expect(got, hasLength(2));
      expect(got.last.appId, 'md.obsidian.Obsidian');
      expect(got.last.pid, 5100);
    });

    test('accepts space-aligned columns', () {
      const sample =
          'org.gnome.Calculator   2298374127   x86_64   stable   deadbeef   4242   4250\n';
      expect(parseHostPsOutput(sample).single.childPid, 4250);
    });

    test('skips a header row instead of mis-binding it', () {
      const sample =
          'Application\tInstance\tArch\tBranch\tCommit\tPID\tChild-PID\n'
          'org.gnome.Calculator\t22983\tx86_64\tstable\tdeadbeef\t4242\t4250\n';
      final got = parseHostPsOutput(sample);
      expect(got, hasLength(1));
      expect(got.single.appId, 'org.gnome.Calculator');
    });

    test('skips rows whose column count does not match', () {
      const sample = 'org.gnome.Calculator\t22983\tx86_64\tstable\n';
      expect(parseHostPsOutput(sample), isEmpty);
    });

    test('empty output yields no instances', () {
      expect(parseHostPsOutput(''), isEmpty);
      expect(parseHostPsOutput('\n\n'), isEmpty);
    });

    // An instance with no registered branch or commit — what `flatpak-builder
    // --run` and bundle launches produce — leaves those cells empty. Splitting
    // on runs of whitespace would fold the two empty cells away, leave five
    // columns, and drop a running instance the caller then cannot stop.
    test('keeps a row whose middle cells are empty', () {
      const sample = 'org.example.Dev\t118820\tx86_64\t\t\t9001\t9002\n';
      final got = parseHostPsOutput(sample);
      expect(got, hasLength(1));
      expect(got.single.appId, 'org.example.Dev');
      expect(got.single.branch, isEmpty);
      expect(got.single.commit, isEmpty);
      expect(got.single.pid, 9001);
      expect(got.single.childPid, 9002);
    });

    test('keeps a row whose leading cell is empty', () {
      const sample = '\t118820\tx86_64\tstable\tdeadbeef\t9001\t9002\n';
      expect(parseHostPsOutput(sample).single.appId, isEmpty);
    });

    // pid and child-pid are the fields a stop actually needs, so a row missing
    // either is unusable rather than merely sparse.
    test('drops a row with no pid', () {
      const sample = 'org.example.Dev\t118820\tx86_64\tstable\tdead\t\t9002\n';
      expect(parseHostPsOutput(sample), isEmpty);
    });

    test('tolerates CRLF line endings', () {
      const sample =
          'org.gnome.Chess\t4127712988\taarch64\tstable\t2ebb\t1020423\t1020425\r\n';
      expect(parseHostPsOutput(sample).single.pid, 1020423);
    });
  });

  group('HostFlatpak.launch', () {
    test('delegates through flatpak-spawn --host', () async {
      final spawns = _Spawns();
      await _host(spawns).launch('org.gnome.Chess');
      final call = spawns.started.single;
      expect(call.exe, 'flatpak-spawn');
      expect(call.args.take(3), ['--host', 'flatpak', 'run']);
    });

    // Without the terminator, `flatpak run` parses a leading-dash app id as one
    // of its own options — on the *host*, outside this process's sandbox.
    test('terminates options before the app id', () async {
      final spawns = _Spawns();
      await _host(spawns).launch('org.gnome.Chess');
      final args = spawns.started.single.args;
      expect(args.last, 'org.gnome.Chess');
      expect(args[args.length - 2], '--');
    });

    test('an app id that looks like a flag stays an operand', () async {
      final spawns = _Spawns();
      await _host(spawns).launch('--command=/bin/sh');
      final args = spawns.started.single.args;
      expect(args.indexOf('--') < args.indexOf('--command=/bin/sh'), isTrue);
      // ...and it is not mistaken for one of flatpak run's own options.
      expect(args.sublist(0, args.indexOf('--')), ['--host', 'flatpak', 'run']);
    });

    test('passes arch, branch and commit as flags', () async {
      final spawns = _Spawns();
      await _host(
        spawns,
      ).launch('org.x.Y', arch: 'aarch64', branch: 'beta', commit: 'dead');
      expect(
        spawns.started.single.args,
        containsAllInOrder([
          '--arch=aarch64',
          '--branch=beta',
          '--commit=dead',
          '--',
          'org.x.Y',
        ]),
      );
    });

    test('omits flags that were not given', () async {
      final spawns = _Spawns();
      await _host(spawns).launch('org.x.Y');
      expect(spawns.started.single.args, [
        '--host',
        'flatpak',
        'run',
        '--',
        'org.x.Y',
      ]);
    });

    test('a failing run throws with the stderr detail', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(
          exitCode: Future.value(1),
          stderr: _chunks(['error: app/org.x.Y/x86_64/stable not installed']),
        );
      await expectLater(
        _host(spawns).launch('org.x.Y'),
        throwsA(
          isA<FlatpakLaunchException>().having(
            (e) => e.message,
            'message',
            allOf(contains('exited 1'), contains('not installed')),
          ),
        ),
      );
    });

    // Dart reports a signal-terminated child as a negative exit code, so -1 is
    // SIGHUP, not a sentinel. Treating it as "still running" reported a launch
    // that had already died as a success.
    test('a signal-terminated run is a failure, not a success', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(exitCode: Future.value(-1));
      await expectLater(
        _host(spawns).launch('org.x.Y'),
        throwsA(isA<FlatpakLaunchException>()),
      );
    });

    test('caps the stderr it quotes back', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(
          exitCode: Future.value(1),
          stderr: _chunks([List.filled(64 * 1024, 'x').join()]),
        );
      try {
        await _host(spawns).launch('org.x.Y');
        fail('expected a launch failure');
      } on FlatpakLaunchException catch (e) {
        expect(e.message.length, lessThan(16 * 1024));
      }
    });

    test('surviving the settle window returns the ps instance', () async {
      final spawns = _Spawns()
        ..results['ps'] = ProcessResult(
          0,
          0,
          'org.x.Y\t99887766\tx86_64\tstable\tdeadbeef\t700\t701\n',
          '',
        );
      final instance = await _host(spawns).launch('org.x.Y');
      expect(instance.instanceId, '99887766');
      expect(instance.pid, 700);
      expect(instance.childPid, 701);
      expect(instance.isRunning, isTrue);
    });

    test(
      'falls back to a synthetic instance when ps has not caught up',
      () async {
        final spawns = _Spawns()..process = _FakeProcess(pid: 31337);
        final instance = await _host(
          spawns,
        ).launch('org.x.Y', arch: 'x86_64', branch: 'stable');
        expect(instance.instanceId, isEmpty);
        expect(instance.appId, 'org.x.Y');
        expect(instance.arch, 'x86_64');
        expect(instance.branch, 'stable');
        expect(instance.pid, 31337);
        expect(instance.isRunning, isTrue);
      },
    );

    // The app keeps writing to stderr for its whole lifetime; the launch must
    // not wait on that stream, and must not keep buffering it either.
    test('does not wait on a still-open stderr', () async {
      final flooding = StreamController<List<int>>();
      addTearDown(flooding.close);
      final spawns = _Spawns()..process = _FakeProcess(stderr: flooding.stream);

      final instance = await _host(
        spawns,
      ).launch('org.x.Y').timeout(const Duration(seconds: 5));
      expect(instance.appId, 'org.x.Y');

      // Still live after the launch resolved: writing more must not throw.
      flooding.add(utf8.encode('chatty app logging\n'));
      await flooding.close();
    });

    // The point of polling: a launch that registers promptly must not be
    // charged the full failure-detection window.
    test('returns as soon as the instance registers', () async {
      final spawns = _Spawns()
        ..results['ps'] = ProcessResult(
          0,
          0,
          'org.x.Y\t99887766\tx86_64\tstable\tdeadbeef\t700\t701\n',
          '',
        );
      final sw = Stopwatch()..start();
      final instance = await _host(
        spawns,
        settle: const Duration(seconds: 30),
        poll: const Duration(milliseconds: 2),
      ).launch('org.x.Y');
      sw.stop();
      expect(instance.instanceId, '99887766');
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'should not have waited out the 30s settle window',
      );
    });

    // ...and a failure is noticed the moment it happens, not on the next poll.
    test('a failure is not deferred to the next poll tick', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(
          exitCode: Future.value(1),
          stderr: _chunks(['not installed']),
        );
      final sw = Stopwatch()..start();
      await expectLater(
        _host(
          spawns,
          settle: const Duration(seconds: 30),
          poll: const Duration(seconds: 10),
        ).launch('org.x.Y'),
        throwsA(isA<FlatpakLaunchException>()),
      );
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    // An app already running: `flatpak run` activates it and returns 0, so a
    // clean exit is a success when ps has the instance.
    test('a clean exit with a registered instance is a success', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(exitCode: Future.value(0))
        ..results['ps'] = ProcessResult(
          0,
          0,
          'org.x.Y\t555\tx86_64\tstable\tdead\t900\t901\n',
          '',
        );
      final instance = await _host(spawns).launch('org.x.Y');
      expect(instance.instanceId, '555');
    });

    // A clean exit with nothing registered: the app ran and finished.
    test('a clean exit with no instance reports not running', () async {
      final spawns = _Spawns()
        ..process = _FakeProcess(exitCode: Future.value(0), pid: 4242);
      final instance = await _host(spawns).launch('org.x.Y');
      expect(instance.instanceId, isEmpty);
      expect(instance.isRunning, isFalse);
      expect(instance.pid, 4242);
    });

    test('a missing flatpak-spawn is reported as a launch failure', () async {
      final spawns = _Spawns()
        ..startThrows = const ProcessException(
          'flatpak-spawn',
          [],
          'No such file or directory',
        );
      await expectLater(
        _host(spawns).launch('org.x.Y'),
        throwsA(
          isA<FlatpakLaunchException>().having(
            (e) => e.message,
            'message',
            contains('org.x.Y'),
          ),
        ),
      );
    });
  });

  group('HostFlatpak.listRunning', () {
    test('asks for exactly the columns the parser expects', () async {
      final spawns = _Spawns();
      await _host(spawns).listRunning();
      expect(spawns.ran.single.args, [
        '--host',
        'flatpak',
        'ps',
        '--columns=$hostPsColumns',
      ]);
    });

    test('parses the host output', () async {
      final spawns = _Spawns()
        ..results['ps'] = ProcessResult(
          0,
          0,
          'org.a.A\t1\tx86_64\tstable\tc1\t10\t11\n'
              'org.b.B\t2\tx86_64\tstable\tc2\t20\t21\n',
          '',
        );
      final got = await _host(spawns).listRunning();
      expect(got.map((i) => i.appId), ['org.a.A', 'org.b.B']);
    });

    test('a failing ps throws rather than reporting nothing running', () async {
      final spawns = _Spawns()
        ..results['ps'] = ProcessResult(0, 1, '', 'portal not available');
      await expectLater(
        _host(spawns).listRunning(),
        throwsA(
          isA<FlatpakLaunchException>().having(
            (e) => e.message,
            'message',
            contains('portal not available'),
          ),
        ),
      );
    });
  });

  group('HostFlatpak.stop', () {
    test('terminates options before the app id', () async {
      final spawns = _Spawns();
      await _host(spawns).stop('org.x.Y');
      expect(spawns.ran.single.args, [
        '--host',
        'flatpak',
        'kill',
        '--',
        'org.x.Y',
      ]);
    });

    test('a clean exit succeeds', () async {
      final spawns = _Spawns()..results['kill'] = ProcessResult(0, 0, '', '');
      await _host(spawns).stop('org.x.Y'); // no throw
    });

    test('"not running" maps to not-found', () async {
      final spawns = _Spawns()
        ..results['kill'] = ProcessResult(
          0,
          1,
          '',
          'error: org.x.Y is not running',
        );
      await expectLater(
        _host(spawns).stop('org.x.Y'),
        throwsA(isA<FlatpakNotFoundException>()),
      );
    });

    test('any other failure is a stop failure carrying the detail', () async {
      final spawns = _Spawns()
        ..results['kill'] = ProcessResult(0, 1, '', 'permission denied');
      await expectLater(
        _host(spawns).stop('org.x.Y'),
        throwsA(
          isA<FlatpakStopException>().having(
            (e) => e.message,
            'message',
            allOf(contains('exited 1'), contains('permission denied')),
          ),
        ),
      );
    });
  });

  // FlatpakInstallation routes launch/stop/listRunning to the host delegate
  // when one is set, and never touches the native reader on that path — which
  // is what makes these runnable without libflatpak present.
  group('FlatpakInstallation delegation', () {
    test('launch goes to the host', () async {
      final spawns = _Spawns();
      final installation = FlatpakInstallation.delegatingTo(
        'user',
        _host(spawns),
      );
      await installation.launch('org.x.Y');
      expect(spawns.started.single.args.take(3), ['--host', 'flatpak', 'run']);
    });

    test('stop goes to the host', () async {
      final spawns = _Spawns();
      final installation = FlatpakInstallation.delegatingTo(
        'user',
        _host(spawns),
      );
      await installation.stop('org.x.Y');
      expect(spawns.ran.single.args, [
        '--host',
        'flatpak',
        'kill',
        '--',
        'org.x.Y',
      ]);
    });

    test('listRunning goes to the host', () async {
      final spawns = _Spawns()
        ..results['ps'] = ProcessResult(
          0,
          0,
          'org.a.A\t1\tx86_64\tstable\tc1\t10\t11\n',
          '',
        );
      final installation = FlatpakInstallation.delegatingTo(
        'user',
        _host(spawns),
      );
      final got = await installation.listRunning();
      expect(got.single.appId, 'org.a.A');
    });
  });
}
