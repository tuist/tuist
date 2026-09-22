use std::time::Duration;

use crate::WorkspacePathError;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("cas error: {0}")]
    Cas(#[from] once_cas::Error),
    #[error("failed to spawn {program}: {source}")]
    Spawn {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to wait for {program}: {source}")]
    Wait {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("remote provider `{provider}` is not supported yet")]
    UnsupportedRemoteProvider { provider: String },
    #[error("remote provider `{provider}` is not configured: {message}")]
    RemoteProviderConfig { provider: String, message: String },
    #[error("remote provider `{provider}` request failed: {source}")]
    RemoteProviderHttp {
        provider: String,
        #[source]
        source: reqwest::Error,
    },
    #[error("remote provider `{provider}` returned an error: {message}")]
    RemoteProviderApi { provider: String, message: String },
    #[error("action requires a non-empty argv")]
    EmptyArgv,
    #[error("action exceeded its timeout of {0:?}")]
    Timeout(Duration),
    #[error("invalid workspace path: {0}")]
    InvalidPath(#[from] WorkspacePathError),
    #[error("declared output `{path}` was not produced")]
    MissingOutput { path: String },
    #[error("failed to read declared output `{path}`: {source}")]
    ReadOutput {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to restore cached output `{path}`: {source}")]
    RestoreOutput {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("invalid cached directory output `{path}`: {message}")]
    InvalidDirectoryOutput { path: String, message: String },
    #[error("invalid cached file output `{path}`: {message}")]
    InvalidFileOutput { path: String, message: String },
}

pub type Result<T> = std::result::Result<T, Error>;
