use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SegmentReference {
    pub segment_id: String,
    pub created_at_ms: u64,
}

impl SegmentReference {
    pub fn new(segment_id: String, created_at_ms: u64) -> Self {
        Self {
            segment_id,
            created_at_ms,
        }
    }
}
