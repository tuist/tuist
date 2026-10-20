use std::collections::BTreeMap;
use std::str::FromStr;

use once_cas::Digest;
use serde::{Deserialize, Serialize};

use crate::{ResourceRequest, WorkspacePath};

/// Domain-separation prefix for action digests. Bump the version when
/// the canonical encoding (or the [`Action`] schema) changes in a way
/// that should invalidate the cache. Older action result JSON still
/// deserializes through serde defaults; the domain only partitions new
/// action lookups.
pub(crate) const ACTION_DIGEST_DOMAIN: &[u8] = b"once.action.v4\0";

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum OutputSymlinkMode {
    Preserve,
    #[default]
    MaterializeExternal,
}

impl OutputSymlinkMode {
    pub fn is_default(&self) -> bool {
        *self == Self::default()
    }
}

impl FromStr for OutputSymlinkMode {
    type Err = String;

    fn from_str(raw: &str) -> Result<Self, Self::Err> {
        match raw {
            "preserve" => Ok(Self::Preserve),
            "materialize-external" => Ok(Self::MaterializeExternal),
            _ => Err(format!(
                "expected `preserve` or `materialize-external`, got `{raw}`"
            )),
        }
    }
}

/// All actions Once can execute.
///
/// The wire format of this enum is part of the action digest (see
/// `ACTION_DIGEST_DOMAIN`). Field additions, renames, or reorderings
/// that affect the JSON encoding require a digest version bump.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Action {
    RunCommand {
        argv: Vec<String>,
        #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
        env: BTreeMap<String, String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        cwd: Option<WorkspacePath>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        input_digest: Option<Digest>,
        /// Workspace-relative paths the action promises to produce. The
        /// runner stores each one in the CAS after a fresh execution
        /// and restores it from the CAS on a cache hit. An empty list
        /// means the action has no declared outputs (only stdout/stderr
        /// are cached); cache hits then provide nothing on disk.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        outputs: Vec<WorkspacePath>,
        #[serde(default, skip_serializing_if = "OutputSymlinkMode::is_default")]
        output_symlink_mode: OutputSymlinkMode,
        #[serde(default, skip_serializing_if = "ResourceRequest::is_default")]
        resources: ResourceRequest,
        /// Per-action timeout in milliseconds. None = no timeout.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        timeout_ms: Option<u64>,
        /// Optional compute provider for remote execution. This is
        /// part of the action key so local and remote runs never share
        /// a cache slot by accident.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        remote: Option<RemoteExecution>,
    },
}

impl Action {
    /// Canonical, content-addressed key for this action.
    ///
    /// The key is `BLAKE3(domain || canonical_json(self))`. Bumping the
    /// domain partitions old and new cache entries cleanly instead of
    /// silently colliding.
    pub fn digest(&self) -> Digest {
        let body = serde_json::to_vec(self).expect("Action is serializable");
        let mut buf = Vec::with_capacity(ACTION_DIGEST_DOMAIN.len() + body.len());
        buf.extend_from_slice(ACTION_DIGEST_DOMAIN);
        buf.extend_from_slice(&body);
        Digest::of_bytes(&buf)
    }

    pub fn resource_request(&self) -> &ResourceRequest {
        match self {
            Action::RunCommand { resources, .. } => resources,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub struct RemoteExecution {
    pub provider: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn action(output_symlink_mode: OutputSymlinkMode) -> Action {
        Action::RunCommand {
            argv: vec!["true".to_string()],
            env: BTreeMap::new(),
            cwd: None,
            input_digest: None,
            outputs: vec![WorkspacePath::try_from("out").unwrap()],
            output_symlink_mode,
            resources: ResourceRequest::default(),
            timeout_ms: None,
            remote: None,
        }
    }

    #[test]
    fn output_symlink_mode_changes_action_digest() {
        assert_ne!(
            action(OutputSymlinkMode::MaterializeExternal).digest(),
            action(OutputSymlinkMode::Preserve).digest()
        );
    }
}
