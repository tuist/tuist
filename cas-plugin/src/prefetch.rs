//! Background ref-graph prefetcher. After an action-cache entry hit, the
//! value object's whole ref graph will be demanded by compiler frontends;
//! walking it eagerly off the critical path turns those demand loads into
//! local hits.

use std::collections::{HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Condvar, Mutex};

pub struct Prefetcher {
    queue: Mutex<VecDeque<Vec<u8>>>,
    cvar: Condvar,
    shutdown: AtomicBool,
    draining: AtomicBool,
    inflight: AtomicU64,
    seen: Mutex<HashSet<Vec<u8>>>,
    workers: Mutex<Vec<std::thread::JoinHandle<()>>>,
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
            fetched: AtomicU64::new(0),
        }
    }

    pub fn worker_count() -> usize {
        std::env::var("TUIST_CAS_PREFETCH")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(24)
    }

    /// Spawns workers that call `process` with each queued digest. `process`
    /// runs on plain threads; the caller guarantees the backing state outlives
    /// the workers by joining them via `stop` before teardown.
    pub fn start<F>(&self, count: usize, process: F)
    where
        F: Fn(Vec<u8>) + Send + Sync + 'static + Clone,
    {
        let mut workers = self.workers.lock().unwrap();
        for _ in 0..count.max(1) {
            let this: &'static Prefetcher = unsafe { &*(self as *const Prefetcher) };
            let process = process.clone();
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
}
