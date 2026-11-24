use tuist_oauth::{Error, OAuthClient, RefreshGrant, Tokens};
use url::Url;

/// The Tuist server's OAuth endpoints a session needs.
pub trait AuthorizationServer: Send + Sync {
    fn ensure_luft_client(&self, server: &Url) -> Result<(), Error>;
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
    fn ensure_luft_client(&self, server: &Url) -> Result<(), Error> {
        OAuthClient::ensure_luft_client(self, server)
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
