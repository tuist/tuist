//! Long-lived threads that run RocksDB metadata commits off the async runtime.
//!
//! Each commit used to start a `spawn_blocking` task, which wakes a pooled
//! thread per write, and the concurrent writers then handed RocksDB's write
//! group leadership back and forth with condition-variable signals. A few
//! dedicated threads draining bounded queues keep the commit off the runtime
//! the same way, but a busy thread picks up its next commit without a wakeup,
//! and RocksDB sees at most one writer per thread.

use std::{
    panic::AssertUnwindSafe,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};

use tokio::sync::{mpsc, oneshot};

type Job = Box<dyn FnOnce() + Send>;

struct Lane {
    sender: mpsc::Sender<Job>,
    // Queued plus running jobs, so a lane blocked inside a long commit (or a
    // RocksDB write stall) stops receiving new work while another lane is free.
    in_flight: Arc<AtomicUsize>,
}

pub(crate) struct CommitThreads {
    lanes: Vec<Lane>,
}

struct InFlight(Arc<AtomicUsize>);

impl Drop for InFlight {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

impl CommitThreads {
    /// Starts `threads` commit threads, each accepting up to `queue_depth`
    /// waiting commits before callers wait for room. The threads exit once
    /// this value is dropped and their queues drain.
    pub(crate) fn new(threads: usize, queue_depth: usize) -> std::io::Result<Self> {
        let lanes = (0..threads)
            .map(|index| {
                let (sender, mut receiver) = mpsc::channel::<Job>(queue_depth);
                std::thread::Builder::new()
                    .name(format!("kura-commit-{index}"))
                    .spawn(move || {
                        while let Some(job) = receiver.blocking_recv() {
                            // A panicking commit fails only its own caller,
                            // whose reply is dropped; the thread keeps serving.
                            let _ = std::panic::catch_unwind(AssertUnwindSafe(job));
                        }
                    })?;
                Ok(Lane {
                    sender,
                    in_flight: Arc::new(AtomicUsize::new(0)),
                })
            })
            .collect::<std::io::Result<_>>()?;
        Ok(Self { lanes })
    }

    /// Runs `operation` on the least busy commit thread. Once queued, the
    /// operation runs to completion even if the caller is dropped, like a
    /// `spawn_blocking` task; a caller dropped while waiting for queue room
    /// never runs it.
    pub(crate) async fn run<T: Send + 'static>(
        &self,
        operation: impl FnOnce() -> T + Send + 'static,
    ) -> Result<T, String> {
        let lane = self
            .lanes
            .iter()
            .min_by_key(|lane| lane.in_flight.load(Ordering::Relaxed))
            .expect("at least one metadata commit thread");
        lane.in_flight.fetch_add(1, Ordering::Relaxed);
        let in_flight = InFlight(Arc::clone(&lane.in_flight));
        let (reply, result) = oneshot::channel();
        let job: Job = Box::new(move || {
            let _in_flight = in_flight;
            let _ = reply.send(operation());
        });
        lane.sender
            .send(job)
            .await
            .map_err(|_| "metadata commit thread stopped".to_owned())?;
        result
            .await
            .map_err(|_| "metadata commit panicked".to_owned())
    }
}

#[cfg(test)]
mod tests {
    use std::{sync::mpsc as std_mpsc, time::Duration};

    use super::*;

    #[tokio::test]
    async fn a_blocked_thread_does_not_hold_up_commits_on_another_thread() {
        let threads = CommitThreads::new(2, 4).unwrap();
        let (release, blocked) = std_mpsc::channel::<()>();
        let (started_tx, started) = oneshot::channel();
        let stuck = threads.run(move || {
            let _ = started_tx.send(());
            blocked.recv_timeout(Duration::from_secs(5)).unwrap();
        });
        tokio::pin!(stuck);
        tokio::select! {
            _ = &mut stuck => panic!("the blocked commit should not finish"),
            started = started => started.unwrap(),
        }
        let other = tokio::time::timeout(Duration::from_secs(5), threads.run(|| 7))
            .await
            .expect("the free thread should take the commit");
        assert_eq!(other, Ok(7));
        release.send(()).unwrap();
        stuck.await.unwrap();
    }

    #[tokio::test]
    async fn a_queued_commit_runs_after_its_caller_is_dropped() {
        let threads = CommitThreads::new(1, 4).unwrap();
        let (release, blocked) = std_mpsc::channel::<()>();
        let (ran_tx, ran) = std_mpsc::channel();
        let mut first = Box::pin(threads.run(move || {
            blocked.recv_timeout(Duration::from_secs(5)).unwrap();
        }));
        let mut second = Box::pin(threads.run(move || ran_tx.send(()).unwrap()));
        // Queue the second commit behind the blocked first one, then drop its
        // caller before it runs.
        assert!(futures_util::poll!(&mut first).is_pending());
        assert!(futures_util::poll!(&mut second).is_pending());
        drop(second);
        release.send(()).unwrap();
        first.await.unwrap();
        ran.recv_timeout(Duration::from_secs(5))
            .expect("the queued commit should still run");
    }

    #[tokio::test]
    async fn a_panicking_commit_fails_its_caller_and_the_thread_keeps_serving() {
        let threads = CommitThreads::new(1, 4).unwrap();
        assert!(threads.run(|| panic!("boom")).await.is_err());
        assert_eq!(threads.run(|| 1).await, Ok(1));
    }
}
