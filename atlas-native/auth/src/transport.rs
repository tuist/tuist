use crate::{Result, error, invalid};
use reqwest::blocking::{Client, Response};
use serde::de::DeserializeOwned;
use serde_json::Value;
use std::sync::OnceLock;
use std::time::Duration;
use url::Url;

pub(crate) enum Body<'a> {
    Get,
    Public {
        failure: fn(u16, &[u8]) -> crate::AuthError,
    },
    Json(Value),
    Form(Vec<(&'a str, &'a str)>),
    Api {
        method: reqwest::Method,
        token: &'a str,
        payload: Option<Value>,
        failure: fn(u16, &[u8]) -> crate::AuthError,
    },
}

pub(crate) trait Transport {
    fn request<T: DeserializeOwned>(&self, url: &Url, body: Body<'_>) -> Result<T>;
}

pub(crate) struct Network;

impl Transport for Network {
    fn request<T: DeserializeOwned>(&self, url: &Url, body: Body<'_>) -> Result<T> {
        let client = client()?;
        let request = match body {
            Body::Get => client.get(url.clone()),
            Body::Public { failure } => {
                return response_using(
                    client
                        .get(url.clone())
                        .header("accept", "application/json")
                        .send(),
                    failure,
                );
            }
            Body::Json(value) => client.post(url.clone()).json(&value),
            Body::Form(parameters) => client.post(url.clone()).form(&parameters),
            Body::Api {
                method,
                token,
                payload,
                failure,
            } => {
                let request = client
                    .request(method, url.clone())
                    .bearer_auth(token)
                    .header("accept", "application/json")
                    .header("cache-control", "no-store");
                let request = if let Some(payload) = payload {
                    request.json(&payload)
                } else {
                    request
                };
                return response_using(request.send(), failure);
            }
        };
        response(request.send())
    }
}

fn client() -> Result<&'static Client> {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    if let Some(client) = CLIENT.get() {
        return Ok(client);
    }
    let client = Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(30))
        .connect_timeout(Duration::from_secs(10))
        .user_agent("AtlasNative/0.1")
        .build()
        .map_err(|_| error("network", "Could not initialize secure networking."))?;
    let _ = CLIENT.set(client);
    Ok(CLIENT.get().expect("client was initialized"))
}

fn response<T: DeserializeOwned>(response: reqwest::Result<Response>) -> Result<T> {
    response_using(response, response_failure)
}

fn response_using<T: DeserializeOwned>(
    response: reqwest::Result<Response>,
    failure: fn(u16, &[u8]) -> crate::AuthError,
) -> Result<T> {
    use std::io::Read;
    const MAX_RESPONSE_BYTES: u64 = 1024 * 1024;
    let response = response
        .map_err(|_| error("network", "Could not connect securely to Atlas. Try again."))?;
    let status = response.status();
    let mut bytes = Vec::new();
    response
        .take(MAX_RESPONSE_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| invalid())?;
    if bytes.len() as u64 > MAX_RESPONSE_BYTES {
        return Err(invalid());
    }
    if !status.is_success() {
        return Err(failure(status.as_u16(), &bytes));
    }
    serde_json::from_slice(&bytes).map_err(|_| invalid())
}

pub(super) fn response_failure(status: u16, bytes: &[u8]) -> crate::AuthError {
    // Only definitive OAuth credential failures clear secure storage. A proxy
    // or server failure, even with HTTP 400, must not destroy a refresh token.
    let oauth_error = serde_json::from_slice::<Value>(bytes).ok();
    let credential_failure = oauth_error.as_ref().and_then(|body| body["error"].as_str());
    if matches!(status, 400 | 401)
        && matches!(
            credential_failure,
            Some("invalid_grant" | "invalid_client" | "unauthorized_client")
        )
    {
        error("rejected", "Atlas rejected the credentials. Sign in again.")
    } else {
        error(
            "server",
            "Atlas could not complete the request. Try again later.",
        )
    }
}
