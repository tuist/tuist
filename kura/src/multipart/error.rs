#[derive(Debug, PartialEq, Eq)]
pub enum MultipartError {
    NotFound,
    TotalSizeExceeded,
    PartsMismatch,
    MemoryPressure,
    Other(String),
}
