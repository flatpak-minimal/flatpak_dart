// InstallationReader — read-only libflatpak query bridge.
// All operations use flatpak_installation_* and run on the caller's thread.
// Results are posted to Dart via Dart_PostCObject_DL.
#pragma once
#include "dart_api_dl.h"
#include "flatpak_types.h"
#include <flatpak/flatpak.h>

class InstallationReader {
public:
    InstallationReader(Dart_Port port, FlatpakInstallation* inst);
    ~InstallationReader();

    void list_apps(bool include_runtimes);
    void list_remotes();
    void get_remote_info(const char* name);
    void list_remote_apps(const char* name, const char* arch,
                          bool include_runtimes);
    void get_app_info(const char* app_id, const char* arch,
                      const char* branch);
    void get_permissions(const char* app_id);
    void check_updates();

private:
    Dart_Port            port_;
    FlatpakInstallation* installation_;
};
