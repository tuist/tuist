use serde::{Deserialize, Serialize};

use crate::segment::{generation::SegmentGeneration, reference::SegmentReference};

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

    pub fn generation_of(&self, segment_id: &str) -> Option<SegmentGeneration> {
        if self
            .old
            .iter()
            .any(|segment| segment.segment_id == segment_id)
        {
            return Some(SegmentGeneration::Old);
        }
        if self
            .current
            .iter()
            .any(|segment| segment.segment_id == segment_id)
        {
            return Some(SegmentGeneration::Current);
        }
        if self
            .new
            .iter()
            .any(|segment| segment.segment_id == segment_id)
        {
            return Some(SegmentGeneration::New);
        }
        None
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
    use crate::segment::{generation::SegmentGeneration, reference::SegmentReference};

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

    #[test]
    fn generation_of_tracks_segment_location() {
        let state = SegmentState {
            old: vec![SegmentReference::new("old".into(), 1)],
            current: vec![SegmentReference::new("current".into(), 2)],
            new: vec![SegmentReference::new("new".into(), 3)],
        };

        assert_eq!(state.generation_of("old"), Some(SegmentGeneration::Old));
        assert_eq!(
            state.generation_of("current"),
            Some(SegmentGeneration::Current)
        );
        assert_eq!(state.generation_of("new"), Some(SegmentGeneration::New));
        assert_eq!(state.generation_of("missing"), None);
    }
}
