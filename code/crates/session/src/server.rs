use tuist_oauth::{Error, OAuthClient, RefreshGrant, Tokens};
use url::Url;

/// The Tuist server's OAuth endpoints a session needs.
pub trait AuthorizationServer: Send + Sync {
    fn register(&self, server: &Url, redirect_uri: &str) -> Result<String, Error>;
    fn exchange_code(
        &self,
        server: &Url,
        client_id: &str,
        code: &str,
        verifier: &str,
        redirect_uri: &str,
    ) -> Result<Tokens, Error>;
    fn refresh(&self, server: &Url, grant: RefreshGrant<'_>) -> Result<Tokens, Error>;
}

impl AuthorizationServer for OAuthClient {
    fn register(&self, server: &Url, redirect_uri: &str) -> Result<String, Error> {
        OAuthClient::register(self, server, redirect_uri)
    }

    fn exchange_code(
        &self,
        server: &Url,
        client_id: &str,
        code: &str,
        verifier: &str,
        redirect_uri: &str,
    ) -> Result<Tokens, Error> {
        OAuthClient::exchange_code(self, server, client_id, code, verifier, redirect_uri)
    }

    fn refresh(&self, server: &Url, grant: RefreshGrant<'_>) -> Result<Tokens, Error> {
        OAuthClient::refresh(self, server, grant)
    }
}
