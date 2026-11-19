use std::{collections::BTreeMap, sync::Mutex, time::Duration};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum FailpointName {
    BeforeSegmentFsync,
    #[cfg(test)]
    BeforeWalFsync,
    #[cfg(any(test, feature = "test-support"))]
    BeforeUsageOutboxAppend,
    AfterInlineManifestReadBeforeCommit,
    AfterArtifactBytesDurableBeforeMetadata,
    AfterMetadataCommitBeforeReturn,
    AfterReadArtifactBytesBeforeReturn,
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
            #[cfg(any(test, feature = "test-support"))]
            Self::BeforeUsageOutboxAppend => "before_usage_outbox_append",
            Self::AfterInlineManifestReadBeforeCommit => "after_inline_manifest_read_before_commit",
            Self::AfterArtifactBytesDurableBeforeMetadata => {
                "after_artifact_bytes_durable_before_metadata"
            }
            Self::AfterMetadataCommitBeforeReturn => "after_metadata_commit_before_return",
            Self::AfterReadArtifactBytesBeforeReturn => "after_read_artifact_bytes_before_return",
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
pub enum FailpointAction {
    Sleep(Duration),
    #[cfg(any(test, feature = "test-support"))]
    Pause {
        reached: std::sync::Arc<tokio::sync::Notify>,
        resume: std::sync::Arc<tokio::sync::Notify>,
    },
    Error(String),
    Panic(String),
}

#[derive(Clone, Debug)]
struct FailpointBehavior {
    action: FailpointAction,
    remaining_hits: Option<usize>,
}

#[derive(Default)]
pub struct FailpointSet {
    behaviors: Mutex<BTreeMap<FailpointName, FailpointBehavior>>,
}

impl FailpointSet {
    pub async fn hit(&self, name: FailpointName) -> Result<(), String> {
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
            #[cfg(any(test, feature = "test-support"))]
            FailpointAction::Pause { reached, resume } => {
                reached.notify_one();
                resume.notified().await;
                Ok(())
            }
            FailpointAction::Error(message) => {
                Err(format!("failpoint {}: {message}", name.as_str()))
            }
            FailpointAction::Panic(message) => {
                panic!("failpoint {}: {message}", name.as_str());
            }
        }
    }

    /// Blocking-context counterpart of [`Self::hit`] for failpoints on code
    /// that runs on the blocking pool (no async runtime to sleep on).
    pub fn hit_blocking(&self, name: FailpointName) -> Result<(), String> {
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
            #[cfg(any(test, feature = "test-support"))]
            FailpointAction::Pause { .. } => {
                panic!("Pause is only supported by async failpoints");
            }
            FailpointAction::Error(message) => {
                Err(format!("failpoint {}: {message}", name.as_str()))
            }
            FailpointAction::Panic(message) => {
                panic!("failpoint {}: {message}", name.as_str());
            }
        }
    }

    #[cfg(any(test, feature = "test-support"))]
    pub fn set_once(&self, name: FailpointName, action: FailpointAction) {
        self.set(name, action, Some(1));
    }

    #[cfg(any(test, feature = "test-support"))]
    #[allow(dead_code)]
    pub fn set_always(&self, name: FailpointName, action: FailpointAction) {
        self.set(name, action, None);
    }

    #[cfg(any(test, feature = "test-support"))]
    #[allow(dead_code)]
    pub fn clear(&self, name: FailpointName) {
        self.behaviors
            .lock()
            .expect("failpoint lock should not be poisoned")
            .remove(&name);
    }

    #[cfg(any(test, feature = "test-support"))]
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
