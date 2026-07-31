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
