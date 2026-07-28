// C ABI exported to Dart FFI.  All handles are opaque void*.
// All results delivered via Dart_PostCObject_DL. Framed payloads use
// kExternalTypedData, so the buffer is handed to the VM rather than copied;
// the one-byte sentinels use kTypedData, where a copy is cheaper than a heap
// allocation plus finalizer. See flatpak_post.h.
// Message discriminator byte at offset 0:
//   0x01 = success / list-end sentinel
//   0x02 = error (UTF-8, uint32_t length-prefix)
//   0x03 = lifecycle operation failure (UTF-8, uint32_t length-prefix) — a
//          launch_full() failure, an unreadable installation, or a stop() that
//          matched running instances but could not signal any. Distinct from
//          0x02, which means nothing matched.
//   0x10 = TransactionProgress (glaze-encoded, in-flight during tx_run)
//   0x11 = UpdateAvailable (FlatpakMonitor inotify signal)
//   0xFF = streaming list end sentinel
//
// No D-Bus client library. All operations route through libflatpak.
// System-install writes trigger polkit inside libflatpak automatically.

#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "dart_api_dl.h"

#ifdef __cplusplus
extern "C" {
#endif

void flatpak_bridge_init(void* dart_api_dl_data);

// ── Installation reader (libflatpak — read-only) ──────────────────────────
// Created once per installation; port passed per-call so the reader is reusable.
void* flatpak_reader_create(const char* installation);
void flatpak_reader_destroy(void* handle);
void flatpak_reader_list_apps(void* handle, Dart_Port port, bool include_runtimes);
void flatpak_reader_list_remotes(void* handle, Dart_Port port);
void flatpak_reader_get_remote_info(void* handle, Dart_Port port, const char* name);
void flatpak_reader_list_remote_apps(void* handle, Dart_Port port, const char* name,
                                     const char* arch, bool include_runtimes);
void flatpak_reader_get_app_info(void* handle, Dart_Port port, const char* app_id, const char* arch,
                                 const char* branch);
void flatpak_reader_get_permissions(void* handle, Dart_Port port, const char* app_id);
void flatpak_reader_check_updates(void* handle, Dart_Port port);
// Fetches the metadata keyfile for a remote ref (no install required).
// Posts the raw metadata string as a 0x01 payload, then 0xFF sentinel.
void flatpak_reader_fetch_remote_metadata(void* handle, Dart_Port port, const char* remote,
                                          const char* ref);
// Refresh the on-disk AppStream catalog for a remote (empty arch = default arch).
// Wraps flatpak_installation_update_appstream_sync(); posts 0xFF on success, 0x02 on error.
void flatpak_reader_refresh_appstream(void* handle, Dart_Port port, const char* remote,
                                      const char* arch);
// Launch an installed app via flatpak_installation_launch_full() with
// FLATPAK_LAUNCH_FLAGS_DO_NOT_REAP. Returns immediately; the launch runs on the
// reader's serial launch thread. On success posts the resulting FlatpakInstance
// as a 0x01 FpInstance payload followed by the 0xFF sentinel. On failure posts
// 0x02 if the app is not installed, or 0x03 if the installation could not be
// read or launch_full() itself failed.
void flatpak_reader_launch(void* handle, Dart_Port port, const char* app_id, const char* arch,
                           const char* branch, const char* commit);
// Terminate every running instance matching app_id, host-wide — flatpak
// instances are not scoped to an installation, so this also matches instances
// launched from the other installation. Prefers the sandboxed app process
// (FlatpakInstance child pid) over the outer bwrap pid, so the app sees the
// SIGTERM and bwrap follows it down; falls back to the bwrap pid when the child
// pid has not been published yet. Stale instances whose process has already
// exited are skipped. SIGTERM is escalated to SIGKILL after a grace period.
// Posts 0xFF if at least one instance was signalled, 0x02 if nothing matched,
// or 0x03 if instances matched but none could be signalled.
void flatpak_reader_stop(void* handle, Dart_Port port, const char* app_id);
// List running sandbox instances (FlatpakInstance) via flatpak_instance_get_all().
// Posts each as a 0x01 FpInstance payload, then the 0xFF sentinel.
void flatpak_reader_list_running(void* handle, Dart_Port port);
// Invalidate cached data so next list call returns fresh results.
void flatpak_reader_drop_caches(void* handle);

// ── User-installation remote management (no polkit required) ─────────────
void* flatpak_user_remote_create(Dart_Port result_port);
void flatpak_user_remote_destroy(void* handle);
void flatpak_user_remote_add(void* handle, const char* name, const uint8_t* config_buf,
                             int64_t config_len, bool if_not_exists);
// Parses the .flatpakrepo keyfile; extracts URL, GPG key, title automatically.
void flatpak_user_remote_add_from_file(void* handle, const char* name, const char* flatpakrepo_path,
                                       bool if_not_exists);
void flatpak_user_remote_modify(void* handle, const char* name, const uint8_t* changes_buf,
                                int64_t changes_len);
void flatpak_user_remote_remove(void* handle, const char* name, bool force);
// flatpak update --appstream --remote=<name> [--user]
// Calls flatpak_installation_update_remote_sync() for both.
// libflatpak escalates privilege for system installations automatically.
void flatpak_user_remote_update(void* handle, const char* name);

// ── Transaction worker (persistent, one per FlatpakInstallation) ──────────
// Owns a serial queue and a single dedicated thread. All FlatpakTransaction
// objects for this installation run one at a time — OSTree holds an exclusive
// repo lock for the duration of flatpak_transaction_run(). Transactions for
// different installations (user vs system) run in parallel because they have
// separate repo paths and therefore separate workers.
void* flatpak_worker_create(const char* installation);
void flatpak_worker_destroy(void* handle);
void flatpak_worker_cancel_current(void* handle);  // signals GCancellable

// ── Transaction handle (one per batch of operations) ─────────────────────
// Built up by calling flatpak_tx_add_* then submitted with flatpak_tx_submit.
// submit() is non-blocking: it enqueues the transaction on the worker and
// returns immediately. Progress (0x10) and completion (0x01/0x02) are posted
// to port when the transaction actually executes on the worker thread.
// A single port carries all messages; the discriminator byte distinguishes:
//   0x10 = TransactionProgress (in-flight)
//   0x01 = success sentinel (transaction complete)
//   0x02 = error (UTF-8 string, uint32_t length-prefix)
void* flatpak_tx_create(void* worker_handle, Dart_Port port);
void flatpak_tx_destroy(void* handle);  // only safe before submit
void flatpak_tx_add_install(void* handle, const char* remote, const char* ref);
void flatpak_tx_add_update(void* handle, const char* ref);  // "" = update all
void flatpak_tx_add_uninstall(void* handle, const char* ref);
void flatpak_tx_add_install_bundle(void* handle, const char* bundle_path);
void flatpak_tx_submit(void* handle);  // enqueues on worker; non-blocking

// ── System-installation remote management (polkit via libflatpak) ─────────
// Routes through flatpak_installation_{add,modify,remove}_remote().
// libflatpak escalates to polkit for system installs automatically.
void* flatpak_system_remote_create(Dart_Port result_port);
void flatpak_system_remote_destroy(void* handle);
void flatpak_system_remote_add(void* handle, const char* name, const uint8_t* config_buf,
                               int64_t config_len, bool if_not_exists);
void flatpak_system_remote_add_from_file(void* handle, const char* name,
                                         const char* flatpakrepo_path, bool if_not_exists);
void flatpak_system_remote_modify(void* handle, const char* name, const uint8_t* changes_buf,
                                  int64_t changes_len);
void flatpak_system_remote_remove(void* handle, const char* name, bool force);
void flatpak_system_remote_update(void* handle, const char* name);

// ── Update monitor (FlatpakMonitor GObject — libflatpak >= 1.5.3) ─────────
// Wraps flatpak_monitor_new(). Uses inotify on the installation directory.
// Posts 0x11 when "changed" fires and flatpak_monitor_update_is_due() == TRUE.
// Works from any host process; no D-Bus portal, no sandbox required.
void* flatpak_monitor_create(Dart_Port event_port, const char* installation);
void flatpak_monitor_close(void* handle);
void flatpak_monitor_destroy(void* handle);

#ifdef __cplusplus
}
#endif
