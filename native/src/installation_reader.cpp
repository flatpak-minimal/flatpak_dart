// installation_reader.cpp — All read-only libflatpak queries.
// Posts glaze-encoded results to Dart via Dart_PostCObject_DL.
// Reader is created once per installation; port passed per-call.

#include "installation_reader.h"

#include <poll.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstring>
#include <string>

#include "flatpak_bridge.h"
#include "flatpak_post.h"

// ── Helpers ─────────────────────────────────────────────────────────────────

template <typename T>
static void post_glaze(Dart_Port port, uint8_t discriminator, const T& value) {
    auto payload = glz::write_binary(value);
    flatpak_nc::post_framed(port, discriminator, reinterpret_cast<const uint8_t*>(payload.data()),
                            payload.size());
}

static void post_sentinel(Dart_Port port) {
    const uint8_t buf[1] = {0xFF};
    flatpak_nc::post_copy(port, buf, 1);
}

static void post_error(Dart_Port port, const char* msg) {
    flatpak_nc::post_framed_error(port, 0x02, msg);
}

static void post_launch_error(Dart_Port port, const char* msg) {
    flatpak_nc::post_framed_error(port, 0x03, msg);
}

static const char* safe_str(const char* s) {
    return s ? s : "";
}

static gpointer reap_thread(gpointer data) {
    auto pid = static_cast<GPid>(GPOINTER_TO_INT(data));
    int status = 0;
    waitpid(pid, &status, 0);
    return nullptr;
}

static void reap_async(GPid pid) {
    GThread* t = g_thread_new("flatpak-reap", reap_thread, GINT_TO_POINTER(pid));
    g_thread_unref(t);
}

// InstallationReader

InstallationReader::InstallationReader(FlatpakInstallation* inst)
    : installation_(static_cast<FlatpakInstallation*>(g_object_ref(inst))),
      launch_work_guard_(asio::make_work_guard(launch_io_)),
      launch_thread_([this] { launch_io_.run(); }) {
}

InstallationReader::~InstallationReader() {
    launch_io_.stop();
    if (launch_thread_.joinable()) {
        launch_thread_.join();
    }
    g_object_unref(installation_);
}

void InstallationReader::list_apps(Dart_Port port, bool include_runtimes) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs =
        flatpak_installation_list_installed_refs(installation_, nullptr, &err);
    if (!refs) {
        post_error(port, err->message);
        return;
    }
    for (guint i = 0; i < refs->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(refs->pdata[i]);
        if (!include_runtimes && flatpak_ref_get_kind(FLATPAK_REF(iref)) != FLATPAK_REF_KIND_APP) {
            continue;
        }

        InstalledApp app;
        app.ref.kind =
            flatpak_ref_get_kind(FLATPAK_REF(iref)) == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        app.ref.name = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
        app.ref.arch = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
        app.ref.branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
        app.ref.commit = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
        app.ref.collectionId = safe_str(flatpak_ref_get_collection_id(FLATPAK_REF(iref)));
        app.origin = safe_str(flatpak_installed_ref_get_origin(iref));
        app.latestCommit = safe_str(flatpak_installed_ref_get_latest_commit(iref));
        app.installedPath = safe_str(flatpak_installed_ref_get_deploy_dir(iref));
        app.installedSize = flatpak_installed_ref_get_installed_size(iref);
        app.isCurrentArch = flatpak_installed_ref_get_is_current(iref);
        app.endOfLife = flatpak_installed_ref_get_eol(iref) != nullptr;
        app.endOfLifeRebase = safe_str(flatpak_installed_ref_get_eol_rebase(iref));
        app.appDataName = safe_str(flatpak_installed_ref_get_appdata_name(iref));
        app.appDataSummary = safe_str(flatpak_installed_ref_get_appdata_summary(iref));
        app.appDataVersion = safe_str(flatpak_installed_ref_get_appdata_version(iref));

        post_glaze(port, 0x01, app);
    }
    post_sentinel(port);
}

void InstallationReader::list_remotes(Dart_Port port) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) remotes = flatpak_installation_list_remotes(installation_, nullptr, &err);
    if (!remotes) {
        post_error(port, err->message);
        return;
    }
    for (guint i = 0; i < remotes->len; i++) {
        auto* remote = static_cast<FlatpakRemote*>(remotes->pdata[i]);

        FlatpakRemoteInfo info;
        info.name = safe_str(flatpak_remote_get_name(remote));
        info.url = safe_str(flatpak_remote_get_url(remote));
        info.title = safe_str(flatpak_remote_get_title(remote));
        info.comment = safe_str(flatpak_remote_get_comment(remote));
        info.description = safe_str(flatpak_remote_get_description(remote));
        info.homepage = safe_str(flatpak_remote_get_homepage(remote));
        info.defaultBranch = safe_str(flatpak_remote_get_default_branch(remote));
        info.subset = "";  // subset API not available in all libflatpak versions
        info.collectionId = safe_str(flatpak_remote_get_collection_id(remote));
        info.filter = safe_str(flatpak_remote_get_filter(remote));
        info.disabled = flatpak_remote_get_disabled(remote);
        info.gpgVerify = flatpak_remote_get_gpg_verify(remote);
        info.noDeps = flatpak_remote_get_nodeps(remote);
        info.priority = flatpak_remote_get_prio(remote);
        info.remoteType = static_cast<int32_t>(flatpak_remote_get_remote_type(remote));

        post_glaze(port, 0x01, info);
    }
    post_sentinel(port);
}

void InstallationReader::get_remote_info(Dart_Port port, const char* name) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakRemote) remote =
        flatpak_installation_get_remote_by_name(installation_, name, nullptr, &err);
    if (!remote) {
        post_error(port, err->message);
        return;
    }

    FlatpakRemoteInfo info;
    info.name = safe_str(flatpak_remote_get_name(remote));
    info.url = safe_str(flatpak_remote_get_url(remote));
    info.title = safe_str(flatpak_remote_get_title(remote));
    info.comment = safe_str(flatpak_remote_get_comment(remote));
    info.description = safe_str(flatpak_remote_get_description(remote));
    info.homepage = safe_str(flatpak_remote_get_homepage(remote));
    info.defaultBranch = safe_str(flatpak_remote_get_default_branch(remote));
    info.subset = "";  // subset API not available in all libflatpak versions
    info.collectionId = safe_str(flatpak_remote_get_collection_id(remote));
    info.filter = safe_str(flatpak_remote_get_filter(remote));
    info.disabled = flatpak_remote_get_disabled(remote);
    info.gpgVerify = flatpak_remote_get_gpg_verify(remote);
    info.noDeps = flatpak_remote_get_nodeps(remote);
    info.priority = flatpak_remote_get_prio(remote);
    info.remoteType = static_cast<int32_t>(flatpak_remote_get_remote_type(remote));

    post_glaze(port, 0x01, info);
    post_sentinel(port);
}

void InstallationReader::list_remote_apps(Dart_Port port, const char* name, const char* arch,
                                          bool include_runtimes) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs =
        flatpak_installation_list_remote_refs_sync(installation_, name, nullptr, &err);
    if (!refs) {
        post_error(port, err->message);
        return;
    }
    for (guint i = 0; i < refs->len; i++) {
        auto* fref = static_cast<FlatpakRemoteRef*>(refs->pdata[i]);
        if (!include_runtimes && flatpak_ref_get_kind(FLATPAK_REF(fref)) != FLATPAK_REF_KIND_APP) {
            continue;
        }
        if (arch && *arch && g_strcmp0(flatpak_ref_get_arch(FLATPAK_REF(fref)), arch) != 0) {
            continue;
        }
        FpRef ref;
        ref.kind =
            flatpak_ref_get_kind(FLATPAK_REF(fref)) == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        ref.name = safe_str(flatpak_ref_get_name(FLATPAK_REF(fref)));
        ref.arch = safe_str(flatpak_ref_get_arch(FLATPAK_REF(fref)));
        ref.branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(fref)));
        ref.commit = safe_str(flatpak_ref_get_commit(FLATPAK_REF(fref)));
        ref.collectionId = safe_str(flatpak_ref_get_collection_id(FLATPAK_REF(fref)));
        post_glaze(port, 0x01, ref);
    }
    post_sentinel(port);
}

void InstallationReader::get_app_info(Dart_Port port, const char* app_id, const char* arch,
                                      const char* branch) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref = flatpak_installation_get_installed_ref(
        installation_, FLATPAK_REF_KIND_APP, app_id, (arch && *arch) ? arch : nullptr,
        (branch && *branch) ? branch : nullptr, nullptr, &err);
    if (!iref) {
        post_error(port, err->message);
        return;
    }

    InstalledApp app;
    app.ref.kind = "app";
    app.ref.name = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
    app.ref.arch = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
    app.ref.branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
    app.ref.commit = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
    app.ref.collectionId = safe_str(flatpak_ref_get_collection_id(FLATPAK_REF(iref)));
    app.origin = safe_str(flatpak_installed_ref_get_origin(iref));
    app.latestCommit = safe_str(flatpak_installed_ref_get_latest_commit(iref));
    app.installedPath = safe_str(flatpak_installed_ref_get_deploy_dir(iref));
    app.installedSize = flatpak_installed_ref_get_installed_size(iref);
    app.isCurrentArch = flatpak_installed_ref_get_is_current(iref);
    app.endOfLife = flatpak_installed_ref_get_eol(iref) != nullptr;
    app.endOfLifeRebase = safe_str(flatpak_installed_ref_get_eol_rebase(iref));
    app.appDataName = safe_str(flatpak_installed_ref_get_appdata_name(iref));
    app.appDataSummary = safe_str(flatpak_installed_ref_get_appdata_summary(iref));
    app.appDataVersion = safe_str(flatpak_installed_ref_get_appdata_version(iref));

    post_glaze(port, 0x01, app);
    post_sentinel(port);
}

void InstallationReader::get_permissions(Dart_Port port, const char* app_id) {
    (void)app_id;
    post_sentinel(port);
}

void InstallationReader::check_updates(Dart_Port port) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) updates =
        flatpak_installation_list_installed_refs_for_update(installation_, nullptr, &err);
    if (!updates) {
        post_error(port, err->message);
        return;
    }
    for (guint i = 0; i < updates->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(updates->pdata[i]);
        FpRef ref;
        ref.kind =
            flatpak_ref_get_kind(FLATPAK_REF(iref)) == FLATPAK_REF_KIND_APP ? "app" : "runtime";
        ref.name = safe_str(flatpak_ref_get_name(FLATPAK_REF(iref)));
        ref.arch = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
        ref.branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));
        ref.commit = safe_str(flatpak_ref_get_commit(FLATPAK_REF(iref)));
        post_glaze(port, 0x01, ref);
    }
    post_sentinel(port);
}

void InstallationReader::fetch_remote_metadata(Dart_Port port, const char* remote,
                                               const char* ref) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakRef) fref = flatpak_ref_parse(ref, &err);
    if (!fref) {
        post_error(port, err ? err->message : "invalid ref");
        return;
    }
    err = nullptr;
    g_autoptr(GBytes) bytes =
        flatpak_installation_fetch_remote_metadata_sync(installation_, remote, fref, nullptr, &err);
    if (!bytes) {
        post_error(port, err ? err->message : "failed to fetch metadata");
        return;
    }

    // Parse the metadata keyfile and extract permissions into a struct
    gsize len = 0;
    auto* data = static_cast<const char*>(g_bytes_get_data(bytes, &len));

    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, data, len, G_KEY_FILE_NONE, &err)) {
        post_error(port, err ? err->message : "failed to parse metadata");
        return;
    }

    // Build a FlatpakRemoteInfo-like struct to carry the permissions.
    // We reuse a simple string-based approach: encode as key=value pairs
    // from the [Context] section which contains the sandbox permissions.
    //
    // Sections of interest:
    //   [Context]        shared, sockets, devices, filesystems, persistent
    //   [Session Bus Policy]   bus-name=policy
    //   [System Bus Policy]    bus-name=policy
    //   [Environment]          VAR=value

    struct MetadataEntry {
        std::string section;
        std::string key;
        std::string value;
    };

    std::vector<MetadataEntry> entries;

    const char* sections[] = {"Context", "Session Bus Policy", "System Bus Policy", "Environment",
                              nullptr};
    for (const char** sp = sections; *sp; ++sp) {
        g_auto(GStrv) keys = g_key_file_get_keys(kf, *sp, nullptr, nullptr);
        if (!keys) {
            continue;
        }
        for (gsize i = 0; keys[i]; i++) {
            g_autofree char* val = g_key_file_get_string(kf, *sp, keys[i], nullptr);
            entries.push_back({*sp, keys[i], val ? val : ""});
        }
    }

    // Encode as glaze binary: vector of (section, key, value) triples
    // using a simple struct
    glz::Writer w;
    w.write<uint64_t>(entries.size());
    for (const auto& e : entries) {
        w.write(e.section);
        w.write(e.key);
        w.write(e.value);
    }
    flatpak_nc::post_framed(port, 0x01, reinterpret_cast<const uint8_t*>(w.buf.data()),
                            w.buf.size());
    post_sentinel(port);
}

static bool resolve_launch_target(FlatpakInstallation* installation, const char* app_id,
                                  const char* hint_arch, const char* hint_branch,
                                  std::string* out_arch, std::string* out_branch) {
    g_autoptr(GError) cerr = nullptr;
    g_autoptr(FlatpakInstalledRef) current =
        flatpak_installation_get_current_installed_app(installation, app_id, nullptr, &cerr);
    if (current) {
        const char* a = flatpak_ref_get_arch(FLATPAK_REF(current));
        const char* b = flatpak_ref_get_branch(FLATPAK_REF(current));
        bool arch_ok = !hint_arch || g_strcmp0(a, hint_arch) == 0;
        bool branch_ok = !hint_branch || g_strcmp0(b, hint_branch) == 0;
        if (arch_ok && branch_ok) {
            *out_arch = a;
            *out_branch = b;
            return true;
        }
    }

    const char* default_arch = flatpak_get_default_arch();
    g_autoptr(GError) lerr = nullptr;
    g_autoptr(GPtrArray) refs =
        flatpak_installation_list_installed_refs(installation, nullptr, &lerr);
    if (!refs) {
        return false;
    }
    bool found = false;
    for (guint i = 0; i < refs->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(refs->pdata[i]);
        if (flatpak_ref_get_kind(FLATPAK_REF(iref)) != FLATPAK_REF_KIND_APP) {
            continue;
        }
        if (g_strcmp0(flatpak_ref_get_name(FLATPAK_REF(iref)), app_id) != 0) {
            continue;
        }
        const char* a = flatpak_ref_get_arch(FLATPAK_REF(iref));
        const char* b = flatpak_ref_get_branch(FLATPAK_REF(iref));
        if (hint_arch && g_strcmp0(a, hint_arch) != 0) {
            continue;
        }
        if (hint_branch && g_strcmp0(b, hint_branch) != 0) {
            continue;
        }
        if (!found || (!hint_arch && g_strcmp0(a, default_arch) == 0)) {
            *out_arch = a;
            *out_branch = b;
            found = true;
        }
        if (g_strcmp0(a, default_arch) == 0) {
            break;  // can't do better than the default arch
        }
    }
    return found;
}

void InstallationReader::launch(Dart_Port port, const char* app_id, const char* arch,
                                const char* branch, const char* commit) {
    std::string appIdStr = safe_str(app_id);
    std::string archStr = safe_str(arch);
    std::string branchStr = safe_str(branch);
    std::string commitStr = safe_str(commit);
    asio::post(launch_io_, [this, port, appIdStr, archStr, branchStr, commitStr]() {
        launch_impl(port, appIdStr.c_str(), archStr.c_str(), branchStr.c_str(), commitStr.c_str());
    });
}

void InstallationReader::launch_impl(Dart_Port port, const char* app_id, const char* arch,
                                     const char* branch, const char* commit) {
    const char* use_arch = (arch && *arch) ? arch : nullptr;
    const char* use_branch = (branch && *branch) ? branch : nullptr;
    const char* use_commit = (commit && *commit) ? commit : nullptr;

    std::string resolved_arch;
    std::string resolved_branch;
    if (!use_arch || !use_branch) {
        if (!resolve_launch_target(installation_, app_id, use_arch, use_branch, &resolved_arch,
                                   &resolved_branch)) {
            post_error(port, "app not installed");
            return;
        }
        if (!use_arch) {
            use_arch = resolved_arch.c_str();
        }
        if (!use_branch) {
            use_branch = resolved_branch.c_str();
        }
    }

    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstance) instance = nullptr;

    gboolean ok = flatpak_installation_launch_full(installation_, FLATPAK_LAUNCH_FLAGS_DO_NOT_REAP,
                                                   app_id, use_arch, use_branch, use_commit,
                                                   &instance, nullptr, &err);
    if (!ok) {
        if (err && err->domain == FLATPAK_ERROR && err->code == FLATPAK_ERROR_NOT_INSTALLED) {
            post_error(port, err->message);
        } else {
            post_launch_error(port, err ? err->message : "launch failed");
        }
        return;
    }

    auto outer_pid = static_cast<GPid>(flatpak_instance_get_pid(instance));
    if (outer_pid > 0) {
        reap_async(outer_pid);
    }

    FpInstance info;
    info.appId = safe_str(flatpak_instance_get_app(instance));
    info.instanceId = safe_str(flatpak_instance_get_id(instance));
    info.arch = safe_str(flatpak_instance_get_arch(instance));
    info.branch = safe_str(flatpak_instance_get_branch(instance));
    info.commit = safe_str(flatpak_instance_get_commit(instance));
    info.pid = flatpak_instance_get_pid(instance);
    info.childPid = flatpak_instance_get_child_pid(instance);
    info.isRunning = flatpak_instance_is_running(instance);

    post_glaze(port, 0x01, info);
    post_sentinel(port);
}

// pidfd-based signalling: a pidfd refers to the exact process instance it was opened for, so we can
// send signals to it even if the PID has been recycled.
static int pidfd_open_compat(pid_t pid) {
    return static_cast<int>(syscall(SYS_pidfd_open, pid, 0));
}

static int pidfd_send_signal_compat(int pidfd, int sig) {
    return static_cast<int>(syscall(SYS_pidfd_send_signal, pidfd, sig, nullptr, 0));
}

// Grace period + SIGKILL escalation for stop(), on a detached background thread. We don't want to
// block the Dart thread waiting for the app to exit, and we don't want to leave a stray process if
// it ignores SIGTERM.
static gpointer stop_escalate_thread(gpointer data) {
    auto pidfd = GPOINTER_TO_INT(data);
    struct pollfd pfd = {.fd = pidfd, .events = POLLIN, .revents = 0};
    int ret = poll(&pfd, 1, 1500);  // ~1.5s grace period
    if (ret == 0) {
        pidfd_send_signal_compat(pidfd, SIGKILL);
    }
    close(pidfd);
    return nullptr;
}

static void stop_escalate_async(int pidfd) {
    GThread* t = g_thread_new("flatpak-stop", stop_escalate_thread, GINT_TO_POINTER(pidfd));
    g_thread_unref(t);
}

void InstallationReader::stop(Dart_Port port, const char* app_id) {
    g_autoptr(GPtrArray) instances = flatpak_instance_get_all();
    bool found = false;
    if (instances) {
        for (guint i = 0; i < instances->len; i++) {
            auto* inst = static_cast<FlatpakInstance*>(instances->pdata[i]);
            if (g_strcmp0(flatpak_instance_get_app(inst), app_id) != 0) {
                continue;
            }
            int child_pid = flatpak_instance_get_child_pid(inst);
            if (child_pid <= 0) {
                continue;
            }
            int pidfd = pidfd_open_compat(child_pid);
            if (pidfd < 0) {
                continue;  // ESRCH: no live app process for this instance
            }
            found = true;
            pidfd_send_signal_compat(pidfd, SIGTERM);
            stop_escalate_async(pidfd);  // thread takes ownership, closes it
        }
    }
    if (!found) {
        post_error(port, "no running instance for app_id");
        return;
    }
    post_sentinel(port);
}

void InstallationReader::list_running(Dart_Port port) {
    g_autoptr(GPtrArray) instances = flatpak_instance_get_all();
    if (!instances) {
        post_sentinel(port);
        return;
    }
    for (guint i = 0; i < instances->len; i++) {
        auto* inst = static_cast<FlatpakInstance*>(instances->pdata[i]);
        FpInstance info;
        info.appId = safe_str(flatpak_instance_get_app(inst));
        info.instanceId = safe_str(flatpak_instance_get_id(inst));
        info.arch = safe_str(flatpak_instance_get_arch(inst));
        info.branch = safe_str(flatpak_instance_get_branch(inst));
        info.commit = safe_str(flatpak_instance_get_commit(inst));
        info.pid = flatpak_instance_get_pid(inst);
        info.childPid = flatpak_instance_get_child_pid(inst);
        info.isRunning = flatpak_instance_is_running(inst);
        post_glaze(port, 0x01, info);
    }
    post_sentinel(port);
}

void InstallationReader::drop_caches() {
    g_autoptr(GError) err = nullptr;
    flatpak_installation_drop_caches(installation_, nullptr, &err);
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
    g_autoptr(GFile) path = g_file_new_for_path(name);
    return flatpak_installation_new_for_path(path, false, nullptr, &err);
}

extern "C" {

void* flatpak_reader_create(const char* installation) {
    auto* inst = open_installation(installation);
    if (!inst) {
        return nullptr;
    }
    auto* reader = new InstallationReader(inst);
    g_object_unref(inst);
    return reader;
}

void flatpak_reader_destroy(void* handle) {
    delete static_cast<InstallationReader*>(handle);
}

void flatpak_reader_list_apps(void* handle, Dart_Port port, bool include_runtimes) {
    static_cast<InstallationReader*>(handle)->list_apps(port, include_runtimes);
}

void flatpak_reader_list_remotes(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->list_remotes(port);
}

void flatpak_reader_get_remote_info(void* handle, Dart_Port port, const char* name) {
    static_cast<InstallationReader*>(handle)->get_remote_info(port, name);
}

void flatpak_reader_list_remote_apps(void* handle, Dart_Port port, const char* name,
                                     const char* arch, bool include_runtimes) {
    static_cast<InstallationReader*>(handle)->list_remote_apps(port, name, arch, include_runtimes);
}

void flatpak_reader_get_app_info(void* handle, Dart_Port port, const char* app_id, const char* arch,
                                 const char* branch) {
    static_cast<InstallationReader*>(handle)->get_app_info(port, app_id, arch, branch);
}

void flatpak_reader_get_permissions(void* handle, Dart_Port port, const char* app_id) {
    static_cast<InstallationReader*>(handle)->get_permissions(port, app_id);
}

void flatpak_reader_check_updates(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->check_updates(port);
}

void flatpak_reader_fetch_remote_metadata(void* handle, Dart_Port port, const char* remote,
                                          const char* ref) {
    static_cast<InstallationReader*>(handle)->fetch_remote_metadata(port, remote, ref);
}

void flatpak_reader_launch(void* handle, Dart_Port port, const char* app_id, const char* arch,
                           const char* branch, const char* commit) {
    static_cast<InstallationReader*>(handle)->launch(port, app_id, arch, branch, commit);
}

void flatpak_reader_stop(void* handle, Dart_Port port, const char* app_id) {
    static_cast<InstallationReader*>(handle)->stop(port, app_id);
}

void flatpak_reader_list_running(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->list_running(port);
}

void flatpak_reader_drop_caches(void* handle) {
    static_cast<InstallationReader*>(handle)->drop_caches();
}

}  // extern "C"
