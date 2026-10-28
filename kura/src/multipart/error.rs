#[derive(Debug, PartialEq, Eq)]
pub enum MultipartError {
    NotFound,
    TotalSizeExceeded,
    CapacityExceeded,
    PartsMismatch,
    MemoryPressure,
    /// The assembled object's bytes do not reproduce the SHA-256 the client
    /// declared at complete time. The upload record and its parts are kept so
    /// the client can re-upload the corrupted part(s) and complete again.
    ChecksumMismatch {
        expected: String,
        actual: String,
    },
    Other(String),
}
