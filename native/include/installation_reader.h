// InstallationReader — read-only libflatpak query bridge.
// Results are posted to the Dart_Port passed per-call.
#pragma once
#include <flatpak/flatpak.h>

#include <condition_variable>
#include <functional>
#include <mutex>
#include <queue>
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
    void launch(Dart_Port port, const char* app_id, const char* arch, const char* branch,
                const char* commit);
    void stop(Dart_Port port, const char* app_id);
    void list_running(Dart_Port port);
    void drop_caches();

   private:
    FlatpakInstallation* installation_;

    // ── Launch queue — one dedicated thread, serial ──────────────────────
    // flatpak_installation_launch_full() blocks while bubblewrap sets the
    // sandbox up, so it must not run on the Dart thread. Same shape as
    // TransactionWorker (transaction_bridge.h), deliberately built on the
    // standard library rather than an async runtime: every other thread in
    // this bridge is a plain std::thread or GThread, and adding a system
    // dependency for one serial queue would have to be satisfied by every
    // consumer sysroot as well as CI.
    std::thread launch_thread_;
    std::mutex launch_mu_;
    std::condition_variable launch_cv_;
    std::queue<std::function<void()>> launch_queue_;
    bool launch_stop_{false};

    void launch_loop();
    void launch_impl(Dart_Port port, const char* app_id, const char* arch, const char* branch,
                     const char* commit);
};
