// DynamicLibrary.open() resolution for the flatpak_nc shared library.

import 'dart:ffi';
import 'dart:io';

abstract final class LibraryLoader {
  static DynamicLibrary load() {
    // 1. Check environment variable override.
    final envPath = Platform.environment['FLATPAK_NC_LIB'];
    if (envPath != null && envPath.isNotEmpty) {
      return DynamicLibrary.open(envPath);
    }

    // 2. Try common build output locations.
    for (final path in _searchPaths) {
      try {
        return DynamicLibrary.open(path);
      } on ArgumentError {
        continue;
      }
    }

    // 3. Fall back to system library search.
    return DynamicLibrary.open('libflatpak_nc.so');
  }

  static const _searchPaths = [
    // CMake build directory (from repo root)
    'build/libflatpak_nc.so',
    'native/build/libflatpak_nc.so',
    // Flutter plugin locations
    'linux/shared/libflatpak_nc.so',
  ];
}
