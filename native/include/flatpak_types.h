// Glaze-serialisable structs mirroring all Dart-facing data types.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "glaze_meta.h"

struct FpRef {
    std::string kind;  // "app" | "runtime"
    std::string name;
    std::string arch;
    std::string branch;
    std::string commit;
    std::string collectionId;
};

template <>
struct glz::meta<FpRef> {
    static constexpr auto fields = std::make_tuple(
        glz::field("kind", &FpRef::kind), glz::field("name", &FpRef::name),
        glz::field("arch", &FpRef::arch), glz::field("branch", &FpRef::branch),
        glz::field("commit", &FpRef::commit), glz::field("collectionId", &FpRef::collectionId));
};

struct InstalledApp {
    FpRef ref;
    std::string origin;
    std::string latestCommit;
    std::string installedPath;
    uint64_t installedSize{};
    bool isCurrentArch{};
    bool endOfLife{};
    std::string endOfLifeRebase;
    std::string appDataName;
    std::string appDataSummary;
    std::string appDataVersion;
    std::string appDataIcon;
};

template <>
struct glz::meta<InstalledApp> {
    static constexpr auto fields = std::make_tuple(
        glz::field("ref", &InstalledApp::ref), glz::field("origin", &InstalledApp::origin),
        glz::field("latestCommit", &InstalledApp::latestCommit),
        glz::field("installedPath", &InstalledApp::installedPath),
        glz::field("installedSize", &InstalledApp::installedSize),
        glz::field("isCurrentArch", &InstalledApp::isCurrentArch),
        glz::field("endOfLife", &InstalledApp::endOfLife),
        glz::field("endOfLifeRebase", &InstalledApp::endOfLifeRebase),
        glz::field("appDataName", &InstalledApp::appDataName),
        glz::field("appDataSummary", &InstalledApp::appDataSummary),
        glz::field("appDataVersion", &InstalledApp::appDataVersion),
        glz::field("appDataIcon", &InstalledApp::appDataIcon));
};

struct FlatpakRemoteInfo {
    std::string name;
    std::string url;
    std::string title;
    std::string comment;
    std::string description;
    std::string homepage;
    std::string defaultBranch;
    // Subset filtering (Flatpak >= 1.12): "verified" | "floss" | "verified_floss" | ""
    std::string subset;
    // OSTree collection ID, e.g. "org.flathub.Stable" — used for P2P and USB sideloading
    std::string collectionId;
    // Path to an app-filter file (AppStream subset) — empty if not set
    std::string filter;
    // Remote type: 0 = user, 1 = system, 2 = static (pre-installed /etc/flatpak/remotes.d)
    int32_t remoteType{};
    bool disabled{};
    bool gpgVerify{};
    // nodeps: skip dependency resolution when installing from this remote
    bool noDeps{};
    int32_t priority{};
};

template <>
struct glz::meta<FlatpakRemoteInfo> {
    static constexpr auto fields = std::make_tuple(
        glz::field("name", &FlatpakRemoteInfo::name), glz::field("url", &FlatpakRemoteInfo::url),
        glz::field("title", &FlatpakRemoteInfo::title),
        glz::field("comment", &FlatpakRemoteInfo::comment),
        glz::field("description", &FlatpakRemoteInfo::description),
        glz::field("homepage", &FlatpakRemoteInfo::homepage),
        glz::field("defaultBranch", &FlatpakRemoteInfo::defaultBranch),
        glz::field("subset", &FlatpakRemoteInfo::subset),
        glz::field("collectionId", &FlatpakRemoteInfo::collectionId),
        glz::field("filter", &FlatpakRemoteInfo::filter),
        glz::field("remoteType", &FlatpakRemoteInfo::remoteType),
        glz::field("disabled", &FlatpakRemoteInfo::disabled),
        glz::field("gpgVerify", &FlatpakRemoteInfo::gpgVerify),
        glz::field("noDeps", &FlatpakRemoteInfo::noDeps),
        glz::field("priority", &FlatpakRemoteInfo::priority));
};

// ── RemoteConfig — used for add/modify operations (write path) ──────────────
//
// Sentinel values indicate "leave unchanged" for modify operations:
//   priority == -1    -> don't change
//   gpgVerify == -1   -> don't change  (0 = false, 1 = true)
//   disabled  == -1   -> don't change
//   noDeps    == -1   -> don't change
//
// gpgKeyData holds raw GPG key bytes (not base64); the C bridge reads the key
// from a file or from the .flatpakrepo bundle and passes the raw bytes here.
struct RemoteConfig {
    std::string url;
    std::string title;
    std::string comment;
    std::string homepage;
    std::string defaultBranch;
    // Glaze-serialised as bytes; C++ bridge calls
    // flatpak_remote_set_gpg_key(remote, g_bytes_new(data, len)).
    std::vector<uint8_t> gpgKeyData;
    std::string subset;  // "" clears any existing subset filter
    std::string collectionId;
    std::string filter;  // "" clears any existing filter file
    int32_t priority{-1};
    int8_t gpgVerify{-1};
    int8_t disabled{-1};
    int8_t noDeps{-1};
};

template <>
struct glz::meta<RemoteConfig> {
    static constexpr auto fields = std::make_tuple(
        glz::field("url", &RemoteConfig::url), glz::field("title", &RemoteConfig::title),
        glz::field("comment", &RemoteConfig::comment),
        glz::field("homepage", &RemoteConfig::homepage),
        glz::field("defaultBranch", &RemoteConfig::defaultBranch),
        glz::field("gpgKeyData", &RemoteConfig::gpgKeyData),
        glz::field("subset", &RemoteConfig::subset),
        glz::field("collectionId", &RemoteConfig::collectionId),
        glz::field("filter", &RemoteConfig::filter),
        glz::field("priority", &RemoteConfig::priority),
        glz::field("gpgVerify", &RemoteConfig::gpgVerify),
        glz::field("disabled", &RemoteConfig::disabled),
        glz::field("noDeps", &RemoteConfig::noDeps));
};

struct TransactionProgress {
    std::string op;  // "install" | "update" | "uninstall"
    std::string ref;
    uint32_t progress{};  // 0-100
    uint64_t bytesTransferred{};
    uint64_t bytesTotal{};
    std::string status;
};

template <>
struct glz::meta<TransactionProgress> {
    static constexpr auto fields = std::make_tuple(
        glz::field("op", &TransactionProgress::op), glz::field("ref", &TransactionProgress::ref),
        glz::field("progress", &TransactionProgress::progress),
        glz::field("bytesTransferred", &TransactionProgress::bytesTransferred),
        glz::field("bytesTotal", &TransactionProgress::bytesTotal),
        glz::field("status", &TransactionProgress::status));
};
