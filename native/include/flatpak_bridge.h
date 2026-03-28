// C ABI exported to Dart FFI — stub for PR 1.
// Full declarations added in PR 3–6.

#pragma once
#include "dart_api_dl.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void flatpak_bridge_init(void* dart_api_dl_data);

#ifdef __cplusplus
}
#endif
