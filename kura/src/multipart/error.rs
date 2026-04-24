#[derive(Debug, PartialEq, Eq)]
pub enum MultipartError {
    NotFound,
    TotalSizeExceeded,
    PartsMismatch,
    Other(String),
}
