#[cfg(feature = "network")]
use reqwest::StatusCode;
#[cfg(feature = "network")]
use reqwest::blocking::{Client, Response};
use serde::Deserialize;
#[cfg(feature = "network")]
use std::{thread, time::Duration};
use url::Url;

#[cfg(feature = "network")]
use crate::Error;

#[cfg(feature = "network")]
const ATTEMPTS: u32 = 3;

/// Where the browser starts. The social providers sign in on the server and
/// then continue the same `/oauth2/authorize` request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provider {
    Tuist,
    Apple,
    Google,
    GitHub,
}

impl Provider {
    fn path(self) -> &'static str {
        match self {
            Self::Tuist => "oauth2/authorize",
            Self::Apple => "oauth2/apple",
            Self::Google => "oauth2/google",
            Self::GitHub => "oauth2/github",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: String,
}

pub enum RefreshGrant<'a> {
    /// Tokens from the OAuth authorization server (`type: account`), refreshed
    /// at `/oauth2/token` with the client that issued them.
    OAuth {
        refresh_token: &'a str,
        client_id: &'a str,
    },
    /// Legacy user tokens from `tuist auth login`, refreshed through the API.
    Legacy { refresh_token: &'a str },
}

pub fn authorization_url(
    server: &Url,
    provider: Provider,
    client_id: &str,
    redirect_uri: &str,
    challenge: &str,
    state: &str,
) -> Url {
    let mut url = endpoint(server, provider.path());
    url.query_pairs_mut()
        .append_pair("response_type", "code")
        .append_pair("client_id", client_id)
        .append_pair("redirect_uri", redirect_uri)
        .append_pair("state", state)
        .append_pair("code_challenge", challenge)
        .append_pair("code_challenge_method", "S256");
    url
}

#[cfg(feature = "network")]
#[derive(Debug, Clone)]
pub struct OAuthClient {
    http: Client,
}

#[cfg(feature = "network")]
impl Default for OAuthClient {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(feature = "network")]
impl OAuthClient {
    pub fn new() -> Self {
        let http = Client::builder()
            .timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("the TLS backend initializes");
        Self { http }
    }

    /// Fails with [`Error::UnsupportedServer`] unless the server advertises
    /// Luft's client (`/.well-known/luft.json`). Servers from before
    /// it would otherwise fail in the browser, mid sign-in.
    pub fn ensure_luft_client(&self, server: &Url) -> Result<(), Error> {
        #[derive(Deserialize)]
        struct Discovery {
            luft_oauth_client_id: Option<String>,
        }

        let response = send(|| {
            self.http
                .get(endpoint(server, ".well-known/luft.json"))
                .header("Accept", "application/json")
        })?;
        if response.status() != StatusCode::OK {
            return Err(Error::UnsupportedServer);
        }
        let bytes = response.bytes().map_err(transport)?;
        match serde_json::from_slice::<Discovery>(&bytes) {
            Ok(Discovery {
                luft_oauth_client_id: Some(id),
            }) if id == crate::LUFT_CLIENT_ID => Ok(()),
            _ => Err(Error::UnsupportedServer),
        }
    }

    pub fn exchange_code(
        &self,
        server: &Url,
        client_id: &str,
        code: &str,
        verifier: &str,
        redirect_uri: &str,
    ) -> Result<Tokens, Error> {
        let form = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirect_uri),
            ("client_id", client_id),
            ("code_verifier", verifier),
        ];
        // Authorization codes are single-use, so the exchange is never replayed.
        let response = self
            .http
            .post(endpoint(server, "oauth2/token"))
            .header("Accept", "application/json")
            .form(&form)
            .send()
            .map_err(transport)?;
        tokens(response)
    }

    /// Sends the refresh grant, retrying transport failures and 408/429/5xx with
    /// the same refresh token, which the server answers with the same pair for
    /// 60 seconds (`RefreshOAuthTokenService`).
    pub fn refresh(&self, server: &Url, grant: RefreshGrant<'_>) -> Result<Tokens, Error> {
        send(|| match grant {
            RefreshGrant::OAuth {
                refresh_token,
                client_id,
            } => self
                .http
                .post(endpoint(server, "oauth2/token"))
                .header("Accept", "application/json")
                .form(&[
                    ("grant_type", "refresh_token"),
                    ("refresh_token", refresh_token),
                    ("client_id", client_id),
                ]),
            RefreshGrant::Legacy { refresh_token } => self
                .http
                .post(endpoint(server, "api/auth/refresh_token"))
                .header("Content-Type", "application/json")
                .header("Accept", "application/json")
                .body(serde_json::json!({ "refresh_token": refresh_token }).to_string()),
        })
        .and_then(tokens)
    }
}

/// Appends a path to the server URL, keeping a self-hosted base path.
pub fn endpoint(server: &Url, path: &str) -> Url {
    let mut base = server.clone();
    if !base.path().ends_with('/') {
        base.set_path(&format!("{}/", base.path()));
    }
    base.join(path).expect("relative endpoint paths are valid")
}

#[cfg(feature = "network")]
fn send(request: impl Fn() -> reqwest::blocking::RequestBuilder) -> Result<Response, Error> {
    let mut attempt = 1;
    loop {
        let result = request().send().map_err(transport).and_then(|response| {
            let status = response.status();
            if status == StatusCode::REQUEST_TIMEOUT
                || status == StatusCode::TOO_MANY_REQUESTS
                || status.is_server_error()
            {
                Err(Error::Unavailable(status.as_u16()))
            } else {
                Ok(response)
            }
        });
        match result {
            Err(error) if error.is_transient() && attempt < ATTEMPTS => {
                thread::sleep(Duration::from_millis(500 * u64::from(attempt)));
                attempt += 1;
            }
            result => return result,
        }
    }
}

#[cfg(feature = "network")]
fn transport(error: reqwest::Error) -> Error {
    Error::Transport(error.to_string())
}

/// Token responses, classified like `RefreshOAuthTokenService.tokens(from:)`.
#[cfg(feature = "network")]
fn tokens(response: Response) -> Result<Tokens, Error> {
    #[derive(Deserialize)]
    struct Body {
        access_token: Option<String>,
        refresh_token: Option<String>,
        error: Option<String>,
        error_description: Option<String>,
        message: Option<String>,
    }

    let status = response.status();
    let body: Option<Body> = response
        .bytes()
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok());
    let rejected = |body: &Option<Body>| {
        let body = body.as_ref();
        Error::Rejected(
            body.and_then(|body| {
                body.error_description
                    .clone()
                    .or_else(|| body.message.clone())
            })
            .unwrap_or_else(|| "The refresh token is expired or invalid".into()),
        )
    };
    match status.as_u16() {
        200 => match body {
            Some(Body {
                access_token: Some(access_token),
                refresh_token: Some(refresh_token),
                ..
            }) => Ok(Tokens {
                access_token,
                refresh_token,
            }),
            // 200 without a pair: the server can no longer mint tokens for this subject.
            _ => Err(rejected(&body)),
        },
        401 => Err(rejected(&body)),
        400 if body.as_ref().and_then(|body| body.error.as_deref()) == Some("invalid_grant") => {
            Err(rejected(&body))
        }
        status => Err(Error::Status(status)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints_keep_a_self_hosted_base_path() {
        let server = Url::parse("https://example.com/tuist").unwrap();
        assert_eq!(
            endpoint(&server, "oauth2/token").as_str(),
            "https://example.com/tuist/oauth2/token"
        );
        let hosted = Url::parse("https://tuist.dev").unwrap();
        assert_eq!(
            endpoint(&hosted, "oauth2/token").as_str(),
            "https://tuist.dev/oauth2/token"
        );
    }

    #[test]
    fn social_providers_continue_the_same_authorization_request() {
        let server = Url::parse("https://tuist.dev").unwrap();
        let url = authorization_url(
            &server,
            Provider::GitHub,
            "client",
            "http://127.0.0.1:4317/callback",
            "challenge",
            "state",
        );
        assert_eq!(
            url.as_str(),
            "https://tuist.dev/oauth2/github?response_type=code&client_id=client&redirect_uri=http%3A%2F%2F127.0.0.1%3A4317%2Fcallback&state=state&code_challenge=challenge&code_challenge_method=S256"
        );
    }
}
