// installation_reader.cpp — All read-only libflatpak queries.
// Posts glaze-encoded results to Dart via Dart_PostCObject_DL.

#include "installation_reader.h"
#include "flatpak_bridge.h"
#include <cstring>

// ── Helpers ─────────────────────────────────────────────────────────────────

static void post_glaze_bytes(Dart_Port port, uint8_t discriminator,
                             const uint8_t* data, size_t len) {
    // Allocate discriminator + payload
    auto* buf = new uint8_t[1 + len];
    buf[0] = discriminator;
    std::memcpy(buf + 1, data, len);

    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = static_cast<intptr_t>(1 + len);
    obj.value.as_external_typed_data.data = buf;
    obj.value.as_external_typed_data.peer = buf;
    obj.value.as_external_typed_data.callback =
        [](void*, void* peer) { delete[] static_cast<uint8_t*>(peer); };

    Dart_PostCObject_DL(port, &obj);
}

template <typename T>
static void post_glaze(Dart_Port port, uint8_t discriminator, const T& value) {
    std::vector<uint8_t> buf;
    glz::write_binary(value, buf);
    post_glaze_bytes(port, discriminator, buf.data(), buf.size());
}

static void post_sentinel(Dart_Port port) {
    uint8_t byte = 0xFF;
    post_glaze_bytes(port, 0xFF, nullptr, 0);
    (void)byte;
}

static void post_ok(Dart_Port port) {
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

static void post_error(Dart_Port port, const char* msg) {
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

static const char* safe_str(const char* s) { return s ? s : ""; }

static const char* op_kind_str(FlatpakTransactionOperationType type) {
    switch (type) {
        case FLATPAK_TRANSACTION_OPERATION_INSTALL:        return "install";
        case FLATPAK_TRANSACTION_OPERATION_UPDATE:         return "update";
        case FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE: return "install";
        case FLATPAK_TRANSACTION_OPERATION_UNINSTALL:      return "uninstall";
        default:                                           return "unknown";
    }
}

// ── InstallationReader ──────────────────────────────────────────────────────

InstallationReader::InstallationReader(Dart_Port port,
                                       FlatpakInstallation* inst)
    : port_(port), installation_(static_cast<FlatpakInstallation*>(
          g_object_ref(inst))) {}

InstallationReader::~InstallationReader() {
    g_object_unref(installation_);
}

void InstallationReader::list_apps(bool include_runtimes) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs(
        installation_, nullptr, &err);
    if (!refs) {
        post_error(port_, err->message);
        return;
    }
    for (guint i = 0; i < refs->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(refs->pdata[i]);
        if (!include_runtimes &&
            flatpak_ref_get_kind(FLATPAK_REF(iref)) != FLATPAK_REF_KIND_APP) {
            continue;
        }

        InstalledApp app;
        app.ref.kind = flatpak_ref_get_kind(FLATPAK_REF(iref))
                           == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        app.ref.name         = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
        app.ref.arch         = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
        app.ref.branch       = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
        app.ref.commit       = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
        app.ref.collectionId = safe_str(flatpak_ref_get_collection_id(FLATPAK_REF(iref)));
        app.origin           = safe_str(flatpak_installed_ref_get_origin(iref));
        app.latestCommit     = safe_str(flatpak_installed_ref_get_latest_commit(iref));
        app.installedPath    = safe_str(flatpak_installed_ref_get_deploy_dir(iref));
        app.installedSize    = flatpak_installed_ref_get_installed_size(iref);
        app.isCurrentArch    = flatpak_installed_ref_get_is_current(iref);
        app.endOfLife        = flatpak_installed_ref_get_eol(iref) != nullptr;
        app.endOfLifeRebase  = safe_str(flatpak_installed_ref_get_eol_rebase(iref));
        app.appDataName      = safe_str(flatpak_installed_ref_get_appdata_name(iref));
        app.appDataSummary   = safe_str(flatpak_installed_ref_get_appdata_summary(iref));
        app.appDataVersion   = safe_str(flatpak_installed_ref_get_appdata_version(iref));
        // appDataIcon is not available via libflatpak C API directly

        post_glaze(port_, 0x01, app);
    }
    post_sentinel(port_);
}

void InstallationReader::list_remotes() {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(
        installation_, nullptr, &err);
    if (!remotes) {
        post_error(port_, err->message);
        return;
    }
    for (guint i = 0; i < remotes->len; i++) {
        auto* remote = static_cast<FlatpakRemote*>(remotes->pdata[i]);

        FlatpakRemoteInfo info;
        info.name          = safe_str(flatpak_remote_get_name(remote));
        info.url           = safe_str(flatpak_remote_get_url(remote));
        info.title         = safe_str(flatpak_remote_get_title(remote));
        info.comment       = safe_str(flatpak_remote_get_comment(remote));
        info.description   = safe_str(flatpak_remote_get_description(remote));
        info.homepage      = safe_str(flatpak_remote_get_homepage(remote));
        info.defaultBranch = safe_str(flatpak_remote_get_default_branch(remote));
        info.subset        = safe_str(flatpak_remote_get_subset(remote));
        info.collectionId  = safe_str(flatpak_remote_get_collection_id(remote));
        info.filter        = safe_str(flatpak_remote_get_filter(remote));
        info.disabled      = flatpak_remote_get_disabled(remote);
        info.gpgVerify     = flatpak_remote_get_gpg_verify(remote);
        info.noDeps        = flatpak_remote_get_nodeps(remote);
        info.priority      = flatpak_remote_get_prio(remote);
        info.remoteType    = static_cast<int32_t>(
            flatpak_remote_get_remote_type(remote));

        post_glaze(port_, 0x01, info);
    }
    post_sentinel(port_);
}

void InstallationReader::get_remote_info(const char* name) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakRemote) remote =
        flatpak_installation_get_remote_by_name(installation_, name,
                                                 nullptr, &err);
    if (!remote) {
        post_error(port_, err->message);
        return;
    }

    FlatpakRemoteInfo info;
    info.name          = safe_str(flatpak_remote_get_name(remote));
    info.url           = safe_str(flatpak_remote_get_url(remote));
    info.title         = safe_str(flatpak_remote_get_title(remote));
    info.comment       = safe_str(flatpak_remote_get_comment(remote));
    info.description   = safe_str(flatpak_remote_get_description(remote));
    info.homepage      = safe_str(flatpak_remote_get_homepage(remote));
    info.defaultBranch = safe_str(flatpak_remote_get_default_branch(remote));
    info.subset        = safe_str(flatpak_remote_get_subset(remote));
    info.collectionId  = safe_str(flatpak_remote_get_collection_id(remote));
    info.filter        = safe_str(flatpak_remote_get_filter(remote));
    info.disabled      = flatpak_remote_get_disabled(remote);
    info.gpgVerify     = flatpak_remote_get_gpg_verify(remote);
    info.noDeps        = flatpak_remote_get_nodeps(remote);
    info.priority      = flatpak_remote_get_prio(remote);
    info.remoteType    = static_cast<int32_t>(
        flatpak_remote_get_remote_type(remote));

    post_glaze(port_, 0x01, info);
    post_sentinel(port_);
}

void InstallationReader::list_remote_apps(const char* name,
                                           const char* arch,
                                           bool include_runtimes) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs = flatpak_installation_list_remote_refs_sync(
        installation_, name, nullptr, &err);
    if (!refs) {
        post_error(port_, err->message);
        return;
    }
    for (guint i = 0; i < refs->len; i++) {
        auto* fref = static_cast<FlatpakRemoteRef*>(refs->pdata[i]);
        if (!include_runtimes &&
            flatpak_ref_get_kind(FLATPAK_REF(fref)) != FLATPAK_REF_KIND_APP) {
            continue;
        }
        if (arch && *arch &&
            g_strcmp0(flatpak_ref_get_arch(FLATPAK_REF(fref)), arch) != 0) {
            continue;
        }
        FlatpakRef ref;
        ref.kind         = flatpak_ref_get_kind(FLATPAK_REF(fref))
                               == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        ref.name         = safe_str(flatpak_ref_get_name(FLATPAK_REF(fref)));
        ref.arch         = safe_str(flatpak_ref_get_arch(FLATPAK_REF(fref)));
        ref.branch       = safe_str(flatpak_ref_get_branch(FLATPAK_REF(fref)));
        ref.commit       = safe_str(flatpak_ref_get_commit(FLATPAK_REF(fref)));
        ref.collectionId = safe_str(
            flatpak_remote_ref_get_collection_id(fref));
        post_glaze(port_, 0x01, ref);
    }
    post_sentinel(port_);
}

void InstallationReader::get_app_info(const char* app_id, const char* arch,
                                       const char* branch) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref =
        flatpak_installation_get_installed_ref(
            installation_, FLATPAK_REF_KIND_APP, app_id,
            (arch && *arch) ? arch : nullptr,
            (branch && *branch) ? branch : nullptr,
            nullptr, &err);
    if (!iref) {
        post_error(port_, err->message);
        return;
    }

    InstalledApp app;
    app.ref.kind         = "app";
    app.ref.name         = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
    app.ref.arch         = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
    app.ref.branch       = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
    app.ref.commit       = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
    app.ref.collectionId = safe_str(flatpak_ref_get_collection_id(FLATPAK_REF(iref)));
    app.origin           = safe_str(flatpak_installed_ref_get_origin(iref));
    app.latestCommit     = safe_str(flatpak_installed_ref_get_latest_commit(iref));
    app.installedPath    = safe_str(flatpak_installed_ref_get_deploy_dir(iref));
    app.installedSize    = flatpak_installed_ref_get_installed_size(iref);
    app.isCurrentArch    = flatpak_installed_ref_get_is_current(iref);
    app.endOfLife        = flatpak_installed_ref_get_eol(iref) != nullptr;
    app.endOfLifeRebase  = safe_str(flatpak_installed_ref_get_eol_rebase(iref));
    app.appDataName      = safe_str(flatpak_installed_ref_get_appdata_name(iref));
    app.appDataSummary   = safe_str(flatpak_installed_ref_get_appdata_summary(iref));
    app.appDataVersion   = safe_str(flatpak_installed_ref_get_appdata_version(iref));

    post_glaze(port_, 0x01, app);
    post_sentinel(port_);
}

void InstallationReader::get_permissions(const char* app_id) {
    // Permission overrides are stored in key-files, not via libflatpak query API.
    // Read from ~/.local/share/flatpak/overrides/<app_id> or
    // /var/lib/flatpak/overrides/<app_id>.
    // For now, post an empty sentinel — full implementation in PR 6.
    (void)app_id;
    post_sentinel(port_);
}

void InstallationReader::check_updates() {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) updates =
        flatpak_installation_list_installed_refs_for_update(
            installation_, nullptr, &err);
    if (!updates) {
        post_error(port_, err->message);
        return;
    }
    for (guint i = 0; i < updates->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(updates->pdata[i]);
        FlatpakRef ref;
        ref.kind   = flatpak_ref_get_kind(FLATPAK_REF(iref))
                         == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        ref.name   = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
        ref.arch   = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
        ref.branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
        ref.commit = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
        post_glaze(port_, 0x01, ref);
    }
    post_sentinel(port_);
}

// ── C ABI wrappers ──────────────────────────────────────────────────────────

static FlatpakInstallation* open_installation(const char* name) {
    g_autoptr(GError) err = nullptr;
    if (g_strcmp0(name, "user") == 0) {
        return flatpak_installation_new_user(nullptr, &err);
    }
    if (g_strcmp0(name, "system") == 0) {
        return flatpak_installation_new_system(nullptr, &err);
    }
    // Custom path
    g_autoptr(GFile) path = g_file_new_for_path(name);
    return flatpak_installation_new_for_path(path, false, nullptr, &err);
}

extern "C" {

void* flatpak_reader_create(Dart_Port port, const char* installation) {
    auto* inst = open_installation(installation);
    if (!inst) { return nullptr; }
    return new InstallationReader(port, inst);
}

void flatpak_reader_destroy(void* handle) {
    delete static_cast<InstallationReader*>(handle);
}

void flatpak_reader_list_apps(void* handle, bool include_runtimes) {
    static_cast<InstallationReader*>(handle)->list_apps(include_runtimes);
}

void flatpak_reader_list_remotes(void* handle) {
    static_cast<InstallationReader*>(handle)->list_remotes();
}

void flatpak_reader_get_remote_info(void* handle, const char* name) {
    static_cast<InstallationReader*>(handle)->get_remote_info(name);
}

void flatpak_reader_list_remote_apps(void* handle, const char* name,
                                      const char* arch,
                                      bool include_runtimes) {
    static_cast<InstallationReader*>(handle)->list_remote_apps(
        name, arch, include_runtimes);
}

void flatpak_reader_get_app_info(void* handle, const char* app_id,
                                  const char* arch, const char* branch) {
    static_cast<InstallationReader*>(handle)->get_app_info(
        app_id, arch, branch);
}

void flatpak_reader_get_permissions(void* handle, const char* app_id) {
    static_cast<InstallationReader*>(handle)->get_permissions(app_id);
}

void flatpak_reader_check_updates(void* handle) {
    static_cast<InstallationReader*>(handle)->check_updates();
}

}  // extern "C"
