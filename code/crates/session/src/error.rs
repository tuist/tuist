use tuist_credentials::{LockError, StoreError};

#[derive(Debug)]
pub enum Error {
    SignedOut,
    /// A different account now owns the shared canonical credentials.
    IdentityChanged,
    /// The server refused the stored refresh token; sign in again.
    Rejected,
    /// The stored tokens are not JWTs the clients understand.
    InvalidCredentials,
    InvalidServerUrl(String),
    Store(StoreError),
    Lock(LockError),
    Server(tuist_oauth::Error),
}

impl Error {
    pub fn is_cancelled(&self) -> bool {
        matches!(self, Self::Server(tuist_oauth::Error::Cancelled))
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::SignedOut => f.write_str("you're not signed in"),
            Self::IdentityChanged => {
                f.write_str("the active account changed; select the account again")
            }
            Self::Rejected => f.write_str("your session expired; sign in again"),
            Self::InvalidCredentials => {
                f.write_str("the saved credentials are invalid; sign in again")
            }
            Self::InvalidServerUrl(url) => write!(f, "{url} is not a valid server URL"),
            Self::Store(error) => write!(f, "{error}"),
            Self::Lock(error) => write!(f, "{error}"),
            Self::Server(error) => write!(f, "{error}"),
        }
    }
}

impl std::error::Error for Error {}

impl From<StoreError> for Error {
    fn from(error: StoreError) -> Self {
        Self::Store(error)
    }
}

impl From<LockError> for Error {
    fn from(error: LockError) -> Self {
        Self::Lock(error)
    }
}

impl From<tuist_oauth::Error> for Error {
    fn from(error: tuist_oauth::Error) -> Self {
        Self::Server(error)
    }
}
