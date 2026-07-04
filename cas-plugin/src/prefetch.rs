//! Background ref-graph prefetcher. After an action-cache entry hit, the
//! value object's whole ref graph will be demanded by compiler frontends;
//! walking it eagerly off the critical path turns those demand loads into
//! local hits.

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
    pub fetched: AtomicU64,
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
            fetched: AtomicU64::new(0),
        }
    }

    pub fn worker_count() -> usize {
        std::env::var("TUIST_CAS_PREFETCH")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(24)
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
                // A panicking process() must not skip the inflight decrement,
                // or drain_stop waits forever.
                let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| process(digest)));
                // Decrement under the lock so a drain check can't miss the
                // wakeup between reading inflight and parking on the condvar.
                let _guard = this.queue.lock().unwrap();
                this.inflight.fetch_sub(1, Ordering::AcqRel);
                this.cvar.notify_all();
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

    /// Stops workers and joins them. Pending queue entries are dropped: by
    /// dispose time the build session is over and nothing will demand them.
    pub fn stop(&self) {
        self.shutdown.store(true, Ordering::Release);
        self.cvar.notify_all();
        let workers = std::mem::take(&mut *self.workers.lock().unwrap());
        for worker in workers {
            let _ = worker.join();
        }
    }

    /// Flushes the queue (including work enqueued by in-flight items), then
    /// stops. Used by the uploader, where pending work must not be dropped.
    pub fn drain_stop(&self) {
        self.draining.store(true, Ordering::Release);
        self.cvar.notify_all();
        let workers = std::mem::take(&mut *self.workers.lock().unwrap());
        for worker in workers {
            let _ = worker.join();
        }
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
}
