// app_metadata.h — pure readers over a Flatpak app metadata keyfile.
//
// These take a parsed GKeyFile rather than a FlatpakInstalledRef or
// FlatpakRemoteRef so that the interpretation of an app's metadata — which
// sockets it asks for, which extensions it requires and at which branches — is
// separable from talking to libflatpak, and can be tested against literal
// metadata without an installation, a remote, or an installed app.
#pragma once

#include <glib.h>

#include <string>
#include <vector>

// An extension the app's metadata declares as required at install time.
struct RequiredExtension {
    std::string id;
    // Branches that would satisfy the extension, in declaration order. Never
    // empty; front() is the one to install when none is present.
    std::vector<std::string> branches;
};

// Whether [Context] sockets= names socket_name.
//
// Matches whole list entries rather than substrings: "wayland" must not be
// satisfied by a hypothetical "fallback-wayland", the way a plain strstr()
// would have it. Negated entries ("!wayland", which overrides use) do not
// count as a request.
bool metadata_requests_socket(GKeyFile* kf, const char* socket_name);

// Extensions the metadata declares that must be present at app-install time,
// with the branches that satisfy each.
//
// Skips `no-autodownload=true` (optional, fetched on demand) and
// `subdirectories=true` (installable refs are <point>.<suffix> and have to be
// enumerated from the remote rather than named here).
//
// "versions" is a ;-list of acceptable branches, any one of which satisfies the
// extension. "version" is the single-branch form. Neither key means "same
// branch as the app", which is what app_branch supplies.
std::vector<RequiredExtension> required_extensions(GKeyFile* kf, const char* app_branch);
