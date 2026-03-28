cmake_minimum_required(VERSION 3.22)
project(flatpak_nc CXX C)

set(CMAKE_CXX_STANDARD  23)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# ── Dependencies ──────────────────────────────────────────────────────────
# Only libflatpak and GLib are required. No D-Bus client library is needed;
# libflatpak handles SystemHelper communication and polkit internally.
find_package(PkgConfig REQUIRED)
pkg_check_modules(FLATPAK  REQUIRED IMPORTED_TARGET flatpak)
pkg_check_modules(GLIB     REQUIRED IMPORTED_TARGET glib-2.0)

# ── CMake modules ─────────────────────────────────────────────────────────
include(cmake/Sanitizers.cmake)
include(cmake/ClangTidy.cmake)
include(cmake/ClangFormat.cmake)
include(cmake/Coverage.cmake)

# ── dart_api_dl — compile as plain C ─────────────────────────────────────
add_library(dart_api_dl OBJECT src/dart_api_dl.c)
target_include_directories(dart_api_dl PUBLIC include)

# ── Main shared library ───────────────────────────────────────────────────
add_library(flatpak_nc SHARED
    src/flatpak_bridge.cpp
    src/transaction_bridge.cpp    # FlatpakTransaction GObject signals → Dart
    src/installation_reader.cpp   # All read-only libflatpak queries
    src/user_remote_bridge.cpp    # Remote CRUD for user installations
    $<TARGET_OBJECTS:dart_api_dl>
)

target_include_directories(flatpak_nc PRIVATE include)

target_link_libraries(flatpak_nc
    PRIVATE
        PkgConfig::FLATPAK   # links libflatpak, which pulls in GLib, GObject
        pthread
)

set_target_properties(flatpak_nc PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON
    OUTPUT_NAME "flatpak_nc"
)

apply_sanitizers(flatpak_nc)
apply_clang_tidy(flatpak_nc)

if(BUILD_TESTING)
    enable_testing()
    add_subdirectory(test)
endif()

if(ENABLE_COVERAGE)
    enable_coverage(flatpak_nc)
endif()

add_clang_format_targets()
