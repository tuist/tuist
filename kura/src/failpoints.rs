use std::{collections::BTreeMap, sync::Mutex, time::Duration};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum FailpointName {
    AfterArtifactBytesDurableBeforeMetadata,
    AfterMetadataCommitBeforeReturn,
    AfterBootstrapManifestPageFetchBeforeApply,
    AfterBootstrapArtifactFetchBeforePersist,
    BeforeDeleteOutboxMessageAfterSuccess,
    BeforeApplyReplicatedTombstone,
    AfterApplyReplicatedTombstone,
}

impl FailpointName {
    fn as_str(self) -> &'static str {
        match self {
            Self::AfterArtifactBytesDurableBeforeMetadata => {
                "after_artifact_bytes_durable_before_metadata"
            }
            Self::AfterMetadataCommitBeforeReturn => "after_metadata_commit_before_return",
            Self::AfterBootstrapManifestPageFetchBeforeApply => {
                "after_bootstrap_manifest_page_fetch_before_apply"
            }
            Self::AfterBootstrapArtifactFetchBeforePersist => {
                "after_bootstrap_artifact_fetch_before_persist"
            }
            Self::BeforeDeleteOutboxMessageAfterSuccess => {
                "before_delete_outbox_message_after_success"
            }
            Self::BeforeApplyReplicatedTombstone => "before_apply_replicated_tombstone",
            Self::AfterApplyReplicatedTombstone => "after_apply_replicated_tombstone",
        }
    }
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
pub(crate) enum FailpointAction {
    Sleep(Duration),
    Error(String),
    Panic(String),
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
