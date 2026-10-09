//! Frontend error type. Distinguishes I/O, walk, parse, and evaluation
//! failures so callers can react differently (e.g. surface a parse
//! error with a file path while suppressing a transient walk error).

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("failed to read {path}: {source}")]
    Read {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to walk {root}: {source}")]
    Walk {
        root: String,
        #[source]
        source: walkdir::Error,
    },
    #[error("parse error in {path}:\n{message}")]
    Parse { path: String, message: String },
    #[error("evaluation error in {path}:\n{message}")]
    Eval { path: String, message: String },
}

pub type Result<T> = std::result::Result<T, Error>;
