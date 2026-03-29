// hook/build.dart — Native asset build hook for flatpak_dart.
//
// Automatically builds libflatpak_nc.so via CMake when the package is
// consumed as a dependency. Requires: cmake, clang (or gcc), pkg-config,
// libflatpak-dev, libglib2.0-dev.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = input.packageRoot;
    final nativeDir = packageRoot.resolve('native/');
    final buildDir = input.outputDirectory.resolve('native_build/');
    final buildDirPath = buildDir.toFilePath();

    // Ensure build directory exists
    await Directory(buildDirPath).create(recursive: true);

    // Find a C++ compiler
    final cxx = _findCompiler(['clang++-19', 'clang++', 'g++']);
    final cc = _findCompiler(['clang-19', 'clang', 'gcc']);

    // Run CMake configure
    final configResult = await Process.run('cmake', [
      '-B', buildDirPath,
      '-S', nativeDir.toFilePath(),
      '-DCMAKE_BUILD_TYPE=Release',
      if (cxx != null) '-DCMAKE_CXX_COMPILER=$cxx',
      if (cc != null) '-DCMAKE_C_COMPILER=$cc',
    ]);
    if (configResult.exitCode != 0) {
      throw Exception(
          'CMake configure failed:\n${configResult.stderr}');
    }

    // Run CMake build
    final cpuCount = Platform.numberOfProcessors;
    final buildResult = await Process.run('cmake', [
      '--build', buildDirPath,
      '--parallel', '$cpuCount',
    ]);
    if (buildResult.exitCode != 0) {
      throw Exception(
          'CMake build failed:\n${buildResult.stderr}');
    }

    // Add source files as dependencies for rebuild detection
    output.dependencies.add(nativeDir.resolve('CMakeLists.txt'));
    for (final uri in await _globSources(nativeDir.resolve('src/'))) {
      output.dependencies.add(uri);
    }
    for (final uri in await _globSources(nativeDir.resolve('include/'))) {
      output.dependencies.add(uri);
    }

    // Register the built shared library as a code asset
    final soPath = buildDir.resolve('libflatpak_nc.so');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'libflatpak_nc.so',
        file: soPath,
        linkMode: DynamicLoadingBundled(),
      ),
    );
  });
}

String? _findCompiler(List<String> candidates) {
  for (final name in candidates) {
    final result = Process.runSync('which', [name]);
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  }
  return null;
}

Future<List<Uri>> _globSources(Uri dir) async {
  final directory = Directory.fromUri(dir);
  if (!await directory.exists()) return [];
  final files = <Uri>[];
  await for (final entity in directory.list(recursive: true)) {
    if (entity is File) {
      final path = entity.path;
      if (path.endsWith('.cpp') ||
          path.endsWith('.c') ||
          path.endsWith('.h')) {
        files.add(entity.uri);
      }
    }
  }
  return files;
}
