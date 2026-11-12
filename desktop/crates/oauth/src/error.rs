#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// The request did not complete; retrying the same request may succeed.
    Transport(String),
    /// The server answered with a status worth retrying (408, 429, 5xx).
    Unavailable(u16),
    /// The server refused the grant: the person must sign in again.
    Rejected(String),
    /// Any other unexpected status.
    Status(u16),
    InvalidResponse,
    /// The server does not support signing in from native apps.
    UnsupportedServer,
    /// The browser returned an error instead of a code, such as a denied consent.
    Denied(String),
    /// The callback's state did not match this sign-in.
    StateMismatch,
    Cancelled,
    TimedOut,
    Io(String),
}

impl Error {
    /// Transient failures keep the stored credentials and never mark them rejected.
    pub fn is_transient(&self) -> bool {
        matches!(self, Self::Transport(_) | Self::Unavailable(_))
    }
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Transport(message) => write!(f, "couldn't reach the Tuist server: {message}"),
            Self::Unavailable(status) => write!(f, "the Tuist server is unavailable (HTTP {status})"),
            Self::Rejected(message) => write!(f, "{message}"),
            Self::Status(status) => write!(f, "the Tuist server answered HTTP {status}"),
            Self::InvalidResponse => f.write_str("the Tuist server sent an unexpected response"),
            Self::UnsupportedServer => {
                f.write_str("this server doesn't support signing in from the Tuist app; ask your administrator to update it")
            }
            Self::Denied(message) => write!(f, "sign-in was not completed: {message}"),
            Self::StateMismatch => f.write_str("the sign-in response didn't match this request"),
            Self::Cancelled => f.write_str("sign-in was cancelled"),
            Self::TimedOut => f.write_str("sign-in timed out"),
            Self::Io(message) => write!(f, "{message}"),
        }
    }
}

impl std::error::Error for Error {}
