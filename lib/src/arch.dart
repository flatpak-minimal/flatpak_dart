// Which architectures' apps this machine can actually run.
//
// Flatpak arch names are not kernel arch names (`arm`, not `armv7l`; `i386`,
// not `i686`), so everything here speaks flatpak's spelling.
//
// Detection rather than configuration: a caller should not have to tell the
// library whether emulation works, because the machine already knows. What the
// machine does *not* know on its own is whether an emulated architecture is
// worth offering — see [kernelExecutableArches] for why that takes a second
// signal.

import 'dart:io';

import 'package:path/path.dart' as p;

/// How far beyond the native architecture to look for runnable apps.
enum ArchPolicy {
  /// Only the host's own architecture.
  native,

  /// The host's architecture plus those it runs natively — the 32-bit
  /// personality of a 64-bit host. Flatpak's own notion of "supported".
  compatible,

  /// Also architectures the kernel can execute through binfmt_misc.
  /// Subject to the availability check described on [kernelExecutableArches];
  /// registration alone is not enough to make an architecture worth offering.
  emulated,
}

/// Kernel machine name (`uname -m`) to flatpak's arch spelling.
///
/// Resolved once — it cannot change within a process, and `uname` is a
/// blocking subprocess spawn.
final String? hostFlatpakArch = () {
  try {
    final m = Process.runSync('uname', ['-m']).stdout.toString().trim();
    return flatpakArchFor(m);
  } catch (_) {
    return null;
  }
}();

/// Flatpak's spelling of a kernel architecture name, or `null` when it is not
/// one flatpak names.
///
/// Deliberately generous: an architecture flatpak has no refs for is harmless
/// here, because every caller intersects this with what is actually available.
/// Guessing too narrowly would silently drop a real architecture.
String? flatpakArchFor(String machine) => switch (machine) {
  'x86_64' || 'amd64' => 'x86_64',
  'i386' || 'i486' || 'i586' || 'i686' => 'i386',
  'aarch64' || 'arm64' => 'aarch64',
  'armv7l' || 'armv7hl' || 'armv6l' || 'arm' => 'arm',
  'riscv64' => 'riscv64',
  'loongarch64' => 'loongarch64',
  'ppc64le' => 'ppc64le',
  's390x' => 's390x',
  _ => null,
};

/// Architectures [hostArch] runs natively, most preferred first.
///
/// Mirrors `flatpak_get_supported_arches()`: a 64-bit host also runs its
/// 32-bit personality. Verified against `flatpak --supported-arches` on both
/// architectures this table names — flatpak 1.18.1 on x86_64 reports exactly
/// `x86_64, i386`, and flatpak 1.16.6 on an aarch64 Raspberry Pi 5 reports
/// exactly `aarch64, arm`, in that order.
List<String> compatibleArches(String hostArch) => switch (hostArch) {
  'x86_64' => const ['x86_64', 'i386'],
  'aarch64' => const ['aarch64', 'arm'],
  _ => [hostArch],
};

/// A binfmt_misc registration that can execute foreign binaries.
class BinfmtHandler {
  /// Registration name, e.g. `qemu-aarch64`.
  final String name;

  /// Flatpak arch spelling this handler executes, or `null` if unrecognised.
  final String? arch;

  /// Absolute path of the interpreter the kernel will run.
  final String interpreter;

  /// Whether the registration is enabled.
  final bool enabled;

  /// Whether the `F` (fix binary) flag is set — the kernel opens the
  /// interpreter at registration time, so it keeps working inside a mount
  /// namespace that does not contain it. Without `F` a sandboxed launch cannot
  /// reach the interpreter and the exec fails.
  final bool fixBinary;

  const BinfmtHandler({
    required this.name,
    required this.arch,
    required this.interpreter,
    required this.enabled,
    required this.fixBinary,
  });

  @override
  String toString() =>
      'BinfmtHandler($name, arch=$arch, enabled=$enabled, F=$fixBinary)';
}

/// Parses one binfmt_misc registration file's contents.
///
/// The format is one `key value` per line, with the first line being the bare
/// word `enabled` or `disabled`:
///
/// ```
/// enabled
/// interpreter /usr/bin/qemu-aarch64-static
/// flags: F
/// offset 0
/// magic 7f454c460201010000000000000000000200b7
/// ```
BinfmtHandler parseBinfmtHandler(String name, String contents) {
  var enabled = false;
  var interpreter = '';
  var flags = '';

  for (final line in contents.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed == 'enabled') {
      enabled = true;
    } else if (trimmed.startsWith('interpreter ')) {
      interpreter = trimmed.substring('interpreter '.length).trim();
    } else if (trimmed.startsWith('flags:')) {
      flags = trimmed.substring('flags:'.length).trim();
    }
  }

  return BinfmtHandler(
    name: name,
    arch: _archForHandler(name, interpreter),
    interpreter: interpreter,
    enabled: enabled,
    fixBinary: flags.contains('F'),
  );
}

/// Recovers the target architecture from a registration.
///
/// The registration name is conventionally `qemu-<arch>`, and the interpreter
/// `qemu-<arch>-static`; either will do, and the interpreter is tried second so
/// a non-standard registration name still resolves. Big-endian variants
/// (`aarch64_be`, `armeb`) are deliberately unmatched — flatpak has no refs for
/// them, and mapping them onto the little-endian arch would be wrong.
String? _archForHandler(String name, String interpreter) {
  for (final candidate in [name, p.basename(interpreter)]) {
    var s = candidate;
    if (s.startsWith('qemu-')) s = s.substring('qemu-'.length);
    if (s.endsWith('-static')) s = s.substring(0, s.length - '-static'.length);
    if (s.endsWith('-binfmt')) s = s.substring(0, s.length - '-binfmt'.length);
    final arch = flatpakArchFor(s);
    if (arch != null) return arch;
  }
  return null;
}

/// Whether [arch] is one this machine can run under [policy].
///
/// The catalog-side question is "should I ingest this architecture"; this is
/// the installed-side one — an app for an architecture the machine cannot
/// execute is installed but unrunnable, and should not be offered.
bool isRunnableArch(
  String arch,
  ArchPolicy policy, {
  String? hostArch,
  Set<String>? executableArches,
  String binfmtDir = '/proc/sys/fs/binfmt_misc',
}) => candidateArches(
  policy,
  hostArch: hostArch,
  binfmtDir: binfmtDir,
  executableArches: executableArches,
).contains(arch);

/// Caches [kernelExecutableArches] so a caller can ask per app without paying
/// a directory scan each time.
///
/// A full scan costs about a millisecond on a machine with `qemu-user-static`
/// installed (33 registrations), which is nothing once but real when a list
/// view asks per row.
///
/// There is deliberately no cheap change-detector behind this. binfmt_misc
/// does not bump the directory mtime when a registration is added — on a test
/// machine the directory's mtime was the mount time while the registrations
/// themselves were stamped later — and disabling a handler in place changes
/// neither the mtime nor the entry count, which is exactly the case that
/// matters. So the choice is a bounded staleness window plus an explicit
/// [invalidate] for callers that know something changed.
class ArchSupportCache {
  ArchSupportCache({
    this.cacheFor = const Duration(seconds: 5),
    String binfmtDir = '/proc/sys/fs/binfmt_misc',
    Set<String> Function()? scan,
  }) : _binfmtDir = binfmtDir,
       _scan = scan ?? (() => kernelExecutableArches(binfmtDir: binfmtDir));

  /// How long a scan result is reused before the kernel is consulted again.
  /// [Duration.zero] rescans every time.
  final Duration cacheFor;

  final String _binfmtDir;
  final Set<String> Function() _scan;

  Set<String>? _cached;
  final Stopwatch _age = Stopwatch();

  /// Number of scans performed. Exposed so a test can prove the cache is
  /// actually avoiding work rather than merely returning the right answer.
  int scans = 0;

  String get binfmtDir => _binfmtDir;

  /// Architectures the kernel can currently execute, from cache when fresh.
  Set<String> executableArches() {
    final cached = _cached;
    if (cached != null && _age.elapsed < cacheFor) return cached;
    scans++;
    _age
      ..reset()
      ..start();
    return _cached = _scan();
  }

  /// Drops the cached scan, so the next query consults the kernel.
  ///
  /// Call after anything that could have changed binfmt registrations —
  /// installing or removing an emulator package, or a user toggling one.
  void invalidate() {
    _cached = null;
    _age.stop();
    _age.reset();
  }
}

/// Architectures the kernel is configured to execute through binfmt_misc.
///
/// **This is not on its own a reason to offer an architecture.** A machine with
/// `qemu-user-static` installed registers every architecture qemu supports —
/// 31 of them on a stock Fedora — while a remote may publish refs for only one
/// or two. Callers must intersect this with what is actually available, which
/// for catalog work is the set of architectures that have a downloaded catalog.
///
/// [binfmtDir] and [interpreterExists] exist so this can be tested against a
/// fixture directory rather than the live kernel.
Set<String> kernelExecutableArches({
  String binfmtDir = '/proc/sys/fs/binfmt_misc',
  bool Function(String path)? interpreterExists,
}) {
  final exists = interpreterExists ?? (path) => File(path).existsSync();
  final dir = Directory(binfmtDir);
  if (!dir.existsSync()) return const {};

  final out = <String>{};
  for (final entry in _binfmtEntries(dir)) {
    final name = p.basename(entry.path);
    // Control files, not registrations.
    if (name == 'status' || name == 'register') continue;
    final String contents;
    try {
      contents = entry.readAsStringSync();
    } catch (_) {
      continue; // racing with a deregistration, or not readable
    }
    final handler = parseBinfmtHandler(name, contents);
    final arch = handler.arch;
    if (arch == null || !handler.enabled || !handler.fixBinary) continue;
    // A registration can outlive its interpreter; the kernel keeps the entry
    // but the exec would fail.
    if (handler.interpreter.isEmpty || !exists(handler.interpreter)) continue;
    out.add(arch);
  }
  return out;
}

List<File> _binfmtEntries(Directory dir) {
  try {
    return dir.listSync().whereType<File>().toList();
  } catch (_) {
    return const [];
  }
}

/// Architectures worth considering under [policy], most preferred first.
///
/// This is the *candidate* set: the host's architecture always comes first, and
/// emulated architectures come last because a native app should always win.
/// It is not a claim that any of them have apps — intersect with availability
/// before showing anything to a user.
List<String> candidateArches(
  ArchPolicy policy, {
  String? hostArch,
  String binfmtDir = '/proc/sys/fs/binfmt_misc',
  Set<String>? executableArches,
}) {
  final host = hostArch ?? hostFlatpakArch;
  // Only reachable when uname reported a machine flatpakArchFor() does not
  // name. Nothing is runnable in that case, and guessing an arch would be
  // worse than showing an empty list.
  if (host == null) return const [];

  final ordered = <String>[host];
  void add(String a) {
    if (!ordered.contains(a)) ordered.add(a);
  }

  if (policy == ArchPolicy.native) return ordered;

  for (final a in compatibleArches(host)) {
    add(a);
  }
  if (policy == ArchPolicy.compatible) return ordered;

  final emulated =
      executableArches ?? kernelExecutableArches(binfmtDir: binfmtDir);
  for (final a in emulated.toList()..sort()) {
    add(a);
  }
  return ordered;
}
