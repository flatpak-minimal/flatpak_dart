@TestOn('vm')
library;

import 'package:flatpak_dart/flatpak_dart.dart';
import 'package:test/test.dart';

void main() {
  AppRunnability build({
    String appId = 'org.x.Y',
    String arch = 'x86_64',
    bool archSupported = true,
    String? runtimeRef,
    bool runtimeInstalled = false,
    LaunchBlocker blocker = LaunchBlocker.none,
  }) => AppRunnability(
    appId: appId,
    arch: arch,
    archSupported: archSupported,
    runtimeRef: runtimeRef,
    runtimeInstalled: runtimeInstalled,
    blocker: blocker,
  );

  group('AppRunnability', () {
    test('no blocker means it should launch', () {
      final r = build(
        runtimeRef: 'org.gnome.Platform/x86_64/50',
        runtimeInstalled: true,
      );
      expect(r.canLaunch, isTrue);
      expect(r.isRecoverable, isFalse);
    });

    // The case this exists for: installed, right architecture, but the runtime
    // for that architecture was never fetched. One download away.
    test('a missing runtime blocks but is recoverable', () {
      final r = build(
        arch: 'aarch64',
        runtimeRef: 'org.gnome.Platform/aarch64/50',
        blocker: LaunchBlocker.runtimeMissing,
      );
      expect(r.canLaunch, isFalse);
      expect(r.isRecoverable, isTrue);
      expect(r.runtimeRef, 'org.gnome.Platform/aarch64/50');
    });

    // No download fixes an architecture the machine cannot execute.
    test('an architecture blocker is not recoverable', () {
      final r = build(
        arch: 'aarch64',
        archSupported: false,
        blocker: LaunchBlocker.architecture,
      );
      expect(r.canLaunch, isFalse);
      expect(r.isRecoverable, isFalse);
    });

    test('not installed blocks and is not recoverable by runtime install', () {
      final r = build(arch: '', blocker: LaunchBlocker.notInstalled);
      expect(r.canLaunch, isFalse);
      expect(r.isRecoverable, isFalse);
    });

    // Metadata with no runtime is malformed, not a reason to refuse; the
    // library defers to libflatpak rather than inventing a verdict.
    test('an app declaring no runtime is not blocked by this check', () {
      final r = build(runtimeRef: null);
      expect(r.canLaunch, isTrue);
      expect(r.runtimeRef, isNull);
    });

    test('toString names the app, arch and blocker', () {
      final s = build(
        arch: 'aarch64',
        archSupported: false,
        blocker: LaunchBlocker.architecture,
      ).toString();
      expect(s, contains('org.x.Y'));
      expect(s, contains('aarch64'));
      expect(s, contains('architecture'));
    });

    test('toString includes the runtime when there is one', () {
      final s = build(
        runtimeRef: 'org.gnome.Platform/x86_64/50',
        runtimeInstalled: true,
      ).toString();
      expect(s, contains('org.gnome.Platform/x86_64/50'));
    });
  });

  group('resolveRunnability', () {
    test('installed, right arch, runtime present -> launches', () {
      final r = resolveRunnability(
        appId: 'org.x.Y',
        arch: 'x86_64',
        installed: true,
        archSupported: true,
        runtimeRef: 'org.gnome.Platform/x86_64/50',
        runtimeInstalled: true,
      );
      expect(r.canLaunch, isTrue);
      expect(r.blocker, LaunchBlocker.none);
    });

    // Exactly what `flatpak install --arch=aarch64` leaves behind on a machine
    // that can emulate aarch64: installed, executable, runtime never fetched.
    test('runtime absent -> runtimeMissing, and it is named', () {
      final r = resolveRunnability(
        appId: 'org.gnome.Calculator',
        arch: 'aarch64',
        installed: true,
        archSupported: true,
        runtimeRef: 'org.gnome.Platform/aarch64/50',
        runtimeInstalled: false,
      );
      expect(r.blocker, LaunchBlocker.runtimeMissing);
      expect(r.isRecoverable, isTrue);
      expect(r.runtimeRef, 'org.gnome.Platform/aarch64/50');
    });

    test('not installed wins over everything else', () {
      final r = resolveRunnability(
        appId: 'org.x.Y',
        arch: 'aarch64',
        installed: false,
        archSupported: false,
        runtimeRef: 'org.gnome.Platform/aarch64/50',
        runtimeInstalled: false,
      );
      expect(r.blocker, LaunchBlocker.notInstalled);
    });

    // Precedence: an unrunnable architecture is terminal, so reporting a
    // missing runtime instead would send a caller off to install something
    // that still would not help.
    test('architecture wins over a missing runtime', () {
      final r = resolveRunnability(
        appId: 'org.x.Y',
        arch: 'aarch64',
        installed: true,
        archSupported: false,
        runtimeRef: 'org.gnome.Platform/aarch64/50',
        runtimeInstalled: false,
      );
      expect(r.blocker, LaunchBlocker.architecture);
      expect(r.isRecoverable, isFalse);
      // ...and the runtime is not reported, because it is beside the point.
      expect(r.runtimeRef, isNull);
    });

    test('a null runtime is not a blocker', () {
      final r = resolveRunnability(
        appId: 'org.x.Y',
        arch: 'x86_64',
        installed: true,
        archSupported: true,
      );
      expect(r.blocker, LaunchBlocker.none);
      expect(r.canLaunch, isTrue);
    });

    test('carries the app id and arch through every branch', () {
      for (final r in [
        resolveRunnability(
          appId: 'org.x.Y',
          arch: 'aarch64',
          installed: false,
          archSupported: false,
        ),
        resolveRunnability(
          appId: 'org.x.Y',
          arch: 'aarch64',
          installed: true,
          archSupported: false,
        ),
        resolveRunnability(
          appId: 'org.x.Y',
          arch: 'aarch64',
          installed: true,
          archSupported: true,
          runtimeRef: 'r/aarch64/1',
        ),
      ]) {
        expect(r.appId, 'org.x.Y');
        expect(r.arch, 'aarch64');
      }
    });
  });

  group('LaunchBlocker', () {
    test('covers every outcome the check can produce', () {
      expect(LaunchBlocker.values, hasLength(4));
      expect(
        LaunchBlocker.values.map((b) => b.name),
        containsAll(['none', 'notInstalled', 'architecture', 'runtimeMissing']),
      );
    });

    // Ordering matters for a UI that switches on the first blocker: an
    // architecture mismatch is terminal and should be reported instead of a
    // missing runtime, never alongside it.
    test('architecture is a distinct outcome from a missing runtime', () {
      expect(LaunchBlocker.architecture, isNot(LaunchBlocker.runtimeMissing));
    });
  });
}
