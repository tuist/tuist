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
mod tests;
