// child_reaper.h — one thread that reaps every child this library spawns.
//
// FLATPAK_LAUNCH_FLAGS_DO_NOT_REAP leaves the bwrap process as our child, so
// something in this process has to waitpid() it or it becomes a zombie for the
// lifetime of the host app. waitpid(-1) would be wrong in a library — it would
// steal exit statuses from whatever else the embedder has spawned — so we wait
// on the specific pid.
//
// One reaper thread serves every launched app. It parks in poll() over the
// launched children's pidfds and reaps with WNOHANG when one becomes readable,
// so a session that launches N apps costs one thread rather than N. The thread
// is started on the first add() and exits once the last child is reaped.
#pragma once

#include <poll.h>
#include <sys/types.h>

#include <mutex>
#include <thread>
#include <vector>

class ChildReaper {
   public:
    // The process-wide reaper. Deliberately leaked rather than a
    // function-local static with a destructor: loop() runs on its own thread
    // and the destructor below blocks until every outstanding child exits,
    // which at process teardown would mean waiting on apps the user is still
    // using. Leaking one object at exit is the cheaper trade.
    static ChildReaper& instance();

    // Test seam: an independent reaper, so a test is not entangled with the
    // process-wide instance or with children the embedder spawned.
    ChildReaper();

    // Stops the reaper thread and reaps every child still outstanding — which
    // means blocking until those children exit. Sound for a scoped reaper
    // whose children are short-lived; the process-wide instance is never
    // destroyed.
    ~ChildReaper();

    ChildReaper(const ChildReaper&) = delete;
    ChildReaper& operator=(const ChildReaper&) = delete;

    // Take ownership of reaping [pid]. Safe to call from any thread.
    void add(pid_t pid);

   private:
    struct Child {
        pid_t pid;
        int pidfd;
    };

    static int pidfd_open(pid_t pid);
    static void wait_for(pid_t pid);
    void wake();
    void loop();

    // Moves everything queued into [watched]. False when the loop should exit —
    // nothing left to watch, or a stop was requested.
    bool take_pending(std::vector<Child>& watched);

    // Reaps every child whose pidfd signalled in [fds], compacting the ones
    // still running to the front of [watched]. [offset] skips the wake pipe.
    static void reap_signalled(std::vector<Child>& watched, const std::vector<pollfd>& fds,
                               size_t offset);

    std::mutex mu_;
    std::vector<Child> pending_;
    bool running_ = false;
    bool stopping_ = false;

    // thread_ gets its own lock rather than riding on mu_, because the only
    // operation that needs it — join the outgoing loop, then install the new
    // one — must not hold mu_ (the loop takes mu_ on its way out, so joining
    // under it would deadlock).
    //
    // It cannot ride on running_ either. A freshly constructed std::thread is
    // already executing before the move-assignment that stores it completes,
    // so the new loop can drain, clear running_ and return while the assignment
    // is still in flight; a second add() would then see running_ == false and
    // touch thread_ concurrently. Move-assigning onto a still-joinable thread
    // calls std::terminate, which is exactly what that race produced.
    std::mutex thread_mu_;
    std::thread thread_;

    int wake_fds_[2]{-1, -1};
};
