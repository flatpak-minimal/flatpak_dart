// InstallationReader — read-only libflatpak query bridge.
// Results are posted to the Dart_Port passed per-call.
#pragma once
#include <flatpak/flatpak.h>

#include <asio.hpp>
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

    asio::io_context launch_io_;
    asio::executor_work_guard<asio::io_context::executor_type> launch_work_guard_;
    std::thread launch_thread_;

    void launch_impl(Dart_Port port, const char* app_id, const char* arch, const char* branch,
                     const char* commit);
};
