// flatpak_bridge.cpp — C ABI entry points, init, and update monitor.

#include "flatpak_bridge.h"

#include <flatpak/flatpak.h>

#include <cstdio>
#include <cstring>

// ── Post helpers (local to this TU) ─────────────────────────────────────────

namespace {

void post_update_event(Dart_Port port) {
    uint8_t buf[1] = {0x11};
    Dart_CObject obj;
    obj.type = Dart_CObject_kTypedData;
    obj.value.as_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_typed_data.length = 1;
    obj.value.as_typed_data.values = buf;
    Dart_PostCObject_DL(port, &obj);
}

}  // anonymous namespace

// ── Update monitor ──────────────────────────────────────────────────────────
//
// Uses flatpak_installation_create_monitor() which returns a GFileMonitor
// on the installation directory. The "changed" signal fires when any file
// in the installation changes (installs, updates, uninstalls, config edits).

struct MonitorHandle {
    Dart_Port port;
    FlatpakInstallation* installation;
    GFileMonitor* file_monitor;
    gulong signal_id;
    GMainContext* context;
    GMainLoop* loop;
    GThread* thread;
    // Track last known app count to detect real state changes
    int last_app_count;
};

static int count_installed_apps(FlatpakInstallation* inst) {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GPtrArray) refs = flatpak_installation_list_installed_refs(inst, nullptr, &err);
    if (!refs) {
        return -1;
    }
    int count = 0;
    for (guint i = 0; i < refs->len; i++) {
        auto* ref = static_cast<FlatpakInstalledRef*>(refs->pdata[i]);
        if (flatpak_ref_get_kind(FLATPAK_REF(ref)) == FLATPAK_REF_KIND_APP) {
            count++;
        }
    }
    return count;
}

static void on_file_changed(GFileMonitor* /*monitor*/, GFile* /*file*/, GFile* /*other_file*/,
                            GFileMonitorEvent /*event_type*/, gpointer user_data) {
    auto* h = static_cast<MonitorHandle*>(user_data);
    int current = count_installed_apps(h->installation);
    if (current != h->last_app_count) {
        h->last_app_count = current;
        post_update_event(h->port);
    }
}

static gpointer monitor_thread_func(gpointer data) {
    auto* h = static_cast<MonitorHandle*>(data);
    g_main_context_push_thread_default(h->context);
    g_main_loop_run(h->loop);
    g_main_context_pop_thread_default(h->context);
    return nullptr;
}

static FlatpakInstallation* open_installation_for_monitor(const char* name) {
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

// ── C ABI ───────────────────────────────────────────────────────────────────

extern "C" {

void flatpak_bridge_init(void* dart_api_dl_data) {
    Dart_InitializeApiDL(dart_api_dl_data);
}

void* flatpak_monitor_create(Dart_Port event_port, const char* installation) {
    auto* inst = open_installation_for_monitor(installation);
    if (!inst) {
        return nullptr;
    }

    auto* h = new MonitorHandle{};
    h->port = event_port;
    h->installation = inst;
    h->file_monitor = nullptr;
    h->signal_id = 0;
    h->last_app_count = count_installed_apps(inst);
    h->context = g_main_context_new();
    h->loop = g_main_loop_new(h->context, FALSE);

    // Get the installation directory and create a GFileMonitor directly.
    g_autoptr(GError) err = nullptr;
    GFile* install_path = flatpak_installation_get_path(inst);

    g_main_context_push_thread_default(h->context);

    h->file_monitor =
        g_file_monitor_directory(install_path, G_FILE_MONITOR_WATCH_MOVES, nullptr, &err);
    if (h->file_monitor) {
        // Rate-limit to avoid flooding on rapid changes (e.g. during install)
        g_file_monitor_set_rate_limit(h->file_monitor, 500);  // 500ms
        h->signal_id = g_signal_connect(h->file_monitor, "changed", G_CALLBACK(on_file_changed), h);
        fprintf(stderr, "[flatpak_nc] monitor created on %s\n", g_file_get_path(install_path));
    } else {
        fprintf(stderr, "[flatpak_nc] monitor creation failed: %s\n",
                err ? err->message : "unknown error");
    }

    g_main_context_pop_thread_default(h->context);

    // Start the GMainLoop on a dedicated thread to dispatch signals
    h->thread = g_thread_new("flatpak-monitor", monitor_thread_func, h);

    return h;
}

void flatpak_monitor_close(void* handle) {
    auto* h = static_cast<MonitorHandle*>(handle);
    if (!h) {
        return;
    }

    if (h->loop) {
        g_main_loop_quit(h->loop);
    }

    if (h->thread) {
        g_thread_join(h->thread);
        h->thread = nullptr;
    }

    if (h->file_monitor && h->signal_id > 0) {
        g_signal_handler_disconnect(h->file_monitor, h->signal_id);
        h->signal_id = 0;
    }

    if (h->file_monitor) {
        g_file_monitor_cancel(h->file_monitor);
    }
}

void flatpak_monitor_destroy(void* handle) {
    auto* h = static_cast<MonitorHandle*>(handle);
    if (!h) {
        return;
    }

    flatpak_monitor_close(handle);

    if (h->file_monitor) {
        g_object_unref(h->file_monitor);
    }
    if (h->loop) {
        g_main_loop_unref(h->loop);
    }
    if (h->context) {
        g_main_context_unref(h->context);
    }
    if (h->installation) {
        g_object_unref(h->installation);
    }
    delete h;
}

}  // extern "C"
