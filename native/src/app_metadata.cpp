// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Joel Winarske

#include "app_metadata.h"

#include <cstring>

bool metadata_requests_socket(GKeyFile* kf, const char* socket_name) {
    if (!kf || !socket_name) {
        return false;
    }
    g_auto(GStrv) sockets = g_key_file_get_string_list(kf, "Context", "sockets", nullptr, nullptr);
    if (!sockets) {
        return false;
    }
    for (gsize i = 0; sockets[i]; i++) {
        const char* entry = g_strstrip(sockets[i]);
        if (*entry == '!') {
            continue;  // explicitly withheld, not requested
        }
        if (std::strcmp(entry, socket_name) == 0) {
            return true;
        }
    }
    return false;
}

std::vector<RequiredExtension> required_extensions(GKeyFile* kf, const char* app_branch) {
    std::vector<RequiredExtension> out;
    if (!kf) {
        return out;
    }
    static constexpr const char kPrefix[] = "Extension ";
    static constexpr gsize kPrefixLen = sizeof(kPrefix) - 1;

    g_auto(GStrv) groups = g_key_file_get_groups(kf, nullptr);
    for (gsize i = 0; groups && groups[i]; i++) {
        const char* group = groups[i];
        if (std::strncmp(group, kPrefix, kPrefixLen) != 0) {
            continue;
        }
        const char* ext_id = group + kPrefixLen;
        if (!*ext_id) {
            continue;  // "Extension " with no id names nothing installable
        }
        if (g_key_file_get_boolean(kf, group, "no-autodownload", nullptr)) {
            continue;
        }
        if (g_key_file_get_boolean(kf, group, "subdirectories", nullptr)) {
            continue;
        }

        RequiredExtension ext;
        ext.id = ext_id;
        g_auto(GStrv) versions =
            g_key_file_get_string_list(kf, group, "versions", nullptr, nullptr);
        for (gsize v = 0; versions && versions[v]; v++) {
            if (*versions[v]) {
                ext.branches.emplace_back(versions[v]);
            }
        }
        if (ext.branches.empty()) {
            g_autofree char* version = g_key_file_get_string(kf, group, "version", nullptr);
            ext.branches.emplace_back((version && *version) ? version
                                                            : (app_branch ? app_branch : ""));
        }
        out.push_back(std::move(ext));
    }
    return out;
}
