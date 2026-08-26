// test_serial_queue.cpp — the serial work queue behind AppStream refresh.
//
// What matters here is not that items run, but the shutdown contract: every
// item that was accepted gets answered exactly once, either by running or by
// being cancelled. A Dart future is waiting on each of them, so an item that
// is silently dropped is a caller hung forever.

#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "serial_queue.h"

namespace {

using namespace std::chrono_literals;

// Records what ran and what was cancelled, in order.
struct Log {
    std::mutex mu;
    std::vector<std::string> ran;
    std::vector<std::string> cancelled;

    void recordRun(const std::string& s) {
        std::lock_guard lk(mu);
        ran.push_back(s);
    }
    void recordCancel(const std::string& s) {
        std::lock_guard lk(mu);
        cancelled.push_back(s);
    }
    std::vector<std::string> runs() {
        std::lock_guard lk(mu);
        return ran;
    }
    std::vector<std::string> cancels() {
        std::lock_guard lk(mu);
        return cancelled;
    }
    size_t total() {
        std::lock_guard lk(mu);
        return ran.size() + cancelled.size();
    }
};

// Polls until [pred] holds or the budget runs out, so the tests are not tuned
// to a machine's scheduling.
template <typename Pred>
bool waitFor(Pred pred, std::chrono::milliseconds budget = 5000ms) {
    const auto deadline = std::chrono::steady_clock::now() + budget;
    while (!pred()) {
        if (std::chrono::steady_clock::now() >= deadline) {
            return false;
        }
        std::this_thread::sleep_for(1ms);
    }
    return true;
}

}  // namespace

TEST(SerialQueue, RunsAPushedItem) {
    Log log;
    SerialQueue<std::string> q([&](const std::string& s) { log.recordRun(s); },
                               [&](const std::string& s) { log.recordCancel(s); });
    EXPECT_TRUE(q.push("a"));
    EXPECT_TRUE(waitFor([&] { return log.runs().size() == 1; }));
    EXPECT_EQ(log.runs()[0], "a");
    EXPECT_TRUE(log.cancels().empty());
}

TEST(SerialQueue, RunsItemsInOrder) {
    Log log;
    SerialQueue<std::string> q([&](const std::string& s) { log.recordRun(s); },
                               [&](const std::string& s) { log.recordCancel(s); });
    for (const auto* s : {"a", "b", "c", "d"}) {
        ASSERT_TRUE(q.push(s));
    }
    ASSERT_TRUE(waitFor([&] { return log.runs().size() == 4; }));
    EXPECT_EQ(log.runs(), (std::vector<std::string>{"a", "b", "c", "d"}));
}

// Serial, not concurrent: a refresh must never overlap another refresh.
TEST(SerialQueue, NeverRunsTwoItemsAtOnce) {
    std::atomic<int> inFlight{0};
    std::atomic<int> maxInFlight{0};
    std::atomic<int> done{0};
    {
        SerialQueue<int> q(
            [&](const int&) {
                const int now = ++inFlight;
                int prev = maxInFlight.load();
                while (now > prev && !maxInFlight.compare_exchange_weak(prev, now)) {
                }
                std::this_thread::sleep_for(2ms);
                --inFlight;
                ++done;
            },
            [](const int&) {});
        for (int i = 0; i < 8; i++) {
            ASSERT_TRUE(q.push(i));
        }
        ASSERT_TRUE(waitFor([&] { return done.load() == 8; }));
    }
    EXPECT_EQ(maxInFlight.load(), 1);
}

// push() returns immediately even while a slow item is running — the whole
// point of the queue is that the calling (Dart) thread does not block.
TEST(SerialQueue, PushDoesNotBlockBehindARunningItem) {
    std::atomic<bool> release{false};
    std::atomic<int> started{0};
    SerialQueue<int> q(
        [&](const int&) {
            ++started;
            while (!release.load()) {
                std::this_thread::sleep_for(1ms);
            }
        },
        [](const int&) {});

    ASSERT_TRUE(q.push(1));
    ASSERT_TRUE(waitFor([&] { return started.load() == 1; }));

    const auto before = std::chrono::steady_clock::now();
    EXPECT_TRUE(q.push(2));
    const auto elapsed = std::chrono::steady_clock::now() - before;
    EXPECT_LT(elapsed, 500ms);

    release.store(true);
}

// The shutdown contract: a queued item that never ran is cancelled, not
// dropped. Each one has a caller waiting on a reply.
TEST(SerialQueue, CancelsTheBacklogOnStop) {
    Log log;
    std::atomic<bool> release{false};
    std::atomic<int> started{0};
    {
        SerialQueue<std::string> q(
            [&](const std::string& s) {
                ++started;
                while (!release.load()) {
                    std::this_thread::sleep_for(1ms);
                }
                log.recordRun(s);
            },
            [&](const std::string& s) { log.recordCancel(s); });

        ASSERT_TRUE(q.push("running"));
        ASSERT_TRUE(waitFor([&] { return started.load() == 1; }));
        ASSERT_TRUE(q.push("queued1"));
        ASSERT_TRUE(q.push("queued2"));

        release.store(true);
        q.stop();
    }
    // The in-flight item finished; the two behind it were cancelled.
    EXPECT_EQ(log.runs(), (std::vector<std::string>{"running"}));
    EXPECT_EQ(log.cancels(), (std::vector<std::string>{"queued1", "queued2"}));
}

TEST(SerialQueue, EveryAcceptedItemIsAnsweredExactlyOnce) {
    Log log;
    {
        SerialQueue<std::string> q(
            [&](const std::string& s) {
                std::this_thread::sleep_for(1ms);
                log.recordRun(s);
            },
            [&](const std::string& s) { log.recordCancel(s); });
        for (int i = 0; i < 32; i++) {
            ASSERT_TRUE(q.push("item" + std::to_string(i)));
        }
        // Destructor stops mid-drain: some run, the rest cancel.
    }
    EXPECT_EQ(log.total(), 32u);
}

TEST(SerialQueue, PushAfterStopIsRefusedRatherThanDropped) {
    Log log;
    SerialQueue<std::string> q([&](const std::string& s) { log.recordRun(s); },
                               [&](const std::string& s) { log.recordCancel(s); });
    q.stop();

    EXPECT_FALSE(q.push("late"));
    // Refused means not taken: the queue did not answer it, so the caller must.
    EXPECT_TRUE(log.runs().empty());
    EXPECT_TRUE(log.cancels().empty());
}

TEST(SerialQueue, StoppedReflectsState) {
    SerialQueue<int> q([](const int&) {}, [](const int&) {});
    EXPECT_FALSE(q.stopped());
    q.stop();
    EXPECT_TRUE(q.stopped());
}

TEST(SerialQueue, StopIsIdempotent) {
    SerialQueue<int> q([](const int&) {}, [](const int&) {});
    q.stop();
    q.stop();
    q.stop();
    SUCCEED();  // no double-join, no terminate
}

TEST(SerialQueue, ConcurrentStopsAreSafe) {
    SerialQueue<int> q([](const int&) { std::this_thread::sleep_for(1ms); }, [](const int&) {});
    for (int i = 0; i < 8; i++) {
        q.push(i);
    }
    std::vector<std::thread> stoppers;
    stoppers.reserve(4);
    for (int i = 0; i < 4; i++) {
        stoppers.emplace_back([&q] { q.stop(); });
    }
    for (auto& t : stoppers) {
        t.join();
    }
    EXPECT_TRUE(q.stopped());
}

// Pushes arriving off several threads is the real shape: the Dart thread
// enqueues while the worker drains.
TEST(SerialQueue, AcceptsConcurrentPushes) {
    Log log;
    {
        SerialQueue<std::string> q([&](const std::string& s) { log.recordRun(s); },
                                   [&](const std::string& s) { log.recordCancel(s); });
        std::vector<std::thread> pushers;
        pushers.reserve(8);
        for (int t = 0; t < 8; t++) {
            pushers.emplace_back([&q, t] {
                for (int i = 0; i < 8; i++) {
                    q.push("t" + std::to_string(t) + "i" + std::to_string(i));
                }
            });
        }
        for (auto& t : pushers) {
            t.join();
        }
        ASSERT_TRUE(waitFor([&] { return log.total() == 64; }));
    }
    EXPECT_EQ(log.total(), 64u);
}

TEST(SerialQueue, IdleQueueTearsDownCleanly) {
    for (int i = 0; i < 8; i++) {
        SerialQueue<int> q([](const int&) {}, [](const int&) {});
        (void)q;
    }
    SUCCEED();
}

// An empty queue must park, not spin: the worker is idle for the whole life of
// a session that never refreshes a catalog.
TEST(SerialQueue, IdleQueueDoesNotRunAnything) {
    Log log;
    SerialQueue<std::string> q([&](const std::string& s) { log.recordRun(s); },
                               [&](const std::string& s) { log.recordCancel(s); });
    std::this_thread::sleep_for(30ms);
    EXPECT_EQ(log.total(), 0u);
}
