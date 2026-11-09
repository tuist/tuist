//! The Tuist server's OAuth endpoints, as the Swift app and CLI use them:
//! dynamic client registration, the PKCE authorization-code flow over a
//! loopback redirect (RFC 8252), and both refresh grants. Calls are blocking;
//! run them away from the UI thread.

mod callback;
mod client;
mod error;
mod pkce;

pub use callback::LoopbackCallback;
pub use client::{OAuthClient, Provider, RefreshGrant, Tokens, authorization_url};
pub use error::Error;
pub use pkce::Pkce;

/// `ServerEnvironmentService.oauthClientId()`: refreshes for credentials that
/// do not record their issuing client use the built-in Tuist app client.
pub fn default_client_id() -> String {
    std::env::var("TUIST_OAUTH_CLIENT_ID")
        .unwrap_or_else(|_| "b3298a92-3deb-4f5e-a526-b7ad324979b5".into())
}
