#[derive(Debug, PartialEq, Eq)]
pub enum MultipartError {
    NotFound,
    TotalSizeExceeded,
    CapacityExceeded,
    PartsMismatch,
    MemoryPressure,
    Other(String),
}
