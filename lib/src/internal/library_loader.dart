// DynamicLibrary.open() resolution for the flatpak_nc shared library.
//
// Resolution order:
//   1. FLATPAK_NC_LIB environment variable (explicit path)
//   2. Native assets bundled library (@Native annotation / hook/build.dart)
//   3. Common build output directories
//   4. System library search (LD_LIBRARY_PATH)

import 'dart:ffi';
import 'dart:io';

abstract final class LibraryLoader {
  static DynamicLibrary load() {
    // 1. Check environment variable override.
    final envPath = Platform.environment['FLATPAK_NC_LIB'];
    if (envPath != null && envPath.isNotEmpty) {
      return DynamicLibrary.open(envPath);
    }

    // 2. Try native asset bundled path (from hook/build.dart).
    //    When built via native assets, the Dart VM makes the library
    //    available via DynamicLibrary.open with just the asset name.
    try {
      return DynamicLibrary.open('libflatpak_nc.so');
    } on ArgumentError {
      // Not bundled — fall through to manual search
    }

    // 3. Try common build output locations.
    for (final path in _searchPaths) {
      final file = File(path);
      if (file.existsSync()) {
        return DynamicLibrary.open(file.absolute.path);
      }
    }

    // 4. Last resort — will throw if not found.
    throw UnsupportedError(
      'Could not find libflatpak_nc.so. Either:\n'
      '  - Set FLATPAK_NC_LIB=/path/to/libflatpak_nc.so\n'
      '  - Run ./scripts/build_release.sh from the package root\n'
      '  - Use the native assets build hook (requires --enable-experiment=native-assets)',
    );
  }

  static const _searchPaths = [
    'build/libflatpak_nc.so',
    'build-asan/libflatpak_nc.so',
    'build-debug/libflatpak_nc.so',
    'build-release/libflatpak_nc.so',
    'native/build/libflatpak_nc.so',
    'linux/shared/libflatpak_nc.so',
  ];
}
