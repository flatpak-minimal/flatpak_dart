// test_app_metadata.cpp — tests for the pure readers over an app's metadata
// keyfile. No installation, no remote, no installed app: metadata in, answers
// out, so the interpretation rules are pinned independently of libflatpak.

#include <gtest/gtest.h>

#include <string>
#include <vector>

#include "app_metadata.h"

namespace {

// Parses literal metadata the way the reader does before calling into these.
class KeyFile {
   public:
    explicit KeyFile(const std::string& text) : kf_(g_key_file_new()) {
        loaded_ = g_key_file_load_from_data(kf_, text.c_str(), text.size(), G_KEY_FILE_NONE,
                                            nullptr) != FALSE;
    }
    ~KeyFile() {
        g_key_file_unref(kf_);
    }
    KeyFile(const KeyFile&) = delete;
    KeyFile& operator=(const KeyFile&) = delete;

    GKeyFile* get() const {
        return kf_;
    }
    bool loaded() const {
        return loaded_;
    }

   private:
    GKeyFile* kf_;
    bool loaded_ = false;
};

std::vector<std::string> ids(const std::vector<RequiredExtension>& exts) {
    std::vector<std::string> out;
    out.reserve(exts.size());
    for (const auto& e : exts) {
        out.push_back(e.id);
    }
    return out;
}

const RequiredExtension* find(const std::vector<RequiredExtension>& exts, const std::string& id) {
    for (const auto& e : exts) {
        if (e.id == id) {
            return &e;
        }
    }
    return nullptr;
}

}  // namespace

// ── metadata_requests_socket ────────────────────────────────────────────────

TEST(MetadataRequestsSocket, FindsARequestedSocket) {
    KeyFile kf("[Context]\nsockets=x11;wayland;pulseaudio;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_TRUE(metadata_requests_socket(kf.get(), "wayland"));
    EXPECT_TRUE(metadata_requests_socket(kf.get(), "x11"));
    EXPECT_TRUE(metadata_requests_socket(kf.get(), "pulseaudio"));
}

TEST(MetadataRequestsSocket, MissingSocketIsNotRequested) {
    KeyFile kf("[Context]\nsockets=x11;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(kf.get(), "wayland"));
}

TEST(MetadataRequestsSocket, NoContextSectionIsNotRequested) {
    KeyFile kf("[Application]\nname=org.x.Y\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(kf.get(), "wayland"));
}

TEST(MetadataRequestsSocket, NoSocketsKeyIsNotRequested) {
    KeyFile kf("[Context]\ndevices=dri;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(kf.get(), "wayland"));
}

// A substring match would report an app that asks only for "fallback-x11" as
// having requested "x11", and would let a socket named "...wayland" satisfy a
// wayland-only filter.
TEST(MetadataRequestsSocket, DoesNotMatchOnSubstrings) {
    KeyFile kf("[Context]\nsockets=fallback-x11;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(kf.get(), "x11"));
    EXPECT_TRUE(metadata_requests_socket(kf.get(), "fallback-x11"));
}

TEST(MetadataRequestsSocket, NegatedSocketIsNotARequest) {
    KeyFile kf("[Context]\nsockets=!wayland;x11;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(kf.get(), "wayland"));
    EXPECT_TRUE(metadata_requests_socket(kf.get(), "x11"));
}

TEST(MetadataRequestsSocket, NullArgumentsAreSafe) {
    KeyFile kf("[Context]\nsockets=wayland;\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_FALSE(metadata_requests_socket(nullptr, "wayland"));
    EXPECT_FALSE(metadata_requests_socket(kf.get(), nullptr));
}

// ── required_extensions ─────────────────────────────────────────────────────

TEST(RequiredExtensions, NoExtensionsYieldsNothing) {
    KeyFile kf("[Application]\nname=org.x.Y\nruntime=org.freedesktop.Platform/x86_64/23.08\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_TRUE(required_extensions(kf.get(), "stable").empty());
}

TEST(RequiredExtensions, InheritsTheAppBranchWhenNoVersionIsNamed) {
    KeyFile kf("[Application]\nname=org.x.Y\n\n[Extension org.x.Y.Plugin]\ndirectory=lib/plugin\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    EXPECT_EQ(exts[0].id, "org.x.Y.Plugin");
    ASSERT_EQ(exts[0].branches.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "stable");
}

TEST(RequiredExtensions, SingularVersionOverridesTheAppBranch) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversion=1.4\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    ASSERT_EQ(exts[0].branches.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "1.4");
}

TEST(RequiredExtensions, PluralVersionsListsEveryAcceptableBranch) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversions=23.08;24.08;\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    ASSERT_EQ(exts[0].branches.size(), 2u);
    EXPECT_EQ(exts[0].branches[0], "23.08");
    EXPECT_EQ(exts[0].branches[1], "24.08");
}

// "versions" wins outright — the singular key is the fallback spelling, not an
// extra candidate to append.
TEST(RequiredExtensions, PluralVersionsWinsOverSingular) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversion=1.0\nversions=23.08;24.08;\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    ASSERT_EQ(exts[0].branches.size(), 2u);
    EXPECT_EQ(exts[0].branches[0], "23.08");
}

TEST(RequiredExtensions, EmptyVersionsEntriesAreIgnored) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversions=;23.08;;\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    ASSERT_EQ(exts[0].branches.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "23.08");
}

TEST(RequiredExtensions, EmptyVersionFallsBackToTheAppBranch) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversion=\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 1u);
    ASSERT_EQ(exts[0].branches.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "stable");
}

TEST(RequiredExtensions, SkipsNoAutodownload) {
    KeyFile kf(
        "[Extension org.x.Y.Required]\nversion=1.0\n"
        "[Extension org.x.Y.Optional]\nversion=1.0\nno-autodownload=true\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_EQ(ids(required_extensions(kf.get(), "stable")),
              std::vector<std::string>{"org.x.Y.Required"});
}

TEST(RequiredExtensions, NoAutodownloadFalseIsStillRequired) {
    KeyFile kf("[Extension org.x.Y.Plugin]\nversion=1.0\nno-autodownload=false\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_EQ(required_extensions(kf.get(), "stable").size(), 1u);
}

// subdirectories=true means the installable refs are <point>.<suffix>, which
// have to be enumerated from the remote — the group itself names nothing that
// can be installed.
TEST(RequiredExtensions, SkipsSubdirectories) {
    KeyFile kf("[Extension org.freedesktop.Platform.GL]\nversion=1.4\nsubdirectories=true\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_TRUE(required_extensions(kf.get(), "stable").empty());
}

TEST(RequiredExtensions, IgnoresNonExtensionGroups) {
    KeyFile kf(
        "[Application]\nname=org.x.Y\n"
        "[Context]\nsockets=wayland;\n"
        "[Extensions]\nfoo=bar\n"
        "[Extension org.x.Y.Plugin]\nversion=1.0\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_EQ(ids(required_extensions(kf.get(), "stable")),
              std::vector<std::string>{"org.x.Y.Plugin"});
}

TEST(RequiredExtensions, GroupWithNoIdNamesNothing) {
    KeyFile kf("[Extension ]\nversion=1.0\n");
    ASSERT_TRUE(kf.loaded());
    EXPECT_TRUE(required_extensions(kf.get(), "stable").empty());
}

TEST(RequiredExtensions, HandlesSeveralExtensions) {
    KeyFile kf(
        "[Extension org.x.Y.A]\nversion=1.0\n"
        "[Extension org.x.Y.B]\nversions=2.0;2.1;\n"
        "[Extension org.x.Y.C]\ndirectory=lib/c\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "stable");
    ASSERT_EQ(exts.size(), 3u);
    EXPECT_EQ(find(exts, "org.x.Y.A")->branches[0], "1.0");
    EXPECT_EQ(find(exts, "org.x.Y.B")->branches.size(), 2u);
    EXPECT_EQ(find(exts, "org.x.Y.C")->branches[0], "stable");
}

TEST(RequiredExtensions, NullKeyFileYieldsNothing) {
    EXPECT_TRUE(required_extensions(nullptr, "stable").empty());
}

// The reader passes safe_str(flatpak_ref_get_branch(...)), which is "" when the
// ref carries no branch. That must not crash or produce a garbage branch.
TEST(RequiredExtensions, EmptyAppBranchIsCarriedThrough) {
    KeyFile kf("[Extension org.x.Y.Plugin]\ndirectory=lib/plugin\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), "");
    ASSERT_EQ(exts.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "");
}

TEST(RequiredExtensions, NullAppBranchIsSafe) {
    KeyFile kf("[Extension org.x.Y.Plugin]\ndirectory=lib/plugin\n");
    ASSERT_TRUE(kf.loaded());
    const auto exts = required_extensions(kf.get(), nullptr);
    ASSERT_EQ(exts.size(), 1u);
    EXPECT_EQ(exts[0].branches[0], "");
}
