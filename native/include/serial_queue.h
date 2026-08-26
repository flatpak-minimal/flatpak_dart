// serial_queue.h — one background thread draining a FIFO of work items.
//
// The bridge has several jobs that must not run on the Dart thread but must
// still run one at a time: a launch blocks while bubblewrap sets up a sandbox,
// an AppStream refresh pulls a whole catalog over the network. Each such job
// was previously an open-coded mutex + condition_variable + queue + shutdown
// drain, which is easy to get subtly wrong and — being welded to the object
// that owns it — impossible to test on its own.
//
// This is that shape, extracted: enqueue and return, run serially, and on
// shutdown hand the untouched backlog to a cancel callback so no caller is
// left waiting for a reply that will never come.
#pragma once

#include <condition_variable>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <utility>

/// A serial background queue. [Item] must be default-constructible and
/// movable.
template <typename Item>
class SerialQueue {
   public:
    using Handler = std::function<void(const Item&)>;

    /// Starts the worker thread. [run] handles each item in turn; [cancel]
    /// receives every item still queued when the queue stops, so a caller
    /// waiting on a reply always gets one.
    SerialQueue(Handler run, Handler cancel)
        : run_(std::move(run)), cancel_(std::move(cancel)), thread_(&SerialQueue::loop, this) {
    }

    ~SerialQueue() {
        stop();
    }

    SerialQueue(const SerialQueue&) = delete;
    SerialQueue& operator=(const SerialQueue&) = delete;

    /// Queues [item] and returns immediately. False when the queue has already
    /// stopped, in which case the item was *not* taken and answering it is the
    /// caller's job — silently dropping it would hang whoever is waiting.
    bool push(Item item) {
        {
            std::lock_guard lk(mu_);
            if (stop_) {
                return false;
            }
            queue_.push(std::move(item));
        }
        cv_.notify_one();
        return true;
    }

    /// Stops draining and joins the worker. An item already running finishes;
    /// the rest of the backlog goes to the cancel callback rather than being
    /// run, so shutdown does not have to wait out a queue of slow work.
    /// Idempotent, and safe to call from any thread.
    void stop() {
        {
            std::lock_guard lk(mu_);
            stop_ = true;
        }
        cv_.notify_one();
        // Its own lock: two concurrent stop() calls must not both join, and
        // joining under mu_ would deadlock against the loop's own use of it.
        std::lock_guard jlk(join_mu_);
        if (thread_.joinable()) {
            thread_.join();
        }
    }

    /// Whether stop() has been requested.
    bool stopped() const {
        std::lock_guard lk(mu_);
        return stop_;
    }

   private:
    void loop() {
        for (;;) {
            Item item;
            {
                std::unique_lock lk(mu_);
                cv_.wait(lk, [this] { return stop_ || !queue_.empty(); });
                if (stop_) {
                    std::queue<Item> pending;
                    pending.swap(queue_);
                    lk.unlock();
                    while (!pending.empty()) {
                        cancel_(pending.front());
                        pending.pop();
                    }
                    return;
                }
                item = std::move(queue_.front());
                queue_.pop();
            }
            // Outside the lock: a handler may be slow, and push() must not
            // block behind it.
            run_(item);
        }
    }

    Handler run_;
    Handler cancel_;

    mutable std::mutex mu_;
    std::condition_variable cv_;
    std::queue<Item> queue_;
    bool stop_ = false;

    std::mutex join_mu_;
    std::thread thread_;
};
