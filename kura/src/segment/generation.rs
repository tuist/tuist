#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SegmentGeneration {
    Old,
    Current,
    New,
}
