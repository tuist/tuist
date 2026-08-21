//! Lazy worker pool with write-ahead-friendly drain semantics; used by the
//! uploader to run publications off the build's critical path.

use std::collections::{HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};

type ProcessFn = std::sync::Arc<dyn Fn(Vec<u8>) + Send + Sync>;

pub struct Prefetcher {
    queue: Mutex<VecDeque<Vec<u8>>>,
    cvar: Condvar,
    shutdown: AtomicBool,
    draining: AtomicBool,
    inflight: AtomicU64,
    seen: Mutex<HashSet<Vec<u8>>>,
    workers: Mutex<Vec<std::thread::JoinHandle<()>>>,
    // Workers spawn on first enqueue: most compiler processes never touch the
    // remote, and eagerly spinning up pools in ~1000 short-lived frontends
    // per build is measurable overhead.
    starter: Mutex<Option<(usize, ProcessFn)>>,
}

/// Balances an inflight increment: dropping it decrements the counter under the
/// queue lock and wakes any drain waiter. Making the decrement a Drop guard
/// keeps it panic-safe — if the post-process cleanup below panics (e.g. a
/// poisoned lock), unwinding still runs the decrement, so `drain_stop` cannot be
/// left waiting on a counter that never returns to zero.
struct InflightGuard<'a> {
    prefetcher: &'a Prefetcher,
}

impl Drop for InflightGuard<'_> {
    fn drop(&mut self) {
        // Decrement under the lock so a drain check can't miss the wakeup
        // between reading inflight and parking on the condvar. Recover from a
        // poisoned lock rather than re-panicking: the decrement must run or
        // drain_stop hangs.
        let _queue = self
            .prefetcher
            .queue
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.prefetcher.inflight.fetch_sub(1, Ordering::AcqRel);
        self.prefetcher.cvar.notify_all();
    }
}

impl Prefetcher {
    pub fn new() -> Self {
        Self {
            queue: Mutex::new(VecDeque::new()),
            cvar: Condvar::new(),
            shutdown: AtomicBool::new(false),
            draining: AtomicBool::new(false),
            inflight: AtomicU64::new(0),
            seen: Mutex::new(HashSet::new()),
            workers: Mutex::new(Vec::new()),
            starter: Mutex::new(None),
        }
    }

    /// Registers the worker configuration; workers spawn lazily on the first
    /// enqueue. `process` runs on plain threads; the caller guarantees the
    /// backing state outlives the workers by joining them via `stop` or
    /// `drain_stop` before teardown.
    pub fn configure<F>(&self, count: usize, process: F)
    where
        F: Fn(Vec<u8>) + Send + Sync + 'static,
    {
        *self.starter.lock().unwrap() = Some((count, std::sync::Arc::new(process)));
    }

    fn ensure_started(&self) {
        let Some((count, process)) = self.starter.lock().unwrap().take() else {
            return;
        };
        let mut workers = self.workers.lock().unwrap();
        for _ in 0..count.max(1) {
            let this: &'static Prefetcher = unsafe { &*(self as *const Prefetcher) };
            let process = std::sync::Arc::clone(&process);
            workers.push(std::thread::spawn(move || loop {
                let digest = {
                    let mut queue = this.queue.lock().unwrap();
                    loop {
                        if this.shutdown.load(Ordering::Acquire) {
                            return;
                        }
                        if let Some(digest) = queue.pop_front() {
                            this.inflight.fetch_add(1, Ordering::AcqRel);
                            break digest;
                        }
                        // Draining: exit only once nothing is queued AND no
                        // peer is mid-process (it may still enqueue children).
                        if this.draining.load(Ordering::Acquire)
                            && this.inflight.load(Ordering::Acquire) == 0
                        {
                            this.cvar.notify_all();
                            return;
                        }
                        queue = this.cvar.wait(queue).unwrap();
                    }
                };
                // The decrement (and its drain wakeup) now rides on this guard's
                // Drop, so it runs even if process() or the cleanup below panics.
                let _inflight = InflightGuard { prefetcher: this };
                let key = digest.clone();
                let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| process(digest)));
                // Drop the item from `seen` once processed: dedup is meant to
                // collapse concurrent/pending duplicates, not to permanently
                // block a re-enqueue. The proxy keeps a failed publication's
                // write-ahead record and the sweep re-enqueues the same path;
                // without this, that retry is silently dropped until the proxy
                // restarts. Also bounds `seen` in the long-lived proxy.
                this.seen.lock().unwrap().remove(&key);
            }));
        }
    }

    pub fn enqueue(&self, digest: Vec<u8>) {
        if digest.is_empty() || self.shutdown.load(Ordering::Acquire) {
            return;
        }
        if !self.seen.lock().unwrap().insert(digest.clone()) {
            return;
        }
        self.ensure_started();
        self.queue.lock().unwrap().push_back(digest);
        self.cvar.notify_one();
    }

    /// Drains for at most `timeout`, then stops workers and returns whatever
    /// is still queued so the caller can persist it. Keeps process exit off
    /// the build's critical path: a compiler frontend spends at most the
    /// timeout here instead of flushing its whole upload backlog.
    pub fn drain_stop_timeout(&self, timeout: std::time::Duration) -> Vec<Vec<u8>> {
        self.draining.store(true, Ordering::Release);
        self.cvar.notify_all();
        let deadline = std::time::Instant::now() + timeout;
        {
            let mut queue = self.queue.lock().unwrap();
            loop {
                if queue.is_empty() && self.inflight.load(Ordering::Acquire) == 0 {
                    break;
                }
                let now = std::time::Instant::now();
                if now >= deadline {
                    break;
                }
                let (q, _timed_out) = self.cvar.wait_timeout(queue, deadline - now).unwrap();
                queue = q;
            }
        }
        // Stop workers regardless; each finishes its current item, so join is
        // bounded by one in-flight operation.
        self.shutdown.store(true, Ordering::Release);
        self.cvar.notify_all();
        let workers = std::mem::take(&mut *self.workers.lock().unwrap());
        for worker in workers {
            let _ = worker.join();
        }
        self.queue.lock().unwrap().drain(..).collect()
    }

    /// Blocks until nothing is queued and no worker is mid-item, for at most
    /// `timeout`, reporting whether it got there.
    ///
    /// Unlike `drain_stop_timeout` this leaves the pool RUNNING. The caller is
    /// the long-lived proxy answering a drain request, which keeps serving
    /// after the wait: stopping the workers there would leave every later
    /// publication on that machine queued behind a pool that never runs again.
    pub fn wait_idle(&self, timeout: std::time::Duration) -> bool {
        let deadline = std::time::Instant::now() + timeout;
        let mut queue = self.queue.lock().unwrap();
        loop {
            // A worker pops and increments `inflight` under this same lock, so
            // the pair is read consistently: there is no window where an item
            // is in neither the queue nor the counter.
            if queue.is_empty() && self.inflight.load(Ordering::Acquire) == 0 {
                return true;
            }
            let now = std::time::Instant::now();
            if now >= deadline {
                return false;
            }
            let (guard, _timed_out) = self.cvar.wait_timeout(queue, deadline - now).unwrap();
            queue = guard;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::time::Duration;

    /// Workers fabricate a `'static` reference to the pool and are only joined
    /// by `drain_stop_timeout`, which `wait_idle` deliberately does not call —
    /// so a pool waited on this way must outlive the test.
    fn leaked_pool() -> &'static Prefetcher {
        Box::leak(Box::new(Prefetcher::new()))
    }

    #[test]
    fn wait_idle_returns_when_the_pool_has_caught_up_and_leaves_it_serving() {
        let pool = leaked_pool();
        let processed = Arc::new(AtomicU64::new(0));
        let sink = Arc::clone(&processed);
        pool.configure(2, move |item| {
            std::thread::sleep(Duration::from_millis(10));
            sink.fetch_add(u64::from(item[0]), Ordering::Relaxed);
        });
        for item in 1..=4u8 {
            pool.enqueue(vec![item]);
        }

        assert!(pool.wait_idle(Duration::from_secs(10)));
        assert_eq!(processed.load(Ordering::Relaxed), 10);

        // The pool is still live. A `drain_stop_timeout` here would have made
        // this enqueue unrunnable, which is why the proxy cannot use that one.
        pool.enqueue(vec![5]);
        assert!(pool.wait_idle(Duration::from_secs(10)));
        assert_eq!(processed.load(Ordering::Relaxed), 15);
    }

    #[test]
    fn wait_idle_gives_up_at_its_deadline_without_cancelling_the_work() {
        let pool = leaked_pool();
        let processed = Arc::new(AtomicU64::new(0));
        let sink = Arc::clone(&processed);
        pool.configure(1, move |_| {
            std::thread::sleep(Duration::from_millis(300));
            sink.fetch_add(1, Ordering::Relaxed);
        });
        pool.enqueue(vec![1]);

        assert!(
            !pool.wait_idle(Duration::from_millis(20)),
            "an item still in flight is not quiescence"
        );
        assert!(pool.wait_idle(Duration::from_secs(10)));
        assert_eq!(
            processed.load(Ordering::Relaxed),
            1,
            "the timed-out wait left the item running rather than dropping it"
        );
    }
}
