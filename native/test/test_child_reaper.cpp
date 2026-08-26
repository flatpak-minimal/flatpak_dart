// test_child_reaper.cpp — the reaper is what stands between a long session of
// app launches and a process full of zombies, so these fork real children and
// assert they are actually reaped.
//
// The assertion is always the same, and it is always made through /proc: a pid
// the reaper has collected loses its /proc entry, while an unreaped one sits in
// Z state forever. The test deliberately never calls waitpid() on a pid it has
// handed to the reaper — there is exactly one exit status and whoever calls
// waitpid() first consumes it, so a test that waited would race the very thread
// it is trying to observe and would fail whenever it won.

#include <errno.h>
#include <gtest/gtest.h>
#include <sys/wait.h>
#include <unistd.h>

#include <chrono>
#include <string>
#include <thread>
#include <vector>

#include "child_reaper.h"

namespace {

using namespace std::chrono_literals;

// A child that exits immediately with the given status.
pid_t spawn_exiting(int status = 0) {
    pid_t pid = fork();
    if (pid == 0) {
        _exit(status);
    }
    return pid;
}

// A child that lives until it is killed.
pid_t spawn_sleeping() {
    pid_t pid = fork();
    if (pid == 0) {
        for (;;) {
            pause();
        }
    }
    return pid;
}

// Whether the kernel still has an entry for [pid] at all. A running child has
// one, a zombie has one, and a reaped child has none — so its disappearance is
// what "the reaper collected it" looks like from outside.
bool process_exists(pid_t pid) {
    const std::string path = "/proc/" + std::to_string(pid);
    return access(path.c_str(), F_OK) == 0;
}

// True once [pid] has been reaped. Polls rather than sleeping a fixed interval
// so the test is not tuned to a machine's scheduling.
//
// Polling for *absence* is also what makes pid reuse harmless here: a recycled
// pid can only delay the observation, never fake one.
bool reaped_within(pid_t pid, std::chrono::milliseconds budget) {
    const auto deadline = std::chrono::steady_clock::now() + budget;
    for (;;) {
        if (!process_exists(pid)) {
            return true;
        }
        if (std::chrono::steady_clock::now() >= deadline) {
            return false;  // still running, or still a zombie nobody collected
        }
        std::this_thread::sleep_for(1ms);
    }
}

// Whether the kernel still shows [pid] in the zombie state.
bool is_zombie(pid_t pid) {
    std::string path = "/proc/" + std::to_string(pid) + "/stat";
    FILE* f = std::fopen(path.c_str(), "r");
    if (!f) {
        return false;
    }
    char comm[256] = {};
    char state = 0;
    int scanned = std::fscanf(f, "%*d %255s %c", comm, &state);
    std::fclose(f);
    return scanned == 2 && state == 'Z';
}

}  // namespace

TEST(ChildReaper, ReapsASingleChild) {
    ChildReaper reaper;
    pid_t pid = spawn_exiting();
    ASSERT_GT(pid, 0);
    reaper.add(pid);
    EXPECT_TRUE(reaped_within(pid, 2000ms));
}

TEST(ChildReaper, LeavesNoZombieBehind) {
    ChildReaper reaper;
    pid_t pid = spawn_exiting();
    ASSERT_GT(pid, 0);
    reaper.add(pid);
    ASSERT_TRUE(reaped_within(pid, 2000ms));
    EXPECT_FALSE(is_zombie(pid));
}

// The whole point of the pidfd/poll design: N launched apps cost one thread,
// and every one of them is still collected.
TEST(ChildReaper, ReapsManyChildrenOnOneThread) {
    ChildReaper reaper;
    std::vector<pid_t> pids;
    for (int i = 0; i < 24; i++) {
        pid_t pid = spawn_exiting(i % 2);
        ASSERT_GT(pid, 0);
        pids.push_back(pid);
        reaper.add(pid);
    }
    for (pid_t pid : pids) {
        EXPECT_TRUE(reaped_within(pid, 5000ms)) << "pid " << pid << " was not reaped";
    }
}

// add() from several threads at once is the real shape: launches arrive off the
// launch thread while the loop is mid-poll.
TEST(ChildReaper, AcceptsConcurrentAdds) {
    ChildReaper reaper;
    std::vector<pid_t> pids(16);
    for (auto& pid : pids) {
        pid = spawn_exiting();
        ASSERT_GT(pid, 0);
    }

    std::vector<std::thread> adders;
    adders.reserve(pids.size());
    for (pid_t pid : pids) {
        adders.emplace_back([&reaper, pid] { reaper.add(pid); });
    }
    for (auto& t : adders) {
        t.join();
    }

    for (pid_t pid : pids) {
        EXPECT_TRUE(reaped_within(pid, 5000ms)) << "pid " << pid << " was not reaped";
    }
}

// A child added after the loop has drained and exited must restart it, rather
// than sit in the queue forever.
TEST(ChildReaper, RestartsAfterTheLoopDrains) {
    ChildReaper reaper;

    pid_t first = spawn_exiting();
    ASSERT_GT(first, 0);
    reaper.add(first);
    ASSERT_TRUE(reaped_within(first, 2000ms));

    // Give the loop time to observe an empty set and return.
    std::this_thread::sleep_for(50ms);

    pid_t second = spawn_exiting();
    ASSERT_GT(second, 0);
    reaper.add(second);
    EXPECT_TRUE(reaped_within(second, 2000ms));
}

// A child that outlives the add and exits later still gets collected — the loop
// has to be parked in poll() on its pidfd, not polling once and giving up.
TEST(ChildReaper, ReapsAChildThatExitsLater) {
    ChildReaper reaper;
    pid_t pid = spawn_sleeping();
    ASSERT_GT(pid, 0);
    reaper.add(pid);

    std::this_thread::sleep_for(100ms);
    ASSERT_EQ(kill(pid, SIGTERM), 0);

    EXPECT_TRUE(reaped_within(pid, 5000ms));
}

// Destroying a reaper that still holds a child must collect it rather than
// abandon it — the scoped-reaper contract the header documents.
TEST(ChildReaper, DestructorReapsOutstandingChildren) {
    pid_t pid = spawn_sleeping();
    ASSERT_GT(pid, 0);
    {
        ChildReaper reaper;
        reaper.add(pid);
        std::this_thread::sleep_for(50ms);
        ASSERT_EQ(kill(pid, SIGTERM), 0);
    }  // ~ChildReaper blocks until the child is reaped
    EXPECT_TRUE(reaped_within(pid, 100ms));
    EXPECT_FALSE(is_zombie(pid));
}

// Constructing and destroying a reaper that never saw a child must not hang or
// leave a thread behind.
TEST(ChildReaper, IdleReaperTearsDownCleanly) {
    for (int i = 0; i < 4; i++) {
        ChildReaper reaper;
        (void)reaper;
    }
    SUCCEED();
}

// The process-wide instance is the one the launch path uses; it must be usable
// and stable across calls.
TEST(ChildReaper, SharedInstanceIsASingleton) {
    EXPECT_EQ(&ChildReaper::instance(), &ChildReaper::instance());

    pid_t pid = spawn_exiting();
    ASSERT_GT(pid, 0);
    ChildReaper::instance().add(pid);
    EXPECT_TRUE(reaped_within(pid, 2000ms));
}
