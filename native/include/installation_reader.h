// InstallationReader — read-only libflatpak query bridge.
// Results are posted to the Dart_Port passed per-call.
#pragma once
#include <flatpak/flatpak.h>

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <string>
#include <thread>

#include "dart_api_dl.h"
#include "flatpak_types.h"

class InstallationReader {
   public:
    explicit InstallationReader(FlatpakInstallation* inst);
    ~InstallationReader();

    void list_apps(Dart_Port port, bool include_runtimes);
    void list_remotes(Dart_Port port);
    void get_remote_info(Dart_Port port, const char* name);
    void list_remote_apps(Dart_Port port, const char* name, const char* arch,
                          bool include_runtimes);
    void get_app_info(Dart_Port port, const char* app_id, const char* arch, const char* branch);
    void get_permissions(Dart_Port port, const char* app_id);
    void check_updates(Dart_Port port);
    void fetch_remote_metadata(Dart_Port port, const char* remote, const char* ref);
    // Refresh the downloaded AppStream catalog for a remote (empty arch = default).
    // Wraps flatpak_installation_update_appstream_sync(); posts 0xFF or 0x02.
    void refresh_appstream(Dart_Port port, const char* remote, const char* arch);
    void launch(Dart_Port port, const char* app_id, const char* arch, const char* branch,
                const char* commit);
    void stop(Dart_Port port, const char* app_id);
    void list_running(Dart_Port port);
    void drop_caches();

   private:
    // Thread-safety of installation_: libflatpak documents FlatpakInstallation as safe for
    // concurrent operations from multiple threads (flatpak-installation.c SECTION doc), which is
    // what lets launch_impl() call into it from the launch thread while the reader's other methods
    // call into it from the Dart thread. We deliberately do not add our own mutex: it would have to
    // wrap every libflatpak call to be meaningful, and a partial one would only give false
    // confidence. This comment is the invariant — if that upstream guarantee is ever in doubt, the
    // fix is a mutex around every installation_ use, not just the launch path.
    FlatpakInstallation* installation_;

    // ── Launch queue — one dedicated thread, serial ──────────────────────
    // flatpak_installation_launch_full() blocks while bubblewrap sets the sandbox up, so it must
    // not run on the Dart thread. Same shape as TransactionWorker (transaction_bridge.h),
    // deliberately built on the standard library rather than an async runtime: every other thread
    // in this bridge is a plain std::thread or GThread, and adding a system dependency for one
    // serial queue would have to be satisfied by every consumer sysroot as well as CI.
    //
    // stop() and list_running() deliberately stay on the calling (Dart) thread. Both are bounded
    // reads of $XDG_RUNTIME_DIR/.flatpak plus, for stop(), a few pidfd syscalls — measured at
    // ~102us for list_running() with 3 instances, ~161us with 9, and ~727us for a stop() matching
    // 6 instances, all far inside a frame budget. Queueing them behind launches would make stop()
    // wait on an in-flight sandbox spawn, which is the opposite of what a stop should do.
    struct LaunchRequest {
        Dart_Port port;
        std::string appId;
        std::string arch;
        std::string branch;
        std::string commit;
    };

    std::thread launch_thread_;
    std::mutex launch_mu_;
    std::condition_variable launch_cv_;
    std::queue<LaunchRequest> launch_queue_;
    // Written under launch_mu_ so the condition_variable cannot miss a wakeup; also read without
    // the lock by reread_child_pid() so an in-flight launch can abandon its poll at shutdown.
    std::atomic<bool> launch_stop_{false};

    void launch_loop();
    void launch_impl(Dart_Port port, const char* app_id, const char* arch, const char* branch,
                     const char* commit);
};
