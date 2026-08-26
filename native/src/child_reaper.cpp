// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Joel Winarske

#include "child_reaper.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

ChildReaper& ChildReaper::instance() {
    static auto* reaper = new ChildReaper();  // see the header: leaked on purpose
    return *reaper;
}

ChildReaper::ChildReaper() {
    // O_NONBLOCK on both ends: the reader drains until EAGAIN, and the writer must never
    // block the launching thread if the pipe fills.
    if (pipe2(wake_fds_, O_NONBLOCK | O_CLOEXEC) != 0) {
        wake_fds_[0] = wake_fds_[1] = -1;
    }
}

ChildReaper::~ChildReaper() {
    {
        std::lock_guard lk(mu_);
        stopping_ = true;
    }
    wake();
    {
        std::lock_guard tlk(thread_mu_);
        if (thread_.joinable()) {
            thread_.join();
        }
    }
    // Anything queued but never picked up by the loop is still ours to reap.
    std::vector<Child> leftover;
    {
        std::lock_guard lk(mu_);
        leftover.swap(pending_);
    }
    for (const auto& c : leftover) {
        wait_for(c.pid);
        close(c.pidfd);
    }
    if (wake_fds_[0] >= 0) {
        close(wake_fds_[0]);
        close(wake_fds_[1]);
    }
}

int ChildReaper::pidfd_open(pid_t pid) {
    return static_cast<int>(syscall(SYS_pidfd_open, pid, 0));
}

void ChildReaper::wait_for(pid_t pid) {
    int status = 0;
    // Retry on EINTR: an unrestarted waitpid() would abandon the child as a zombie for the
    // lifetime of the host process, which is exactly what this reaper exists to prevent. The
    // Dart VM's profiler delivers SIGPROF, and embedders install handlers of their own.
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
}

void ChildReaper::wake() {
    if (wake_fds_[1] >= 0) {
        const char b = 0;
        ssize_t ignored = write(wake_fds_[1], &b, 1);
        (void)ignored;
    }
}

void ChildReaper::add(pid_t pid) {
    int pidfd = pidfd_open(pid);
    if (pidfd < 0) {
        // No pidfd (pre-5.3 kernel, or the child is already gone). Fall back to a dedicated
        // blocking wait so the child is still reaped.
        std::thread([pid] { wait_for(pid); }).detach();
        return;
    }

    bool start = false;
    {
        std::lock_guard lk(mu_);
        if (stopping_) {
            // Shutting down: reap inline rather than queue onto a loop that is going away.
            std::thread([pid, pidfd] {
                wait_for(pid);
                close(pidfd);
            }).detach();
            return;
        }
        pending_.push_back({pid, pidfd});
        if (!running_) {
            running_ = true;
            start = true;
        }
    }
    if (start) {
        // Under thread_mu_, never mu_: see the header. The loop being joined has already
        // cleared running_, so it is on its way out and the join is immediate.
        std::lock_guard tlk(thread_mu_);
        if (thread_.joinable()) {
            thread_.join();
        }
        thread_ = std::thread(&ChildReaper::loop, this);
    }
    wake();
}

bool ChildReaper::take_pending(std::vector<Child>& watched) {
    std::lock_guard lk(mu_);
    watched.insert(watched.end(), pending_.begin(), pending_.end());
    pending_.clear();
    if (stopping_ || watched.empty()) {
        running_ = false;
        return false;
    }
    return true;
}

void ChildReaper::reap_signalled(std::vector<Child>& watched, const std::vector<pollfd>& fds,
                                 size_t offset) {
    size_t kept = 0;
    for (size_t i = 0; i < watched.size(); i++) {
        if (fds[i + offset].revents == 0) {
            watched[kept++] = watched[i];
            continue;
        }
        int reaped = 0;
        int status = 0;
        while ((reaped = waitpid(watched[i].pid, &status, WNOHANG)) < 0 && errno == EINTR) {
        }
        if (reaped == 0) {
            // Readable but not reapable — which a pidfd should never report, since POLLIN means
            // the process has already terminated. Keeping it in the set would spin (poll returns
            // immediately on a still-readable fd) and dropping it would leave the zombie this
            // exists to prevent, so hand it to a blocking waiter instead.
            pid_t orphan = watched[i].pid;
            std::thread([orphan] { wait_for(orphan); }).detach();
        }
        close(watched[i].pidfd);
    }
    watched.resize(kept);
}

void ChildReaper::loop() {
    std::vector<Child> watched;
    std::vector<pollfd> fds;

    while (take_pending(watched)) {
        fds.clear();
        fds.reserve(watched.size() + 1);
        if (wake_fds_[0] >= 0) {
            fds.push_back({wake_fds_[0], POLLIN, 0});
        }
        for (const auto& c : watched) {
            fds.push_back({c.pidfd, POLLIN, 0});
        }

        if (poll(fds.data(), fds.size(), -1) < 0) {
            if (errno == EINTR) {
                continue;
            }
            // poll() cannot recover. Reap what we hold on a detached thread rather than inline:
            // those children may still be alive, and this loop has already cleared running_, so
            // the next add() will try to join it — blocking here would hang the launching thread
            // for as long as a launched app keeps running.
            {
                std::lock_guard lk(mu_);
                running_ = false;
            }
            std::thread([orphans = std::move(watched)] {
                for (const auto& c : orphans) {
                    wait_for(c.pid);
                    close(c.pidfd);
                }
            }).detach();
            return;
        }

        const size_t offset = (wake_fds_[0] >= 0) ? 1 : 0;
        if (offset == 1 && (fds[0].revents & POLLIN) != 0) {
            char drain[64];
            while (read(wake_fds_[0], drain, sizeof(drain)) > 0) {
            }
        }
        reap_signalled(watched, fds, offset);
    }

    // Reached only via the stopping_/empty exit. Anything still held belongs to a reaper being
    // destroyed, so it is reaped inline — that blocking wait is the destructor contract the
    // header documents.
    for (const auto& c : watched) {
        wait_for(c.pid);
        close(c.pidfd);
    }
}
