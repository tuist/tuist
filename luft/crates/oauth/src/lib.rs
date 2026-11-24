//! The Tuist server's OAuth endpoints, as the Swift app and CLI use them:
//! the PKCE authorization-code flow over a loopback redirect (RFC 8252) and
//! both refresh grants. Calls are blocking;
//! run them away from the UI thread.

mod callback;
mod client;
mod error;
mod pkce;

pub use callback::LoopbackCallback;
#[cfg(feature = "network")]
pub use client::OAuthClient;
pub use client::{Provider, RefreshGrant, Tokens, authorization_url, endpoint};
pub use error::Error;
pub use pkce::Pkce;

/// Luft's OAuth client, which every Tuist server defines with the same ID
/// (`Tuist.OAuth.Clients.luft_client_id/0`). Luft is a first-party app: the
/// server trusts its sessions as the signed-in user rather than through scopes,
/// so new features need no new sign-in.
pub const LUFT_CLIENT_ID: &str = "6653b77b-b787-4eb2-b955-8380ea5f1478";

/// `ServerEnvironmentService.oauthClientId()`: refreshes for credentials that
/// do not record their issuing client use the built-in Tuist app client.
pub fn default_client_id() -> String {
    std::env::var("TUIST_OAUTH_CLIENT_ID")
        .unwrap_or_else(|_| "b3298a92-3deb-4f5e-a526-b7ad324979b5".into())
}
