@TestOn('vm')
library;

import 'package:flatpak_dart/src/installation.dart';
import 'package:test/test.dart';

void main() {
  group('parseHostPsOutput', () {
    test('column constant matches the positional parse', () {
      expect(hostPsColumns.split(',').length, 7);
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
    // flatpak 1.12.7 with the output piped (non-tty): tab separated, no header,
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
  });
}
