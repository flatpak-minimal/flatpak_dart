// flatpak_bridge.cpp — C ABI entry points, init, and update monitor.

#include "flatpak_bridge.h"
#include <flatpak/flatpak.h>
#include <cstring>

// ── Post helpers (local to this TU) ─────────────────────────────────────────

namespace {

void post_update_event(Dart_Port port) {
    auto* buf = new uint8_t[1];
    buf[0] = 0x11;

    Dart_CObject obj;
    obj.type = Dart_CObject_kExternalTypedData;
    obj.value.as_external_typed_data.type = Dart_TypedData_kUint8;
    obj.value.as_external_typed_data.length = 1;
    obj.value.as_external_typed_data.data = buf;
    obj.value.as_external_typed_data.peer = buf;
    obj.value.as_external_typed_data.callback =
        [](void*, void* peer) { delete[] static_cast<uint8_t*>(peer); };

    Dart_PostCObject_DL(port, &obj);
}

}  // anonymous namespace

// ── Update monitor ──────────────────────────────────────────────────────────
//
// Wraps FlatpakMonitor (libflatpak >= 1.5.3). Uses inotify on the
// installation directory. Posts 0x11 when "changed" fires.
// Works from any host process; no D-Bus portal, no sandbox required.

struct MonitorHandle {
    Dart_Port           port;
    FlatpakInstallation* installation;
    gulong              signal_id;
    GMainContext*       context;
    GMainLoop*          loop;
    GThread*            thread;
};

static gboolean on_monitor_changed(FlatpakInstallation* /*inst*/,
                                    gpointer user_data) {
    auto* h = static_cast<MonitorHandle*>(user_data);
    post_update_event(h->port);
    return G_SOURCE_CONTINUE;
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
    if (!inst) { return nullptr; }

    auto* h = new MonitorHandle{};
    h->port         = event_port;
    h->installation = inst;
    h->context      = g_main_context_new();
    h->loop         = g_main_loop_new(h->context, FALSE);

    // FlatpakInstallation emits "changed" when refs change on disk.
    // We connect in the monitor's dedicated GMainContext.
    g_main_context_push_thread_default(h->context);
    h->signal_id = g_signal_connect(inst, "changed",
        G_CALLBACK(on_monitor_changed), h);
    g_main_context_pop_thread_default(h->context);

    // Start the GMainLoop on a dedicated thread
    h->thread = g_thread_new("flatpak-monitor", monitor_thread_func, h);

    return h;
}

void flatpak_monitor_close(void* handle) {
    auto* h = static_cast<MonitorHandle*>(handle);
    if (!h) { return; }

    // Stop the main loop — this causes monitor_thread_func to return
    if (h->loop) {
        g_main_loop_quit(h->loop);
    }

    // Wait for the thread to finish
    if (h->thread) {
        g_thread_join(h->thread);
        h->thread = nullptr;
    }

    // Disconnect the signal
    if (h->installation && h->signal_id > 0) {
        g_signal_handler_disconnect(h->installation, h->signal_id);
        h->signal_id = 0;
    }
}

void flatpak_monitor_destroy(void* handle) {
    auto* h = static_cast<MonitorHandle*>(handle);
    if (!h) { return; }

    // Ensure closed first
    flatpak_monitor_close(handle);

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
