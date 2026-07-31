use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SegmentReference {
    pub segment_id: String,
    pub created_at_ms: u64,
    /// Max effective `version_ms` of the artifacts committed into this
    /// segment, stamped when it seals (rotates out of active). `None` on the
    /// still-open active segment and on references persisted by releases that
    /// predate the stat; callers fall back to `created_at_ms`. Optional with a
    /// serde default so the persisted ring JSON stays readable across one
    /// version skew in both directions.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_version_ms: Option<u64>,
}

impl SegmentReference {
    pub fn new(segment_id: String, created_at_ms: u64) -> Self {
        Self {
            segment_id,
            created_at_ms,
            max_version_ms: None,
        }
    }

    /// The seal-time stat with the pre-upgrade fallback applied: a reference
    /// without it reports the segment's creation time, the accepted
    /// conservative proxy for the age of its contents. Test-gated until the
    /// age-based ring rules consume it.
    #[cfg(test)]
    pub fn effective_max_version_ms(&self) -> u64 {
        self.max_version_ms.unwrap_or(self.created_at_ms)
    }
}

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    use super::SegmentReference;

    /// The reference shape persisted by releases that predate
    /// `max_version_ms`. Deserializing through it simulates an old binary
    /// reading ring state written by new code (rollback skew).
    #[derive(Debug, Deserialize, PartialEq, Eq)]
    struct PreStatSegmentReference {
        segment_id: String,
        created_at_ms: u64,
    }

    #[test]
    fn pre_stat_json_deserializes_with_absent_stat() {
        let reference: SegmentReference =
            serde_json::from_str(r#"{"segment_id":"segment-1","created_at_ms":7}"#)
                .expect("pre-stat reference should deserialize");

        assert_eq!(reference, SegmentReference::new("segment-1".into(), 7));
        assert_eq!(reference.max_version_ms, None);
        assert_eq!(reference.effective_max_version_ms(), 7);
    }

    #[test]
    fn stat_round_trips_through_json() {
        let mut reference = SegmentReference::new("segment-1".into(), 7);
        reference.max_version_ms = Some(11);

        let json = serde_json::to_string(&reference).expect("reference should serialize");
        let decoded: SegmentReference =
            serde_json::from_str(&json).expect("reference should deserialize");

        assert_eq!(decoded, reference);
        assert_eq!(decoded.effective_max_version_ms(), 11);
    }

    #[test]
    fn new_shape_json_deserializes_under_the_old_struct_shape() {
        let mut reference = SegmentReference::new("segment-1".into(), 7);
        reference.max_version_ms = Some(11);
        let json = serde_json::to_string(&reference).expect("reference should serialize");

        let legacy: PreStatSegmentReference =
            serde_json::from_str(&json).expect("old struct shape should tolerate the new field");

        assert_eq!(
            legacy,
            PreStatSegmentReference {
                segment_id: "segment-1".into(),
                created_at_ms: 7,
            }
        );
    }

    #[test]
    fn unsealed_reference_serializes_without_the_field() {
        let json = serde_json::to_string(&SegmentReference::new("segment-1".into(), 7))
            .expect("reference should serialize");

        assert_eq!(json, r#"{"segment_id":"segment-1","created_at_ms":7}"#);
    }
}
