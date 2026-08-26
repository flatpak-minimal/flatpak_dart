@TestOn('vm')
library;

import 'dart:io';

import 'package:flatpak_dart/src/arch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A binfmt_misc registration as the kernel renders it. Captured verbatim from
/// /proc/sys/fs/binfmt_misc/qemu-aarch64 on Fedora with qemu-user-static
/// installed.
String registration({
  bool enabled = true,
  String interpreter = '/usr/bin/qemu-aarch64-static',
  String flags = 'F',
}) =>
    '${enabled ? 'enabled' : 'disabled'}\n'
    'interpreter $interpreter\n'
    'flags: $flags\n'
    'offset 0\n'
    'magic 7f454c460201010000000000000000000200b700\n'
    'mask ffffffffffffff00fffffffffffffffffeffffff\n';

void main() {
  group('flatpakArchFor', () {
    test('maps kernel names to flatpak spelling', () {
      // The two that differ are the ones that matter: flatpak says `arm`, not
      // `armv7l`, and `i386`, not `i686`.
      expect(flatpakArchFor('armv7l'), 'arm');
      expect(flatpakArchFor('i686'), 'i386');
      expect(flatpakArchFor('x86_64'), 'x86_64');
      expect(flatpakArchFor('aarch64'), 'aarch64');
    });

    test('accepts the common aliases', () {
      expect(flatpakArchFor('amd64'), 'x86_64');
      expect(flatpakArchFor('arm64'), 'aarch64');
    });

    test('an unknown machine is null, not a guess', () {
      expect(flatpakArchFor('vax'), isNull);
      expect(flatpakArchFor(''), isNull);
    });
  });

  group('compatibleArches', () {
    // Verified against `flatpak --supported-arches` on x86_64, which reports
    // exactly these two in this order.
    test('x86_64 also runs i386', () {
      expect(compatibleArches('x86_64'), ['x86_64', 'i386']);
    });

    test('aarch64 also runs arm', () {
      expect(compatibleArches('aarch64'), ['aarch64', 'arm']);
    });

    test('the host is always first', () {
      for (final a in ['x86_64', 'aarch64', 'riscv64']) {
        expect(compatibleArches(a).first, a);
      }
    });

    test('an arch with no 32-bit personality is alone', () {
      expect(compatibleArches('riscv64'), ['riscv64']);
    });
  });

  group('parseBinfmtHandler', () {
    test('parses a real registration', () {
      final h = parseBinfmtHandler('qemu-aarch64', registration());
      expect(h.arch, 'aarch64');
      expect(h.interpreter, '/usr/bin/qemu-aarch64-static');
      expect(h.enabled, isTrue);
      expect(h.fixBinary, isTrue);
    });

    test('reads disabled registrations as disabled', () {
      final h = parseBinfmtHandler(
        'qemu-aarch64',
        registration(enabled: false),
      );
      expect(h.enabled, isFalse);
    });

    test('detects a missing F flag', () {
      final h = parseBinfmtHandler('qemu-aarch64', registration(flags: 'OC'));
      expect(h.fixBinary, isFalse);
    });

    test('finds F among several flags', () {
      final h = parseBinfmtHandler('qemu-aarch64', registration(flags: 'OCF'));
      expect(h.fixBinary, isTrue);
    });

    test('recovers the arch from the interpreter when the name is odd', () {
      final h = parseBinfmtHandler('my-custom-handler', registration());
      expect(h.arch, 'aarch64');
    });

    test('an unrecognised arch is null rather than a guess', () {
      final h = parseBinfmtHandler(
        'qemu-vax',
        registration(interpreter: '/usr/bin/qemu-vax-static'),
      );
      expect(h.arch, isNull);
    });

    // flatpak has no big-endian refs; mapping aarch64_be onto aarch64 would
    // claim the machine can run binaries it cannot.
    test('big-endian variants do not map onto the little-endian arch', () {
      final h = parseBinfmtHandler(
        'qemu-aarch64_be',
        registration(interpreter: '/usr/bin/qemu-aarch64_be-static'),
      );
      expect(h.arch, isNull);
      expect(
        parseBinfmtHandler(
          'qemu-armeb',
          registration(interpreter: '/usr/bin/qemu-armeb-static'),
        ).arch,
        isNull,
      );
    });

    // binfmt_misc is not only for emulators: Debian registers Python bytecode
    // through it too. Captured verbatim from /proc/sys/fs/binfmt_misc on a
    // Raspberry Pi 5 running Debian 13, where it is the *only* registration —
    // a machine that must report no emulated architectures at all.
    test('a non-emulator registration is not an architecture', () {
      const pi =
          'enabled\n'
          'interpreter /usr/bin/python3.13\n'
          'flags: \n'
          'offset 0\n'
          'magic f30d0d0a\n';
      final h = parseBinfmtHandler('python3.13', pi);
      expect(h.arch, isNull);
      expect(h.enabled, isTrue);
      expect(h.fixBinary, isFalse);
    });

    test('survives a truncated file', () {
      final h = parseBinfmtHandler('qemu-aarch64', 'enabled\n');
      expect(h.enabled, isTrue);
      expect(h.interpreter, isEmpty);
      expect(h.fixBinary, isFalse);
    });
  });

  group('kernelExecutableArches', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('fp_binfmt_'));
    tearDown(() => dir.deleteSync(recursive: true));

    void write(String name, String contents) =>
        File(p.join(dir.path, name)).writeAsStringSync(contents);

    Set<String> scan({bool interpreterPresent = true}) =>
        kernelExecutableArches(
          binfmtDir: dir.path,
          interpreterExists: (_) => interpreterPresent,
        );

    test('finds an enabled handler', () {
      write('qemu-aarch64', registration());
      expect(scan(), {'aarch64'});
    });

    test('ignores a disabled handler', () {
      write('qemu-aarch64', registration(enabled: false));
      expect(scan(), isEmpty);
    });

    // Without F the kernel resolves the interpreter by path at exec time, and
    // that path does not exist inside the sandbox a flatpak runs in.
    test('ignores a handler with no F flag', () {
      write('qemu-aarch64', registration(flags: 'OC'));
      expect(scan(), isEmpty);
    });

    // A registration outlives an uninstalled qemu; the entry stays but the
    // exec would fail.
    test('ignores a handler whose interpreter is gone', () {
      write('qemu-aarch64', registration());
      expect(scan(interpreterPresent: false), isEmpty);
    });

    test('skips the control files', () {
      write('status', 'enabled\n');
      write('register', '');
      write('qemu-aarch64', registration());
      expect(scan(), {'aarch64'});
    });

    test('collects several handlers', () {
      write('qemu-aarch64', registration());
      write(
        'qemu-riscv64',
        registration(interpreter: '/usr/bin/qemu-riscv64-static'),
      );
      write('qemu-vax', registration(interpreter: '/usr/bin/qemu-vax-static'));
      expect(scan(), {'aarch64', 'riscv64'});
    });

    // The whole-directory version of the case above.
    test('a directory of only non-emulator handlers yields nothing', () {
      write(
        'python3.13',
        'enabled\ninterpreter /usr/bin/python3.13\nflags: \noffset 0\n',
      );
      write('jar', 'enabled\ninterpreter /usr/bin/jexec\nflags: \n');
      expect(scan(), isEmpty);
    });

    test('a missing binfmt directory is empty, not an error', () {
      expect(
        kernelExecutableArches(binfmtDir: p.join(dir.path, 'nope')),
        isEmpty,
      );
    });

    test('an empty binfmt directory is empty', () {
      expect(scan(), isEmpty);
    });
  });

  group('isRunnableArch', () {
    test('the host arch is always runnable', () {
      expect(
        isRunnableArch('aarch64', ArchPolicy.native, hostArch: 'aarch64'),
        isTrue,
      );
    });

    test('a foreign arch is not runnable under compatible', () {
      expect(
        isRunnableArch('x86_64', ArchPolicy.compatible, hostArch: 'aarch64'),
        isFalse,
      );
    });

    test('a foreign arch becomes runnable when the kernel can execute it', () {
      expect(
        isRunnableArch(
          'x86_64',
          ArchPolicy.emulated,
          hostArch: 'aarch64',
          executableArches: const {'x86_64'},
        ),
        isTrue,
      );
    });

    test('emulated without a handler is still not runnable', () {
      expect(
        isRunnableArch(
          'x86_64',
          ArchPolicy.emulated,
          hostArch: 'aarch64',
          executableArches: const {},
        ),
        isFalse,
      );
    });
  });

  group('ArchSupportCache', () {
    test('scans once and reuses the answer', () {
      var calls = 0;
      final cache = ArchSupportCache(
        cacheFor: const Duration(hours: 1),
        scan: () {
          calls++;
          return {'aarch64'};
        },
      );
      for (var i = 0; i < 50; i++) {
        expect(cache.executableArches(), {'aarch64'});
      }
      expect(calls, 1, reason: 'a list view must not rescan per row');
      expect(cache.scans, 1);
    });

    // The user-visible case: someone disables or removes an emulator while the
    // app is running. Nothing about binfmt_misc can be watched cheaply, so the
    // caller has to say when to look again.
    test('invalidate makes the next query consult the kernel', () {
      var current = {'aarch64', 'riscv64'};
      var calls = 0;
      final cache = ArchSupportCache(
        cacheFor: const Duration(hours: 1),
        scan: () {
          calls++;
          return current;
        },
      );
      expect(cache.executableArches(), {'aarch64', 'riscv64'});

      current = {'aarch64'}; // user disabled qemu-riscv64
      expect(cache.executableArches(), {'aarch64', 'riscv64'}, reason: 'stale');

      cache.invalidate();
      expect(cache.executableArches(), {'aarch64'});
      expect(calls, 2);
    });

    test('a zero window rescans every time', () {
      var calls = 0;
      final cache = ArchSupportCache(
        cacheFor: Duration.zero,
        scan: () {
          calls++;
          return const {'aarch64'};
        },
      );
      cache.executableArches();
      cache.executableArches();
      cache.executableArches();
      expect(calls, 3);
    });

    test('invalidating before any query is harmless', () {
      final cache = ArchSupportCache(scan: () => const {'aarch64'});
      cache.invalidate();
      expect(cache.executableArches(), {'aarch64'});
      expect(cache.scans, 1);
    });

    test('defaults to reading the live kernel', () {
      // No scan injected: it must reach binfmt_misc without throwing, whatever
      // this machine has registered.
      final cache = ArchSupportCache();
      expect(cache.executableArches(), isA<Set<String>>());
    });
  });

  group('candidateArches', () {
    test('native is the host alone', () {
      expect(candidateArches(ArchPolicy.native, hostArch: 'aarch64'), [
        'aarch64',
      ]);
    });

    test('compatible adds the native-compatible arches', () {
      expect(candidateArches(ArchPolicy.compatible, hostArch: 'aarch64'), [
        'aarch64',
        'arm',
      ]);
    });

    test('compatible ignores emulation entirely', () {
      expect(
        candidateArches(
          ArchPolicy.compatible,
          hostArch: 'aarch64',
          executableArches: {'x86_64'},
        ),
        ['aarch64', 'arm'],
      );
    });

    test('emulated appends what the kernel can execute', () {
      expect(
        candidateArches(
          ArchPolicy.emulated,
          hostArch: 'aarch64',
          executableArches: {'x86_64', 'i386'},
        ),
        ['aarch64', 'arm', 'i386', 'x86_64'],
      );
    });

    // Ordering is the policy: a native build must always beat an emulated one
    // when both exist, so the host stays first no matter what is registered.
    test('the host stays first even when it is also emulated', () {
      final got = candidateArches(
        ArchPolicy.emulated,
        hostArch: 'aarch64',
        executableArches: {'aarch64', 'x86_64'},
      );
      expect(got.first, 'aarch64');
      expect(got.where((a) => a == 'aarch64'), hasLength(1));
    });

    test('emulated with nothing registered equals compatible', () {
      expect(
        candidateArches(
          ArchPolicy.emulated,
          hostArch: 'x86_64',
          executableArches: const {},
        ),
        candidateArches(ArchPolicy.compatible, hostArch: 'x86_64'),
      );
    });

    test('an unspecified host uses the detected one', () {
      expect(
        candidateArches(ArchPolicy.compatible),
        compatibleArches(hostFlatpakArch!),
      );
    });
  });

  group('hostFlatpakArch', () {
    test('resolves on this machine', () {
      expect(hostFlatpakArch, isNotNull);
      expect(compatibleArches(hostFlatpakArch!).first, hostFlatpakArch);
    });
  });
}
