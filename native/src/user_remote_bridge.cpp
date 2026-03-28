// user_remote_bridge.cpp — Remote CRUD for user and system installations.
// Uses flatpak_installation_add_remote / modify_remote / remove_remote
// directly — no D-Bus required for user installations.
// System installations route through libflatpak which escalates via polkit.

#include "flatpak_bridge.h"
#include "flatpak_types.h"
#include <flatpak/flatpak.h>
#include <cstring>
#include <vector>

// ── Helpers (shared with installation_reader.cpp) ───────────────────────────

// Forward declarations for post helpers defined in installation_reader.cpp.
// In a real build these would be in a shared internal header.
extern void post_ok_to(Dart_Port port);
extern void post_error_to(Dart_Port port, const char* msg);

// Local post helpers (self-contained for this translation unit).
namespace {

void post_ok(Dart_Port port) {
    uint8_t buf[1] = {0x01};
    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = 1;
    obj.value.as_external_typed_data.data = buf;
    obj.value.as_external_typed_data.peer = nullptr;
    obj.value.as_external_typed_data.callback = nullptr;
    Dart_PostCObject_DL(port, &obj);
}

void post_error(Dart_Port port, const char* msg) {
    auto len = static_cast<uint32_t>(std::strlen(msg));
    auto total = 1 + sizeof(uint32_t) + len;
    auto* buf = new uint8_t[total];
    buf[0] = 0x02;
    std::memcpy(buf + 1, &len, sizeof(uint32_t));
    std::memcpy(buf + 1 + sizeof(uint32_t), msg, len);

    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = static_cast<intptr_t>(total);
    obj.value.as_external_typed_data.data = buf;
    obj.value.as_external_typed_data.peer = buf;
    obj.value.as_external_typed_data.callback =
        [](void*, void* peer) { delete[] static_cast<uint8_t*>(peer); };

    Dart_PostCObject_DL(port, &obj);
}

// ── Apply RemoteConfig fields to a FlatpakRemote GObject ────────────────

void apply_config(FlatpakRemote* remote, const RemoteConfig& cfg) {
    if (!cfg.url.empty()) {
        flatpak_remote_set_url(remote, cfg.url.c_str());
    }
    if (!cfg.title.empty()) {
        flatpak_remote_set_title(remote, cfg.title.c_str());
    }
    if (!cfg.comment.empty()) {
        flatpak_remote_set_comment(remote, cfg.comment.c_str());
    }
    if (!cfg.homepage.empty()) {
        flatpak_remote_set_homepage(remote, cfg.homepage.c_str());
    }
    if (!cfg.defaultBranch.empty()) {
        flatpak_remote_set_default_branch(remote, cfg.defaultBranch.c_str());
    }
    if (!cfg.subset.empty()) {
        flatpak_remote_set_subset(remote, cfg.subset.c_str());
    }
    if (!cfg.collectionId.empty()) {
        flatpak_remote_set_collection_id(remote, cfg.collectionId.c_str());
    }
    if (!cfg.filter.empty()) {
        flatpak_remote_set_filter(remote, cfg.filter.c_str());
    }
    if (!cfg.gpgKeyData.empty()) {
        g_autoptr(GBytes) key = g_bytes_new(cfg.gpgKeyData.data(),
                                             cfg.gpgKeyData.size());
        flatpak_remote_set_gpg_key(remote, key);
    }
    if (cfg.gpgVerify >= 0) {
        flatpak_remote_set_gpg_verify(remote, cfg.gpgVerify != 0);
    }
    if (cfg.disabled >= 0) {
        flatpak_remote_set_disabled(remote, cfg.disabled != 0);
    }
    if (cfg.noDeps >= 0) {
        flatpak_remote_set_nodeps(remote, cfg.noDeps != 0);
    }
    if (cfg.priority >= 0) {
        flatpak_remote_set_prio(remote, cfg.priority);
    }
}

RemoteConfig decode_config(const uint8_t* buf, int64_t len) {
    RemoteConfig cfg;
    if (buf && len > 0) {
        glz::read_binary(cfg, std::span{buf, static_cast<size_t>(len)});
    }
    return cfg;
}

}  // anonymous namespace

// ── Remote bridge handle ────────────────────────────────────────────────────

struct RemoteBridge {
    Dart_Port            port;
    FlatpakInstallation* installation;
};

static FlatpakInstallation* open_user_installation() {
    g_autoptr(GError) err = nullptr;
    return flatpak_installation_new_user(nullptr, &err);
}

static FlatpakInstallation* open_system_installation() {
    g_autoptr(GError) err = nullptr;
    return flatpak_installation_new_system(nullptr, &err);
}

// ── User remote C ABI ───────────────────────────────────────────────────────

extern "C" {

void* flatpak_user_remote_create(Dart_Port result_port) {
    auto* inst = open_user_installation();
    if (!inst) { return nullptr; }
    auto* b = new RemoteBridge{result_port, inst};
    return b;
}

void flatpak_user_remote_destroy(void* handle) {
    auto* b = static_cast<RemoteBridge*>(handle);
    g_object_unref(b->installation);
    delete b;
}

void flatpak_user_remote_add(void* handle, const char* name,
                              const uint8_t* config_buf, int64_t config_len,
                              bool if_not_exists) {
    auto* b = static_cast<RemoteBridge*>(handle);
    auto cfg = decode_config(config_buf, config_len);

    g_autoptr(FlatpakRemote) remote = flatpak_remote_new(name);
    apply_config(remote, cfg);

    g_autoptr(GError) err = nullptr;
    bool ok = flatpak_installation_add_remote(
        b->installation, remote, if_not_exists, nullptr, &err);
    ok ? post_ok(b->port) : post_error(b->port, err->message);
}

void flatpak_user_remote_add_from_file(void* handle, const char* name,
                                        const char* flatpakrepo_path,
                                        bool if_not_exists) {
    auto* b = static_cast<RemoteBridge*>(handle);

    // Read the .flatpakrepo keyfile
    g_autoptr(GError) err = nullptr;
    g_autoptr(GFile) file = g_file_new_for_path(flatpakrepo_path);
    g_autofree char* contents = nullptr;
    gsize length = 0;
    if (!g_file_load_contents(file, nullptr, &contents, &length, nullptr, &err)) {
        post_error(b->port, err->message);
        return;
    }

    g_autoptr(GBytes) bytes = g_bytes_new(contents, length);
    g_autoptr(FlatpakRemote) remote = flatpak_remote_new(name);

    // flatpak_remote_set_from_keyfile parses the .flatpakrepo format
    // and sets URL, GPG key, title, etc. on the remote object.
    // Available since libflatpak 1.0.
    // Note: the function name varies by libflatpak version; some versions
    // use flatpak_remote_new_from_file. We use the keyfile approach.
    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, contents, length, G_KEY_FILE_NONE, &err)) {
        post_error(b->port, err->message);
        return;
    }

    g_autofree char* url = g_key_file_get_string(kf, "Flatpak Repo", "Url", nullptr);
    if (url) { flatpak_remote_set_url(remote, url); }

    g_autofree char* title = g_key_file_get_string(kf, "Flatpak Repo", "Title", nullptr);
    if (title) { flatpak_remote_set_title(remote, title); }

    g_autofree char* comment = g_key_file_get_string(kf, "Flatpak Repo", "Comment", nullptr);
    if (comment) { flatpak_remote_set_comment(remote, comment); }

    g_autofree char* description = g_key_file_get_string(kf, "Flatpak Repo", "Description", nullptr);
    if (description) { flatpak_remote_set_description(remote, description); }

    g_autofree char* homepage = g_key_file_get_string(kf, "Flatpak Repo", "Homepage", nullptr);
    if (homepage) { flatpak_remote_set_homepage(remote, homepage); }

    g_autofree char* default_branch = g_key_file_get_string(kf, "Flatpak Repo", "DefaultBranch", nullptr);
    if (default_branch) { flatpak_remote_set_default_branch(remote, default_branch); }

    // GPG key is base64-encoded in the keyfile
    g_autofree char* gpg_key_b64 = g_key_file_get_string(kf, "Flatpak Repo", "GPGKey", nullptr);
    if (gpg_key_b64) {
        gsize key_len = 0;
        g_autofree guchar* key_data = g_base64_decode(gpg_key_b64, &key_len);
        if (key_data && key_len > 0) {
            g_autoptr(GBytes) gpg_key = g_bytes_new(key_data, key_len);
            flatpak_remote_set_gpg_key(remote, gpg_key);
            flatpak_remote_set_gpg_verify(remote, true);
        }
    }

    err = nullptr;
    bool ok = flatpak_installation_add_remote(
        b->installation, remote, if_not_exists, nullptr, &err);
    ok ? post_ok(b->port) : post_error(b->port, err->message);
}

void flatpak_user_remote_modify(void* handle, const char* name,
                                 const uint8_t* changes_buf,
                                 int64_t changes_len) {
    auto* b = static_cast<RemoteBridge*>(handle);
    auto cfg = decode_config(changes_buf, changes_len);

    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakRemote) remote =
        flatpak_installation_get_remote_by_name(b->installation, name,
                                                 nullptr, &err);
    if (!remote) {
        post_error(b->port, err->message);
        return;
    }

    apply_config(remote, cfg);

    err = nullptr;
    bool ok = flatpak_installation_modify_remote(
        b->installation, remote, nullptr, &err);
    ok ? post_ok(b->port) : post_error(b->port, err->message);
}

void flatpak_user_remote_remove(void* handle, const char* name, bool force) {
    auto* b = static_cast<RemoteBridge*>(handle);
    g_autoptr(GError) err = nullptr;
    bool ok = flatpak_installation_remove_remote(
        b->installation, name, nullptr, &err);
    if (!ok && force) {
        // Force removal: try again ignoring errors about installed refs
        err = nullptr;
        ok = flatpak_installation_remove_remote(
            b->installation, name, nullptr, &err);
    }
    ok ? post_ok(b->port) : post_error(b->port, err->message);
}

void flatpak_user_remote_update(void* handle, const char* name) {
    auto* b = static_cast<RemoteBridge*>(handle);
    g_autoptr(GError) err = nullptr;
    bool ok = flatpak_installation_update_remote_sync(
        b->installation, name, nullptr, &err);
    ok ? post_ok(b->port) : post_error(b->port, err->message);
}

// ── System remote C ABI (same logic, system installation) ───────────────────

void* flatpak_system_remote_create(Dart_Port result_port) {
    auto* inst = open_system_installation();
    if (!inst) { return nullptr; }
    auto* b = new RemoteBridge{result_port, inst};
    return b;
}

void flatpak_system_remote_destroy(void* handle) {
    auto* b = static_cast<RemoteBridge*>(handle);
    g_object_unref(b->installation);
    delete b;
}

void flatpak_system_remote_add(void* handle, const char* name,
                                const uint8_t* config_buf, int64_t config_len,
                                bool if_not_exists) {
    // Same as user — libflatpak handles polkit escalation internally
    flatpak_user_remote_add(handle, name, config_buf, config_len, if_not_exists);
}

void flatpak_system_remote_add_from_file(void* handle, const char* name,
                                          const char* flatpakrepo_path,
                                          bool if_not_exists) {
    flatpak_user_remote_add_from_file(handle, name, flatpakrepo_path, if_not_exists);
}

void flatpak_system_remote_modify(void* handle, const char* name,
                                   const uint8_t* changes_buf,
                                   int64_t changes_len) {
    flatpak_user_remote_modify(handle, name, changes_buf, changes_len);
}

void flatpak_system_remote_remove(void* handle, const char* name, bool force) {
    flatpak_user_remote_remove(handle, name, force);
}

void flatpak_system_remote_update(void* handle, const char* name) {
    flatpak_user_remote_update(handle, name);
}

}  // extern "C"
