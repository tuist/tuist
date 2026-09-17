//! Keep-alive for action results a client answered from its own local store,
//! which this node never read. Rides `GetActionResult` on a reserved action key,
//! like the snapshot, with one `inline_output_files` hint per action.

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use sha2::{Digest as _, Sha256};
use tonic::Status;

pub const KEEP_ALIVE_ACTION_KEY: &[u8] = b"tuist-actioncache-keep-alive/v1";
/// Names one action as `<sha256 hex>/<size>`.
pub const KEEP_ALIVE_HINT: &str = "tuist-keep-alive:";
pub const KEEP_ALIVE_MAX_ACTIONS: usize = 4_096;

pub(super) fn is_keep_alive(digest: &reapi::Digest) -> bool {
    static HASH: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    digest.size_bytes == KEEP_ALIVE_ACTION_KEY.len() as i64
        && digest.hash == *HASH.get_or_init(|| hex::encode(Sha256::digest(KEEP_ALIVE_ACTION_KEY)))
}

pub(super) fn keep_alive_actions(hints: &[String]) -> Result<Vec<reapi::Digest>, Status> {
    let actions = hints
        .iter()
        .filter_map(|hint| hint.strip_prefix(KEEP_ALIVE_HINT))
        .map(|action| {
            action
                .split_once('/')
                .and_then(|(hash, size)| {
                    Some(reapi::Digest {
                        hash: hash.to_owned(),
                        size_bytes: size.parse().ok()?,
                    })
                })
                .ok_or_else(|| {
                    Status::invalid_argument(format!("malformed keep-alive action {action:?}"))
                })
        })
        .collect::<Result<Vec<_>, _>>()?;
    if actions.len() > KEEP_ALIVE_MAX_ACTIONS {
        return Err(Status::invalid_argument(format!(
            "a keep-alive names at most {KEEP_ALIVE_MAX_ACTIONS} actions, got {}",
            actions.len()
        )));
    }
    Ok(actions)
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct KeepAliveSummary {
    pub found: u64,
    pub missing: u64,
    /// Entries that already lost a blob.
    pub evicted: u64,
}

impl KeepAliveSummary {
    pub(super) fn encode(&self) -> Vec<u8> {
        format!(
            "found={} missing={} evicted={}",
            self.found, self.missing, self.evicted
        )
        .into_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_reserved_key_is_a_keep_alive() {
        let reserved = reapi::Digest {
            hash: hex::encode(Sha256::digest(KEEP_ALIVE_ACTION_KEY)),
            size_bytes: KEEP_ALIVE_ACTION_KEY.len() as i64,
        };
        assert!(is_keep_alive(&reserved));
        assert!(!is_keep_alive(&reapi::Digest {
            size_bytes: 1,
            ..reserved.clone()
        }));
        assert!(!is_keep_alive(&reapi::Digest {
            hash: hex::encode(Sha256::digest(b"an ordinary action")),
            ..reserved
        }));
    }

    #[test]
    fn actions_are_read_from_their_hints_and_other_hints_are_ignored() {
        let hash = "ab".repeat(32);
        let actions = keep_alive_actions(&["*".to_owned(), format!("{KEEP_ALIVE_HINT}{hash}/65")])
            .expect("well-formed hints");
        assert_eq!(
            actions,
            vec![reapi::Digest {
                hash,
                size_bytes: 65,
            }]
        );
    }
}
