import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    // Allow an embedder/build system
    final skipDefine = input.userDefines['skip_native_build'];
    if (skipDefine == true || skipDefine == 'true') {
      stderr.writeln(
        'skip_native_build user-define set — skipping native build.',
      );
      return;
    }

    final clearDefine = input.userDefines['clear_ambient_flags'];
    final clearAmbientFlags = clearDefine == true || clearDefine == 'true';

    final nativeDir = input.packageRoot.resolve('native/').toFilePath();
    final buildDir =
        input.outputDirectory.resolve('native_build/').toFilePath();

    await Directory(buildDir).create(recursive: true);

    final hasNinja = await _which('ninja');

    if (!File('${buildDir}CMakeCache.txt').existsSync()) {
      await _run('cmake', [
        '-S',
        nativeDir,
        '-B',
        buildDir,
        '-DCMAKE_BUILD_TYPE=Release',
        if (hasNinja) ...['-G', 'Ninja'],
      ], clearAmbientFlags: clearAmbientFlags);
    }

    await _run('cmake', [
      '--build',
      buildDir,
      '--parallel',
    ], clearAmbientFlags: clearAmbientFlags);

    final libFile = File('${buildDir}libflatpak_nc.so');
    if (!libFile.existsSync()) {
      throw StateError('libflatpak_nc.so not found at ${libFile.path}');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'libflatpak_nc.so',
        linkMode: DynamicLoadingBundled(),
        file: libFile.uri,
      ),
    );

    // Re-run the hook whenever any C/C++ source or CMake file changes.
    for (final dir in ['src', 'include']) {
      final d = Directory('$nativeDir$dir');
      if (!d.existsSync()) continue;
      for (final entity in d.listSync(recursive: true)) {
        if (entity is! File) continue;
        final p = entity.path;
        if (p.endsWith('.cpp') ||
            p.endsWith('.cc') ||
            p.endsWith('.c') ||
            p.endsWith('.hpp') ||
            p.endsWith('.h')) {
          output.dependencies.add(entity.uri);
        }
      }
    }
    output.dependencies.add(Uri.file('${nativeDir}CMakeLists.txt'));

    stderr.writeln('libflatpak_nc built: ${libFile.path}');
  });
}

const _clearedFlagVars = {'CFLAGS': '', 'CXXFLAGS': '', 'LDFLAGS': ''};

Future<void> _run(
  String exe,
  List<String> args, {
  required bool clearAmbientFlags,
}) async {
  final p = await Process.start(
    exe,
    args,
    mode: ProcessStartMode.inheritStdio,
    environment: clearAmbientFlags ? _clearedFlagVars : null,
  );
  final code = await p.exitCode;
  if (code != 0) {
    throw ProcessException(exe, args, 'exit code $code', code);
  }
}

Future<bool> _which(String exe) async {
  try {
    final r = await Process.run('sh', ['-c', 'command -v $exe']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}
