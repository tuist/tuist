//! The usage rollup record the store persists in its outbox; the kura crate's `usage` module
//! aggregates and delivers them.
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct UsageRollup {
    pub event_id: String,
    pub tenant_id: String,
    pub namespace_id: String,
    pub window_start_unix_seconds: u64,
    pub window_seconds: u64,
    pub node_id: String,
    pub region: String,
    pub traffic_plane: String,
    pub direction: String,
    pub operation: String,
    pub protocol: String,
    pub artifact_kind: String,
    pub bytes: u64,
    pub request_count: u64,
    /// Where the credential behind these requests was issued, when it carried a
    /// signed origin. Absent on the wire otherwise, so older control planes and
    /// rollups stored before it existed read the same.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<String>,
}
