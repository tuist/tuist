//! A person's Tuist session on one server: who is signed in, a usable access
//! token, browser sign-in, and sign-out. It follows the Swift clients'
//! `ServerAuthenticationController` so the desktop app, the macOS app, and the
//! CLI can share credentials and rotate them without spending a refresh token twice.

mod accounts;
mod error;
mod server;
mod session;

pub use accounts::{Accounts, SavedAccount, validate_server};
pub use error::Error;
pub use server::AuthorizationServer;
pub use session::{Account, PendingSignIn, Session, Status};
pub use tuist_oauth::Provider;
