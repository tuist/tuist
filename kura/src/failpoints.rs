use std::{collections::BTreeMap, sync::Mutex, time::Duration};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum FailpointName {
    BeforeSegmentFsync,
    #[cfg(test)]
    BeforeWalFsync,
    BeforeInlineApplyWriteLock,
    AfterArtifactBytesDurableBeforeMetadata,
    AfterMetadataCommitBeforeReturn,
    AfterReadArtifactBytesBeforeReturn,
    BeforeDeleteOutboxMessageAfterSuccess,
    BeforeApplyReplicatedTombstone,
    AfterApplyReplicatedTombstone,
    AfterBackfillIndexBuildChunk,
    AfterBackfillBodiesSpoolBeforeApply,
    BetweenBackfillGroupCommits,
    AfterBackfillBatchCommitBeforeWalFlush,
}

impl FailpointName {
    fn as_str(self) -> &'static str {
        match self {
            Self::BeforeSegmentFsync => "before_segment_fsync",
            #[cfg(test)]
            Self::BeforeWalFsync => "before_wal_fsync",
            Self::BeforeInlineApplyWriteLock => "before_inline_apply_write_lock",
            Self::AfterArtifactBytesDurableBeforeMetadata => {
                "after_artifact_bytes_durable_before_metadata"
            }
            Self::AfterMetadataCommitBeforeReturn => "after_metadata_commit_before_return",
            Self::AfterReadArtifactBytesBeforeReturn => "after_read_artifact_bytes_before_return",
            Self::BeforeDeleteOutboxMessageAfterSuccess => {
                "before_delete_outbox_message_after_success"
            }
            Self::BeforeApplyReplicatedTombstone => "before_apply_replicated_tombstone",
            Self::AfterApplyReplicatedTombstone => "after_apply_replicated_tombstone",
            Self::AfterBackfillIndexBuildChunk => "after_backfill_index_build_chunk",
            Self::AfterBackfillBodiesSpoolBeforeApply => "after_backfill_bodies_spool_before_apply",
            Self::BetweenBackfillGroupCommits => "between_backfill_group_commits",
            Self::AfterBackfillBatchCommitBeforeWalFlush => {
                "after_backfill_batch_commit_before_wal_flush"
            }
        }
    }
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub(crate) enum FailpointAction {
    Sleep(Duration),
    Error(String),
    Panic(String),
    /// Park until the test releases the gate. Unlike [`Self::Sleep`], this
    /// makes an interleaving a fact rather than a wager on wall-clock timing:
    /// the test learns when the parked task actually reached the failpoint and
    /// decides itself when it may continue.
    #[cfg(test)]
    Pause(std::sync::Arc<FailpointGate>),
}

/// The two-way rendezvous behind [`FailpointAction::Pause`].
#[cfg(test)]
#[derive(Debug, Default)]
pub(crate) struct FailpointGate {
    entered: tokio::sync::Notify,
    released: tokio::sync::Notify,
}

#[cfg(test)]
impl FailpointGate {
    pub(crate) fn new() -> std::sync::Arc<Self> {
        std::sync::Arc::new(Self::default())
    }

    /// Resolves once a task has reached the failpoint and parked on it.
    pub(crate) async fn entered(&self) {
        self.entered.notified().await;
    }

    /// Lets the parked task run on.
    pub(crate) fn release(&self) {
        self.released.notify_one();
    }

    async fn park(&self) {
        // Both directions store a permit when nobody is waiting yet, so
        // neither half of the rendezvous can be missed by arriving early.
        self.entered.notify_one();
        self.released.notified().await;
    }
}

#[derive(Clone, Debug)]
struct FailpointBehavior {
    action: FailpointAction,
    remaining_hits: Option<usize>,
}

#[derive(Default)]
pub(crate) struct FailpointSet {
    behaviors: Mutex<BTreeMap<FailpointName, FailpointBehavior>>,
}

impl FailpointSet {
    pub(crate) async fn hit(&self, name: FailpointName) -> Result<(), String> {
        let action = {
            let mut behaviors = self
                .behaviors
                .lock()
                .expect("failpoint lock should not be poisoned");
            let Some(behavior) = behaviors.get_mut(&name) else {
                return Ok(());
            };
            let action = behavior.action.clone();
            match behavior.remaining_hits {
                Some(remaining_hits) if remaining_hits <= 1 => {
                    behaviors.remove(&name);
                }
                Some(remaining_hits) => {
                    behavior.remaining_hits = Some(remaining_hits - 1);
                }
                None => {}
            }
            action
        };

        match action {
            FailpointAction::Sleep(duration) => {
                tokio::time::sleep(duration).await;
                Ok(())
            }
            FailpointAction::Error(message) => {
                Err(format!("failpoint {}: {message}", name.as_str()))
            }
            FailpointAction::Panic(message) => {
                panic!("failpoint {}: {message}", name.as_str());
            }
            #[cfg(test)]
            FailpointAction::Pause(gate) => {
                gate.park().await;
                Ok(())
            }
        }
    }

    /// Blocking-context counterpart of [`Self::hit`] for failpoints on code
    /// that runs on the blocking pool (no async runtime to sleep on).
    pub(crate) fn hit_blocking(&self, name: FailpointName) -> Result<(), String> {
        let action = {
            let mut behaviors = self
                .behaviors
                .lock()
                .expect("failpoint lock should not be poisoned");
            let Some(behavior) = behaviors.get_mut(&name) else {
                return Ok(());
            };
            let action = behavior.action.clone();
            match behavior.remaining_hits {
                Some(remaining_hits) if remaining_hits <= 1 => {
                    behaviors.remove(&name);
                }
                Some(remaining_hits) => {
                    behavior.remaining_hits = Some(remaining_hits - 1);
                }
                None => {}
            }
            action
        };

        match action {
            FailpointAction::Sleep(duration) => {
                std::thread::sleep(duration);
                Ok(())
            }
            FailpointAction::Error(message) => {
                Err(format!("failpoint {}: {message}", name.as_str()))
            }
            FailpointAction::Panic(message) => {
                panic!("failpoint {}: {message}", name.as_str());
            }
            #[cfg(test)]
            FailpointAction::Pause(_) => {
                panic!(
                    "failpoint {}: Pause needs an async context, use FailpointSet::hit",
                    name.as_str()
                );
            }
        }
    }

    #[cfg(test)]
    pub(crate) fn set_once(&self, name: FailpointName, action: FailpointAction) {
        self.set(name, action, Some(1));
    }

    #[cfg(test)]
    #[allow(dead_code)]
    pub(crate) fn set_always(&self, name: FailpointName, action: FailpointAction) {
        self.set(name, action, None);
    }

    #[cfg(test)]
    #[allow(dead_code)]
    pub(crate) fn clear(&self, name: FailpointName) {
        self.behaviors
            .lock()
            .expect("failpoint lock should not be poisoned")
            .remove(&name);
    }

    #[cfg(test)]
    fn set(&self, name: FailpointName, action: FailpointAction, remaining_hits: Option<usize>) {
        self.behaviors
            .lock()
            .expect("failpoint lock should not be poisoned")
            .insert(
                name,
                FailpointBehavior {
                    action,
                    remaining_hits,
                },
            );
    }
}
