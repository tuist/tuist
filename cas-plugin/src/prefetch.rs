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
    // Signalled whenever an item leaves `seen`, for `run_now` waiting on a copy
    // a worker is processing.
    released: Condvar,
    workers: Mutex<Vec<std::thread::JoinHandle<()>>>,
    // Workers spawn on first enqueue: most compiler processes never touch the
    // remote, and eagerly spinning up pools in ~1000 short-lived frontends
    // per build is measurable overhead.
    starter: Mutex<Option<(usize, ProcessFn)>>,
    // The same function, kept for `run_now`: `starter` hands its copy to the
    // workers when they spawn.
    process: Mutex<Option<ProcessFn>>,
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
            released: Condvar::new(),
            workers: Mutex::new(Vec::new()),
            starter: Mutex::new(None),
            process: Mutex::new(None),
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
        let process: ProcessFn = std::sync::Arc::new(process);
        *self.process.lock().unwrap() = Some(std::sync::Arc::clone(&process));
        *self.starter.lock().unwrap() = Some((count, process));
    }

    fn ensure_started(&self) {
        let Some((count, process)) = self.starter.lock().unwrap().take() else { return };
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
                this.release(&key);
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

    /// Processes `item` on the calling thread and returns once it has been
    /// processed, reporting whether it could be. A copy already queued is taken
    /// out of the queue and processed here, and a copy a worker is processing is
    /// waited for rather than processed twice. An `enqueue` of the item made
    /// meanwhile is dropped, as for any queued item.
    ///
    /// The caller is a build waiting on its own upload. Queued behind the pool,
    /// it would wait out every background item ahead of it, and its concurrency
    /// is already bounded by how many compiles the build runs at once.
    pub fn run_now(&self, item: Vec<u8>) -> bool {
        if item.is_empty() || self.shutdown.load(Ordering::Acquire) {
            return false;
        }
        let Some(process) = self.process.lock().unwrap().clone() else {
            return false;
        };
        {
            let mut seen = self.seen.lock().unwrap();
            if !seen.insert(item.clone()) {
                // Lock order is `seen` then `queue`; nothing takes them the other
                // way round.
                let mut queue = self.queue.lock().unwrap();
                match queue.iter().position(|queued| queued == &item) {
                    Some(position) => {
                        queue.remove(position);
                    }
                    None => {
                        drop(queue);
                        while seen.contains(&item) {
                            seen = self.released.wait(seen).unwrap();
                        }
                        return true;
                    }
                }
            }
        }
        let key = item.clone();
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| process(item)));
        self.release(&key);
        true
    }

    fn release(&self, item: &[u8]) {
        self.seen
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(item);
        self.released.notify_all();
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

    #[test]
    fn run_now_processes_on_the_calling_thread() {
        let pool = leaked_pool();
        let caller = std::thread::current().id();
        let ran_on: Arc<Mutex<Option<std::thread::ThreadId>>> = Arc::new(Mutex::new(None));
        let sink = Arc::clone(&ran_on);
        pool.configure(1, move |_| {
            *sink.lock().unwrap() = Some(std::thread::current().id());
        });

        assert!(pool.run_now(vec![1]));
        assert_eq!(*ran_on.lock().unwrap(), Some(caller));
    }

    /// A sweep re-enqueues a record the build is already waiting on. Publishing
    /// it twice at once would upload the same graph twice, so the queued copy
    /// is dropped while the inline one runs.
    #[test]
    fn an_item_running_now_is_not_queued_again() {
        let pool = leaked_pool();
        let processed = Arc::new(AtomicU64::new(0));
        let sink = Arc::clone(&processed);
        let (entered_sender, entered) = std::sync::mpsc::channel();
        let (release, released) = std::sync::mpsc::channel::<()>();
        let released = Mutex::new(released);
        pool.configure(1, move |_| {
            sink.fetch_add(1, Ordering::Relaxed);
            let _ = entered_sender.send(());
            let _ = released.lock().unwrap().recv_timeout(Duration::from_secs(10));
        });

        let running = std::thread::spawn(move || pool.run_now(vec![7]));
        entered.recv_timeout(Duration::from_secs(10)).expect("inline run started");
        pool.enqueue(vec![7]);
        release.send(()).unwrap();
        assert!(running.join().unwrap());

        assert!(pool.wait_idle(Duration::from_secs(10)));
        assert_eq!(processed.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn a_queued_item_is_taken_out_of_the_queue_and_run_once() {
        let pool = leaked_pool();
        let processed = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&processed);
        let (entered_sender, entered) = std::sync::mpsc::channel();
        let (release, released) = std::sync::mpsc::channel::<()>();
        let released = Mutex::new(released);
        pool.configure(1, move |item| {
            if item == vec![1] {
                let _ = entered_sender.send(());
                let _ = released.lock().unwrap().recv_timeout(Duration::from_secs(10));
            }
            sink.lock().unwrap().push(item);
        });
        // The one worker is held on item 1, so item 2 stays queued.
        pool.enqueue(vec![1]);
        entered.recv_timeout(Duration::from_secs(10)).expect("worker busy");
        pool.enqueue(vec![2]);

        assert!(pool.run_now(vec![2]));
        assert_eq!(*processed.lock().unwrap(), vec![vec![2]]);

        release.send(()).unwrap();
        assert!(pool.wait_idle(Duration::from_secs(10)));
        assert_eq!(*processed.lock().unwrap(), vec![vec![2], vec![1]]);
    }

    /// A copy a worker is already processing has an outcome coming. Running it
    /// again would publish the same record twice, and returning early would tell
    /// the caller it was done before it was.
    #[test]
    fn run_now_waits_for_the_copy_a_worker_is_processing() {
        let pool = leaked_pool();
        let processed = Arc::new(AtomicU64::new(0));
        let sink = Arc::clone(&processed);
        let (entered_sender, entered) = std::sync::mpsc::channel();
        let (release, released) = std::sync::mpsc::channel::<()>();
        let released = Mutex::new(released);
        pool.configure(1, move |_| {
            let _ = entered_sender.send(());
            let _ = released.lock().unwrap().recv_timeout(Duration::from_secs(10));
            sink.fetch_add(1, Ordering::Relaxed);
        });
        pool.enqueue(vec![1]);
        entered.recv_timeout(Duration::from_secs(10)).expect("worker busy");

        let waiting = std::thread::spawn(move || pool.run_now(vec![1]));
        std::thread::sleep(Duration::from_millis(100));
        assert!(!waiting.is_finished(), "it waits for the worker");
        release.send(()).unwrap();

        assert!(waiting.join().unwrap());
        assert_eq!(processed.load(Ordering::Relaxed), 1);
    }
}
