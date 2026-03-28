// flatpak_bridge.cpp — C ABI entry points + init.
// Stub for PR 1; full implementation added in PR 3–6.

#include "flatpak_bridge.h"

void flatpak_bridge_init(void* dart_api_dl_data) {
    // TODO(PR 3): Dart_InitializeApiDL(dart_api_dl_data);
    (void)dart_api_dl_data;
}
