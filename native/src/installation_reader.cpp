// installation_reader.cpp — All read-only libflatpak queries.
// Posts glaze-encoded results to Dart via Dart_PostCObject_DL.
// Reader is created once per installation; port passed per-call.

#include "installation_reader.h"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

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

// 0x03 — lifecycle operation failure (launch or stop), as distinct from the 0x02 "nothing
// matched" condition that maps to FlatpakNotFoundException on the Dart side.
static void post_op_error(Dart_Port port, const char* msg) {
    flatpak_nc::post_framed_error(port, 0x03, msg);
}

static void post_string(Dart_Port port, const char* s) {
    flatpak_nc::post_framed_error(port, 0x01, s);
}

static const char* safe_str(const char* s) {
    return s ? s : "";
}

// FLATPAK_LAUNCH_FLAGS_DO_NOT_REAP leaves the bwrap process as our child, so
// something in this process has to waitpid() it or it becomes a zombie for the
// lifetime of the host app. waitpid(-1) would be wrong in a library — it would
// steal exit statuses from whatever else the embedder has spawned — so we wait
// on the specific pid.
//
// One reaper thread serves every launched app. It parks in poll() over the
// launched children's pidfds and reaps with WNOHANG when one becomes readable,
// so a session that launches N apps costs one thread rather than N. The thread
// is started on the first launch and exits once the last child is reaped.
namespace {

class ChildReaper {
   public:
    static ChildReaper& instance() {
        static ChildReaper reaper;
        return reaper;
    }

    void add(GPid pid) {
        int pidfd = pidfd_open(pid);
        if (pidfd < 0) {
            // No pidfd (pre-5.3 kernel, or the child is already gone). Fall back to a dedicated
            // blocking wait so the child is still reaped.
            std::thread([pid] { wait_for(pid); }).detach();
            return;
        }

        bool start = false;
        {
            std::lock_guard lk(mu_);
            pending_.push_back({pid, pidfd});
            if (!running_) {
                running_ = true;
                start = true;
            }
        }
        if (start) {
            std::thread(&ChildReaper::loop, this).detach();
        }
        wake();
    }

   private:
    struct Child {
        GPid pid;
        int pidfd;
    };

    ChildReaper() {
        // O_NONBLOCK on both ends: the reader drains until EAGAIN, and the writer must never
        // block the launching thread if the pipe fills.
        if (pipe2(wake_fds_, O_NONBLOCK | O_CLOEXEC) != 0) {
            wake_fds_[0] = wake_fds_[1] = -1;
        }
    }

    static int pidfd_open(pid_t pid) {
        return static_cast<int>(syscall(SYS_pidfd_open, pid, 0));
    }

    static void wait_for(GPid pid) {
        int status = 0;
        // Retry on EINTR: an unrestarted waitpid() would abandon the child as a zombie for the
        // lifetime of the host process, which is exactly what this reaper exists to prevent. The
        // Dart VM's profiler delivers SIGPROF, and embedders install handlers of their own.
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
        }
    }

    void wake() {
        if (wake_fds_[1] >= 0) {
            const char b = 0;
            ssize_t ignored = write(wake_fds_[1], &b, 1);
            (void)ignored;
        }
    }

    void loop() {
        std::vector<Child> watched;
        std::vector<pollfd> fds;

        for (;;) {
            {
                std::lock_guard lk(mu_);
                watched.insert(watched.end(), pending_.begin(), pending_.end());
                pending_.clear();
                if (watched.empty()) {
                    running_ = false;
                    return;
                }
            }

            fds.clear();
            fds.reserve(watched.size() + 1);
            if (wake_fds_[0] >= 0) {
                fds.push_back({wake_fds_[0], POLLIN, 0});
            }
            for (const auto& c : watched) {
                fds.push_back({c.pidfd, POLLIN, 0});
            }

            if (poll(fds.data(), fds.size(), -1) < 0) {
                if (errno == EINTR) {
                    continue;
                }
                // poll() cannot recover; reap what we hold so nothing is left a zombie.
                for (const auto& c : watched) {
                    wait_for(c.pid);
                    close(c.pidfd);
                }
                std::lock_guard lk(mu_);
                running_ = false;
                return;
            }

            const size_t offset = (wake_fds_[0] >= 0) ? 1 : 0;
            if (offset == 1 && (fds[0].revents & POLLIN) != 0) {
                char drain[64];
                while (read(wake_fds_[0], drain, sizeof(drain)) > 0) {
                }
            }

            size_t kept = 0;
            for (size_t i = 0; i < watched.size(); i++) {
                if (fds[i + offset].revents == 0) {
                    watched[kept++] = watched[i];
                    continue;
                }
                int status = 0;
                while (waitpid(watched[i].pid, &status, WNOHANG) < 0 && errno == EINTR) {
                }
                close(watched[i].pidfd);
            }
            watched.resize(kept);
        }
    }

    std::mutex mu_;
    std::vector<Child> pending_;
    bool running_ = false;
    int wake_fds_[2]{-1, -1};
};

}  // namespace

static void reap_async(GPid pid) {
    ChildReaper::instance().add(pid);
}

// Resolve an installed app ref from optional arch/branch hints.
// get_current_installed_app() takes no arch, so it is only used when neither
// hint narrows the lookup; an arch-only lookup scans the installed apps.
static FlatpakInstalledRef* get_installed_app_ref(FlatpakInstallation* installation,
                                                  const char* app_id, const char* arch,
                                                  const char* branch, GError** error) {
    const char* want_arch = (arch && *arch) ? arch : nullptr;
    const char* want_branch = (branch && *branch) ? branch : nullptr;

    if (want_branch) {
        return flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_APP, app_id,
                                                      want_arch, want_branch, nullptr, error);
    }
    if (!want_arch) {
        return flatpak_installation_get_current_installed_app(installation, app_id, nullptr, error);
    }

    g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs_by_kind(
        installation, FLATPAK_REF_KIND_APP, nullptr, error);
    if (!refs) {
        return nullptr;
    }
    FlatpakInstalledRef* match = nullptr;
    for (guint i = 0; i < refs->len; i++) {
        auto* iref = static_cast<FlatpakInstalledRef*>(refs->pdata[i]);
        if (g_strcmp0(flatpak_ref_get_name(FLATPAK_REF(iref)), app_id) != 0 ||
            g_strcmp0(flatpak_ref_get_arch(FLATPAK_REF(iref)), want_arch) != 0) {
            continue;
        }
        if (!match || flatpak_installed_ref_get_is_current(iref)) {
            match = iref;
        }
    }
    if (!match) {
        g_set_error(error, FLATPAK_ERROR, FLATPAK_ERROR_NOT_INSTALLED, "%s/%s is not installed",
                    app_id, want_arch);
        return nullptr;
    }
    return static_cast<FlatpakInstalledRef*>(g_object_ref(match));
}

// ── InstallationReader ──────────────────────────────────────────────────────

InstallationReader::InstallationReader(FlatpakInstallation* inst)
    : installation_(static_cast<FlatpakInstallation*>(g_object_ref(inst))) {
    launch_thread_ = std::thread(&InstallationReader::launch_loop, this);
}

InstallationReader::~InstallationReader() {
    // Signal, then join, then unref: the in-flight launch (if any) finishes against a live
    // installation_, the queued backlog is cancelled rather than run, and only then do we drop the
    // installation reference the launch thread was using.
    {
        std::lock_guard lk(launch_mu_);
        launch_stop_.store(true);
    }
    launch_cv_.notify_one();
    if (launch_thread_.joinable()) {
        launch_thread_.join();
    }
    g_object_unref(installation_);
}

void InstallationReader::launch_loop() {
    for (;;) {
        LaunchRequest req;
        {
            std::unique_lock lk(launch_mu_);
            launch_cv_.wait(lk, [&] { return launch_stop_.load() || !launch_queue_.empty(); });
            if (launch_stop_.load()) {
                // Do not make close() pay for the whole backlog: a queued launch has not spawned
                // anything yet, so cancelling it costs nothing but a reply. Each one still gets an
                // error frame, so no Dart future is left hanging. Only the in-flight launch (if
                // any) has already run to completion by the time we get here.
                std::queue<LaunchRequest> pending;
                pending.swap(launch_queue_);
                lk.unlock();
                while (!pending.empty()) {
                    post_op_error(pending.front().port, "reader closed before launch started");
                    pending.pop();
                }
                return;
            }
            req = std::move(launch_queue_.front());
            launch_queue_.pop();
        }
        launch_impl(req.port, req.appId.c_str(), req.arch.c_str(), req.branch.c_str(),
                    req.commit.c_str());
    }
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

namespace {

bool remote_ref_has_socket(FlatpakRemoteRef* fref, const char* socket_name) {
    GBytes* metadata = flatpak_remote_ref_get_metadata(fref);
    if (!metadata) {
        return false;
    }
    gsize len = 0;
    auto* data = static_cast<const char*>(g_bytes_get_data(metadata, &len));
    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, data, len, G_KEY_FILE_NONE, nullptr)) {
        return false;
    }
    g_autofree char* sockets = g_key_file_get_string(kf, "Context", "sockets", nullptr);
    return sockets && strstr(sockets, socket_name) != nullptr;
}
}  // namespace

void InstallationReader::list_remote_apps(Dart_Port port, const char* name, const char* arch,
                                          bool include_runtimes, bool wayland_only) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs =
        flatpak_installation_list_remote_refs_sync(installation_, name, nullptr, &err);
    if (!refs) {
        post_error(port, err->message);
        return;
    }
    for (guint i = 0; i < refs->len; i++) {
        auto* fref = static_cast<FlatpakRemoteRef*>(refs->pdata[i]);
        bool is_app = flatpak_ref_get_kind(FLATPAK_REF(fref)) == FLATPAK_REF_KIND_APP;
        if (!include_runtimes && !is_app) {
            continue;
        }
        if (arch && *arch && g_strcmp0(flatpak_ref_get_arch(FLATPAK_REF(fref)), arch) != 0) {
            continue;
        }
        // Skip apps that don't request the wayland socket.
        if (wayland_only && is_app && !remote_ref_has_socket(fref, "wayland")) {
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
    g_autoptr(FlatpakInstalledRef) iref =
        get_installed_app_ref(installation_, app_id, arch, branch, &err);
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
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref =
        get_installed_app_ref(installation_, app_id, "", "", &err);
    if (!iref) {
        post_error(port, err ? err->message : "app not installed");
        return;
    }
    err = nullptr;
    g_autoptr(GBytes) bytes = flatpak_installed_ref_load_metadata(iref, nullptr, &err);
    if (!bytes) {
        post_error(port, err ? err->message : "failed to load metadata");
        return;
    }
    gsize len = 0;
    auto* data = static_cast<const char*>(g_bytes_get_data(bytes, &len));
    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, data, len, G_KEY_FILE_NONE, &err)) {
        post_error(port, err ? err->message : "failed to parse metadata");
        return;
    }

    const char* sections[] = {"Context", "Session Bus Policy", "System Bus Policy", "Environment",
                              nullptr};
    for (const char** sp = sections; *sp; ++sp) {
        g_auto(GStrv) keys = g_key_file_get_keys(kf, *sp, nullptr, nullptr);
        if (!keys) {
            continue;
        }
        for (gsize i = 0; keys[i]; i++) {
            g_autofree char* val = g_key_file_get_string(kf, *sp, keys[i], nullptr);
            FpMetadataEntry entry;
            entry.section = *sp;
            entry.key = keys[i];
            entry.value = val ? val : "";
            post_glaze(port, 0x01, entry);
        }
    }
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

// Returns false when no installed ref matches. *out_err is set only when the lookup itself
// failed (as opposed to simply finding nothing), so the caller can tell "app not installed" from
// "could not read the installation".
static bool resolve_launch_target(FlatpakInstallation* installation, const char* app_id,
                                  const char* hint_arch, const char* hint_branch,
                                  std::string* out_arch, std::string* out_branch,
                                  std::string* out_err) {
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
        *out_err = lerr && lerr->message ? lerr->message : "failed to list installed refs";
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

// flatpak_instance_get_child_pid() returns the value the instance directory held when the
// FlatpakInstance was constructed. launch_full() hands back an object built before bwrap has
// written the pid file, so reading it there always yields 0. Re-enumerate until a freshly
// constructed object for the same instance id carries the real pid.
//
// Best-effort and bounded: an app that exits before bwrap writes the pid, or a target slow enough
// to miss the deadline, yields 0 — the same value the caller would have seen without this.
static int reread_child_pid(const char* instance_id, const std::atomic<bool>& cancelled) {
    constexpr int kMaxWaitMs = 500;
    constexpr int kMaxBackoffMs = 64;
    bool ever_seen = false;
    int waited = 0;
    int delay_ms = 1;

    for (;;) {
        g_autoptr(GPtrArray) all = flatpak_instance_get_all();
        bool seen_now = false;
        if (all) {
            for (guint i = 0; i < all->len; i++) {
                auto* inst = static_cast<FlatpakInstance*>(all->pdata[i]);
                if (g_strcmp0(flatpak_instance_get_id(inst), instance_id) != 0) {
                    continue;
                }
                seen_now = true;
                int child = flatpak_instance_get_child_pid(inst);
                if (child > 0) {
                    return child;
                }
                break;
            }
        }
        // Once the instance has appeared and then vanished, the app is gone and no pid is
        // coming — stop rather than burning the rest of the budget.
        if (seen_now) {
            ever_seen = true;
        } else if (ever_seen) {
            return 0;
        }
        if (waited >= kMaxWaitMs || cancelled.load()) {
            return 0;
        }
        // Back off geometrically. Every probe re-enumerates and re-parses the info file of every
        // running flatpak on the host, so a fixed 5ms interval spent ~100 of them to cover 500ms;
        // this covers the same window in ~13 while leaving the common case (found on the first or
        // second probe) exactly as fast.
        int sleep_ms = std::min(delay_ms, kMaxWaitMs - waited);
        g_usleep(static_cast<gulong>(sleep_ms) * 1000);
        waited += sleep_ms;
        delay_ms = std::min(delay_ms * 2, kMaxBackoffMs);
    }
}

void InstallationReader::launch(Dart_Port port, const char* app_id, const char* arch,
                                const char* branch, const char* commit) {
    std::string appIdStr = safe_str(app_id);
    std::string archStr = safe_str(arch);
    std::string branchStr = safe_str(branch);
    std::string commitStr = safe_str(commit);
    {
        std::lock_guard lk(launch_mu_);
        launch_queue_.push(LaunchRequest{port, appIdStr, archStr, branchStr, commitStr});
    }
    launch_cv_.notify_one();
}

void InstallationReader::launch_impl(Dart_Port port, const char* app_id, const char* arch,
                                     const char* branch, const char* commit) {
    const char* use_arch = (arch && *arch) ? arch : nullptr;
    const char* use_branch = (branch && *branch) ? branch : nullptr;
    const char* use_commit = (commit && *commit) ? commit : nullptr;

    std::string resolved_arch;
    std::string resolved_branch;
    if (!use_arch || !use_branch) {
        std::string resolve_err;
        if (!resolve_launch_target(installation_, app_id, use_arch, use_branch, &resolved_arch,
                                   &resolved_branch, &resolve_err)) {
            if (resolve_err.empty()) {
                post_error(port, "app not installed");
            } else {
                // The installation could not be read at all — surfacing that as "not installed"
                // sends the caller looking for the wrong problem.
                post_op_error(port, resolve_err.c_str());
            }
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
            post_op_error(port, err ? err->message : "launch failed");
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

    // Always 0 on the object launch_full() returns; we are on the launch thread, so waiting the
    // few ms for bwrap to write it costs the Dart thread nothing.
    if (info.childPid <= 0 && !info.instanceId.empty()) {
        info.childPid = reread_child_pid(info.instanceId.c_str(), launch_stop_);
    }

    post_glaze(port, 0x01, info);
    post_sentinel(port);
}

// Field 22 of /proc/<pid>/stat is the process start time in clock ticks since boot. Paired with
// the pid it identifies a process *instance*: a recycled pid always carries a different start
// time, so comparing it before and after we pin a process tells us whether we pinned the one we
// meant to. Returns false if the process is gone or /proc is unreadable.
static bool read_start_time(pid_t pid, unsigned long long* out) {
    char path[64];
    g_snprintf(path, sizeof(path), "/proc/%d/stat", static_cast<int>(pid));
    g_autofree char* contents = nullptr;
    if (!g_file_get_contents(path, &contents, nullptr, nullptr)) {
        return false;
    }
    // Field 2 (comm) is parenthesised and may itself contain spaces and parens, so start scanning
    // after the final ')'; the next token is field 3.
    const char* p = strrchr(contents, ')');
    if (!p) {
        return false;
    }
    p++;
    int field = 2;
    while (*p) {
        while (*p == ' ') {
            p++;
        }
        if (!*p) {
            break;
        }
        field++;
        if (field == 22) {
            return sscanf(p, "%llu", out) == 1;
        }
        while (*p && *p != ' ') {
            p++;
        }
    }
    return false;
}

constexpr int kGraceMs = 1500;

// pidfd-based signalling. A pidfd pins the exact process instance it was opened for, so once we
// hold one the pid cannot be recycled out from under us. It does NOT cover the window before the
// open: the pid we are about to open came out of an instance file on disk and the process may have
// exited since. read_start_time() below closes that window.
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
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(kGraceMs);
    int ret = 0;
    for (;;) {
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
            deadline - std::chrono::steady_clock::now());
        int timeout_ms = remaining.count() > 0 ? static_cast<int>(remaining.count()) : 0;
        pfd.revents = 0;
        ret = poll(&pfd, 1, timeout_ms);
        if (ret >= 0 || errno != EINTR) {
            break;
        }
        if (timeout_ms == 0) {
            break;
        }
    }
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

// Escalation for the no-pidfd fallback. Measured against GTK apps: gnome-calculator ignores
// SIGTERM outright and exits only on the SIGKILL at the grace deadline, so a fallback that sent
// SIGTERM alone would simply fail to stop such an app rather than degrade gracefully. Without a
// pidfd we cannot pin the process, so re-check the start time before killing: if the pid has been
// recycled during the grace period the kill would land on an unrelated process.
struct FallbackKill {
    pid_t pid;
    unsigned long long start_time;
    bool have_start;
};

static gpointer fallback_escalate_thread(gpointer data) {
    std::unique_ptr<FallbackKill> fk(static_cast<FallbackKill*>(data));
    g_usleep(static_cast<gulong>(kGraceMs) * 1000);
    if (kill(fk->pid, 0) != 0) {
        return nullptr;  // exited during the grace period
    }
    unsigned long long now = 0;
    if (fk->have_start && (!read_start_time(fk->pid, &now) || now != fk->start_time)) {
        return nullptr;  // pid recycled — not our process any more
    }
    kill(fk->pid, SIGKILL);
    return nullptr;
}

static void fallback_escalate_async(pid_t pid, unsigned long long start_time, bool have_start) {
    auto* fk = new FallbackKill{pid, start_time, have_start};
    GThread* t = g_thread_new("flatpak-stop-fb", fallback_escalate_thread, fk);
    g_thread_unref(t);
}

// Sends SIGTERM to one sandbox process and arms SIGKILL escalation. Returns true only if the
// signal actually reached the intended process.
static bool signal_instance_process(pid_t pid) {
    unsigned long long start_before = 0;
    const bool have_start = read_start_time(pid, &start_before);

    int pidfd = pidfd_open_compat(pid);
    if (pidfd >= 0) {
        // The pidfd pins the process from here on. Re-read the start time now that it is pinned:
        // if it still matches, the pid was not recycled between the instance file and the open.
        unsigned long long start_after = 0;
        if (have_start && (!read_start_time(pid, &start_after) || start_after != start_before)) {
            close(pidfd);
            return false;
        }
        if (pidfd_send_signal_compat(pidfd, SIGTERM) != 0) {
            close(pidfd);
            return false;
        }
        stop_escalate_async(pidfd);  // thread takes ownership, closes it
        return true;
    }
    if (errno == ESRCH) {
        return false;  // already gone
    }
    // ENOSYS on pre-5.3 kernels, EMFILE, a seccomp filter. Fall back to plain signals.
    if (kill(pid, SIGTERM) != 0) {
        return false;
    }
    fallback_escalate_async(pid, start_before, have_start);
    return true;
}

void InstallationReader::stop(Dart_Port port, const char* app_id) {
    g_autoptr(GPtrArray) instances = flatpak_instance_get_all();
    int matched = 0;
    int signalled = 0;
    if (instances) {
        for (guint i = 0; i < instances->len; i++) {
            auto* inst = static_cast<FlatpakInstance*>(instances->pdata[i]);
            if (g_strcmp0(flatpak_instance_get_app(inst), app_id) != 0) {
                continue;
            }
            // Skip stale instance directories whose process is already gone, so we never signal a
            // pid the kernel may since have handed to something unrelated.
            if (!flatpak_instance_is_running(inst)) {
                continue;
            }
            matched++;

            // Prefer the sandboxed app process: SIGTERM has to reach the app itself for it to shut
            // down on its own terms, and bwrap follows it down. Fall back to the outer bwrap pid
            // when the child pid has not been published yet — coarser, but silently skipping a
            // running instance while reporting success is worse.
            int target = flatpak_instance_get_child_pid(inst);
            if (target <= 0) {
                target = flatpak_instance_get_pid(inst);
            }
            if (target <= 0) {
                continue;
            }
            if (signal_instance_process(target)) {
                signalled++;
            }
        }
    }
    if (matched == 0) {
        post_error(port, "no running instance for app_id");
        return;
    }
    if (signalled == 0) {
        // Matched running instances but could not signal any. This is emphatically not a
        // "not found" condition — reporting it as one tells the caller their app is not running
        // when it is.
        post_op_error(port, "matched running instance(s) but could not signal any");
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

void InstallationReader::get_version(Dart_Port port) {
    char version[32];
    std::snprintf(version, sizeof(version), "%d.%d.%d", FLATPAK_MAJOR_VERSION,
                  FLATPAK_MINOR_VERSION, FLATPAK_MICRO_VERSION);
    post_string(port, version);
    post_sentinel(port);
}

void InstallationReader::get_default_arch(Dart_Port port) {
    post_string(port, safe_str(flatpak_get_default_arch()));
    post_sentinel(port);
}

void InstallationReader::get_supported_arches(Dart_Port port) {
    const char* const* arches = flatpak_get_supported_arches();
    for (const char* const* p = arches; p && *p; ++p) {
        post_string(port, *p);
    }
    post_sentinel(port);
}

void InstallationReader::list_system_installations(Dart_Port port) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) installs = flatpak_get_system_installations(nullptr, &err);
    if (!installs) {
        post_error(port, err ? err->message : "failed to list system installations");
        return;
    }
    for (guint i = 0; i < installs->len; i++) {
        auto* inst = static_cast<FlatpakInstallation*>(installs->pdata[i]);
        FpInstallationInfo info;
        info.id = safe_str(flatpak_installation_get_id(inst));
        info.displayName = safe_str(flatpak_installation_get_display_name(inst));
        g_autoptr(GFile) path = flatpak_installation_get_path(inst);
        g_autofree char* path_str = path ? g_file_get_path(path) : nullptr;
        info.path = safe_str(path_str);
        info.isUser = flatpak_installation_get_is_user(inst);
        info.priority = flatpak_installation_get_priority(inst);
        post_glaze(port, 0x01, info);
    }
    post_sentinel(port);
}

void InstallationReader::get_runtime_ref(Dart_Port port, const char* app_id, const char* arch,
                                         const char* branch) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref =
        get_installed_app_ref(installation_, app_id, arch, branch, &err);
    if (!iref) {
        post_error(port, err ? err->message : "app not installed");
        return;
    }
    err = nullptr;
    g_autoptr(GBytes) bytes = flatpak_installed_ref_load_metadata(iref, nullptr, &err);
    if (!bytes) {
        post_error(port, err ? err->message : "failed to load metadata");
        return;
    }
    gsize len = 0;
    auto* data = static_cast<const char*>(g_bytes_get_data(bytes, &len));
    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, data, len, G_KEY_FILE_NONE, &err)) {
        post_error(port, err ? err->message : "failed to parse metadata");
        return;
    }
    g_autofree char* runtime = g_key_file_get_string(kf, "Application", "runtime", nullptr);
    if (!runtime || !*runtime) {
        post_error(port, "no runtime declared");
        return;
    }
    post_string(port, runtime);
    post_sentinel(port);
}

void InstallationReader::is_ref_installed(Dart_Port port, const char* ref) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakRef) fref = flatpak_ref_parse(ref, &err);
    if (!fref) {
        post_error(port, err ? err->message : "invalid ref");
        return;
    }
    err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref = flatpak_installation_get_installed_ref(
        installation_, flatpak_ref_get_kind(fref), flatpak_ref_get_name(fref),
        flatpak_ref_get_arch(fref), flatpak_ref_get_branch(fref), nullptr, &err);
    post_string(port, iref ? "1" : "0");
    post_sentinel(port);
}

void InstallationReader::list_missing_extensions(Dart_Port port, const char* app_id,
                                                 const char* arch, const char* branch) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(FlatpakInstalledRef) iref =
        get_installed_app_ref(installation_, app_id, arch, branch, &err);
    if (!iref) {
        post_error(port, err ? err->message : "app not installed");
        return;
    }
    err = nullptr;
    g_autoptr(GBytes) bytes = flatpak_installed_ref_load_metadata(iref, nullptr, &err);
    if (!bytes) {
        post_error(port, err ? err->message : "failed to load metadata");
        return;
    }
    gsize len = 0;
    auto* data = static_cast<const char*>(g_bytes_get_data(bytes, &len));
    g_autoptr(GKeyFile) kf = g_key_file_new();
    if (!g_key_file_load_from_data(kf, data, len, G_KEY_FILE_NONE, &err)) {
        post_error(port, err ? err->message : "failed to parse metadata");
        return;
    }

    const char* app_arch = safe_str(flatpak_ref_get_arch(FLATPAK_REF(iref)));
    const char* app_branch = safe_str(flatpak_ref_get_branch(FLATPAK_REF(iref)));

    g_auto(GStrv) groups = g_key_file_get_groups(kf, nullptr);
    for (gsize i = 0; groups && groups[i]; i++) {
        const char* group = groups[i];
        if (strncmp(group, "Extension ", 10) != 0) {
            continue;
        }
        const char* ext_id = group + 10;
        if (g_key_file_get_boolean(kf, group, "no-autodownload", nullptr)) {
            continue;  // optional extension, not required at app-install time
        }
        // subdirectories=true: installable refs are <point>.<suffix>, enumerated from the remote
        // rather than named here.
        if (g_key_file_get_boolean(kf, group, "subdirectories", nullptr)) {
            continue;
        }

        // "versions" is a ;-list of acceptable branches, any one of which satisfies the extension.
        // "version" is the single-branch form. Neither key means "same branch as the app".
        std::vector<std::string> branches;
        g_auto(GStrv) versions =
            g_key_file_get_string_list(kf, group, "versions", nullptr, nullptr);
        for (gsize v = 0; versions && versions[v]; v++) {
            if (*versions[v]) {
                branches.emplace_back(versions[v]);
            }
        }
        if (branches.empty()) {
            g_autofree char* version = g_key_file_get_string(kf, group, "version", nullptr);
            branches.emplace_back((version && *version) ? version : app_branch);
        }

        bool installed = false;
        for (const auto& ext_branch : branches) {
            g_autoptr(GError) inst_err = nullptr;
            g_autoptr(FlatpakInstalledRef) ext_iref = flatpak_installation_get_installed_ref(
                installation_, FLATPAK_REF_KIND_RUNTIME, ext_id, app_arch, ext_branch.c_str(),
                nullptr, &inst_err);
            if (ext_iref) {
                installed = true;
                break;
            }
        }
        if (!installed) {
            std::string ref_str =
                std::string("runtime/") + ext_id + "/" + app_arch + "/" + branches.front();
            post_string(port, ref_str.c_str());
        }
    }
    post_sentinel(port);
}

void InstallationReader::refresh_appstream(Dart_Port port, const char* remote, const char* arch) {
    const char* use_arch = (arch && *arch) ? arch : nullptr;  // NULL = default arch
    g_autoptr(GError) err = nullptr;
    gboolean changed = FALSE;
    gboolean ok = flatpak_installation_update_appstream_sync(installation_, remote, use_arch,
                                                             &changed, nullptr, &err);
    if (!ok) {
        post_error(port, err ? err->message : "appstream refresh failed");
        return;
    }
    post_sentinel(port);
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
                                     const char* arch, bool include_runtimes, bool wayland_only) {
    static_cast<InstallationReader*>(handle)->list_remote_apps(port, name, arch, include_runtimes,
                                                               wayland_only);
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

void flatpak_reader_refresh_appstream(void* handle, Dart_Port port, const char* remote,
                                      const char* arch) {
    static_cast<InstallationReader*>(handle)->refresh_appstream(port, remote, arch);
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

void flatpak_reader_get_version(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->get_version(port);
}

void flatpak_reader_get_default_arch(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->get_default_arch(port);
}

void flatpak_reader_get_supported_arches(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->get_supported_arches(port);
}

void flatpak_reader_list_system_installations(void* handle, Dart_Port port) {
    static_cast<InstallationReader*>(handle)->list_system_installations(port);
}

void flatpak_reader_get_runtime_ref(void* handle, Dart_Port port, const char* app_id,
                                    const char* arch, const char* branch) {
    static_cast<InstallationReader*>(handle)->get_runtime_ref(port, app_id, arch, branch);
}

void flatpak_reader_is_ref_installed(void* handle, Dart_Port port, const char* ref) {
    static_cast<InstallationReader*>(handle)->is_ref_installed(port, ref);
}

void flatpak_reader_list_missing_extensions(void* handle, Dart_Port port, const char* app_id,
                                            const char* arch, const char* branch) {
    static_cast<InstallationReader*>(handle)->list_missing_extensions(port, app_id, arch, branch);
}

}  // extern "C"
