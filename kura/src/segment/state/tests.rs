
use super::SegmentState;
use crate::segment::reference::SegmentReference;

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
