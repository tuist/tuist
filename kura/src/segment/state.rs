use serde::{Deserialize, Serialize};

use crate::segment::reference::SegmentReference;

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct SegmentState {
    pub old: Vec<SegmentReference>,
    pub current: Vec<SegmentReference>,
    pub new: Vec<SegmentReference>,
}

impl SegmentState {
    pub fn active(&self) -> Option<&SegmentReference> {
        self.new.last()
    }

    pub fn push_new(
        &mut self,
        segment: SegmentReference,
        desired_old_segments: usize,
        desired_current_segments: usize,
        desired_new_segments: usize,
    ) -> Vec<SegmentReference> {
        let mut evicted = Vec::new();
        self.new.push(segment);

        while self.new.len() > desired_new_segments {
            self.current.push(self.new.remove(0));
        }

        while self.current.len() > desired_current_segments {
            self.old.push(self.current.remove(0));
        }

        while self.old.len() > desired_old_segments {
            evicted.push(self.old.remove(0));
        }

        evicted
    }

    /// Raises `segment_id`'s `max_version_ms` stat, never lowering it: a
    /// promotion re-appends an old entry into the active segment, and its
    /// stale version must not drag the stat back down.
    pub fn raise_max_version_ms(&mut self, segment_id: &str, version_ms: u64) {
        if let Some(reference) = self
            .old
            .iter_mut()
            .chain(self.current.iter_mut())
            .chain(self.new.iter_mut())
            .find(|reference| reference.segment_id == segment_id)
            && reference.max_version_ms.is_none_or(|max| max < version_ms)
        {
            reference.max_version_ms = Some(version_ms);
        }
    }

    /// All retained references ordered by data age (the effective max stat),
    /// not ring position. The two orders diverge on rings filled by backfill
    /// — newest-first fetching writes old data into young segments — which is
    /// exactly when the age-based window rules need this view. Ties keep the
    /// eviction cascade order (old, current, new).
    #[allow(dead_code)] // consumed by the backfill pass driver (Unit 7)
    pub fn age_ordered_references(&self) -> Vec<&SegmentReference> {
        let mut references: Vec<&SegmentReference> = self
            .old
            .iter()
            .chain(self.current.iter())
            .chain(self.new.iter())
            .collect();
        references.sort_by_key(|reference| reference.effective_max_version_ms());
        references
    }

    /// The segment the next rotation would evict: `push_new` cascades
    /// new → current → old and pops evictions from the front of `old`, so the
    /// next evictee is the front of the first non-empty band in that cascade
    /// order.
    #[allow(dead_code)] // consumed by the backfill pass driver (Unit 7)
    pub fn next_evictee(&self) -> Option<&SegmentReference> {
        self.old
            .first()
            .or_else(|| self.current.first())
            .or_else(|| self.new.first())
    }

    pub fn remove_segment(&mut self, segment_id: &str) -> bool {
        remove_from_segments(&mut self.old, segment_id)
            || remove_from_segments(&mut self.current, segment_id)
            || remove_from_segments(&mut self.new, segment_id)
    }
}

fn remove_from_segments(segments: &mut Vec<SegmentReference>, segment_id: &str) -> bool {
    if let Some(index) = segments
        .iter()
        .position(|segment| segment.segment_id == segment_id)
    {
        segments.remove(index);
        true
    } else {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::SegmentState;
    use crate::segment::reference::SegmentReference;

    #[test]
    fn raise_max_version_ms_is_max_only() {
        let mut state = SegmentState::default();
        state.push_new(SegmentReference::new("segment-1".into(), 1), 1, 2, 2);

        state.raise_max_version_ms("segment-1", 300);
        assert_eq!(state.new[0].max_version_ms, Some(300));

        state.raise_max_version_ms("segment-1", 100);
        assert_eq!(state.new[0].max_version_ms, Some(300));

        // Unknown segments (already evicted) are a no-op.
        state.raise_max_version_ms("segment-2", 500);
        assert_eq!(state.new.len(), 1);
    }

    #[test]
    fn age_ordered_references_order_by_effective_stat_not_ring_position() {
        let mut state = SegmentState::default();
        // Ring position: s1 (old band) … s5 (active). Stats are scrambled the
        // way a backfill-populated ring scrambles them; s5 (active) has no
        // stat and falls back to created_at_ms.
        for (id, created_at_ms, max_version_ms) in [
            ("s1", 1, Some(500)),
            ("s2", 2, Some(100)),
            ("s3", 3, Some(400)),
            ("s4", 4, Some(200)),
            ("s5", 300, None),
        ] {
            let mut reference = SegmentReference::new(id.into(), created_at_ms);
            reference.max_version_ms = max_version_ms;
            state.push_new(reference, 1, 2, 2);
        }

        let ordered: Vec<&str> = state
            .age_ordered_references()
            .iter()
            .map(|reference| reference.segment_id.as_str())
            .collect();
        assert_eq!(ordered, vec!["s2", "s4", "s5", "s3", "s1"]);
    }

    #[test]
    fn next_evictee_is_the_front_of_the_cascade() {
        let mut state = SegmentState::default();
        assert!(state.next_evictee().is_none());

        state.push_new(SegmentReference::new("s1".into(), 1), 1, 2, 2);
        assert_eq!(state.next_evictee().unwrap().segment_id, "s1");

        for (id, created_at_ms) in [("s2", 2), ("s3", 3), ("s4", 4), ("s5", 5)] {
            state.push_new(SegmentReference::new(id.into(), created_at_ms), 1, 2, 2);
        }
        assert_eq!(state.old[0].segment_id, "s1");
        assert_eq!(state.next_evictee().unwrap().segment_id, "s1");
    }

    #[test]
    fn push_new_rebalances_generations() {
        let mut state = SegmentState::default();

        let evicted = state.push_new(SegmentReference::new("new-1".into(), 1), 1, 2, 2);
        assert!(evicted.is_empty());

        let evicted = state.push_new(SegmentReference::new("new-2".into(), 2), 1, 2, 2);
        assert!(evicted.is_empty());

        let evicted = state.push_new(SegmentReference::new("new-3".into(), 3), 1, 2, 2);
        assert!(evicted.is_empty());
        assert_eq!(state.current[0].segment_id, "new-1");

        let evicted = state.push_new(SegmentReference::new("new-4".into(), 4), 1, 2, 2);
        assert!(evicted.is_empty());
        assert_eq!(state.current[1].segment_id, "new-2");

        let evicted = state.push_new(SegmentReference::new("new-5".into(), 5), 1, 2, 2);
        assert!(evicted.is_empty());
        assert_eq!(state.old[0].segment_id, "new-1");

        let evicted = state.push_new(SegmentReference::new("new-6".into(), 6), 1, 2, 2);
        assert_eq!(evicted.len(), 1);
        assert_eq!(evicted[0].segment_id, "new-1");
    }
}
