//! Personal provider grants stay on Atlas. The browser returns only a correlated result.
use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, endpoint, error, invalid, now, random_string, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use url::Url;

const CALLBACK: &str = "dev.tuist.atlas://connections-callback";

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List,
    Begin { provider: Provider },
    Complete { pending: Pending, callback: String },
    Disconnect { provider: Provider },
}

#[derive(Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum Provider {
    Github,
    Slack,
    Google,
}

impl Provider {
    fn name(self) -> &'static str {
        match self {
            Self::Github => "github",
            Self::Slack => "slack",
            Self::Google => "google",
        }
    }
}

// Deliberately no Debug: pending state belongs only in the platform's secure store.
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Pending {
    provider: Provider,
    server: String,
    client_id: String,
    state: String,
    created_at: u64,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum ConnectionStatus {
    Connected,
    NotConnected,
    NeedsAuthorization,
}

#[derive(Deserialize, Serialize)]
struct Metadata {
    provider: Provider,
    name: String,
    configured: bool,
    account_name: Option<String>,
    scopes: Vec<String>,
    status: ConnectionStatus,
}

#[derive(Deserialize, Serialize)]
struct Connections {
    connections: Vec<Metadata>,
}

#[derive(Deserialize)]
struct Authorization {
    authorization_url: String,
}

#[derive(Deserialize, Serialize)]
struct Disconnected {
    disconnected: bool,
}

pub(crate) fn execute(session: Session, action: Action) -> Result<Value> {
    execute_using(&Network, session, action)
}

pub(super) fn execute_using(
    network: &impl Transport,
    session: Session,
    action: Action,
) -> Result<Value> {
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    if let Action::Complete { pending, callback } = action {
        return complete(&session, pending, &callback);
    }
    let pending = if let Action::Begin { provider } = action {
        Some(Pending {
            provider,
            server: server.to_string(),
            client_id: session.registration.client_id.clone(),
            state: random_string()?,
            created_at: now(),
        })
    } else {
        None
    };
    let base = "api/me/connections";
    let (method, path, payload) = match &action {
        Action::List => (Method::GET, base.to_string(), None),
        Action::Begin { provider } => (
            Method::POST,
            format!("{base}/{}/authorize", provider.name()),
            Some(json!({"state": pending.as_ref().unwrap().state})),
        ),
        Action::Disconnect { provider } => {
            (Method::DELETE, format!("{base}/{}", provider.name()), None)
        }
        Action::Complete { .. } => unreachable!(),
    };
    let url = server.join(&path).map_err(|_| invalid())?;
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload,
        failure: response_failure,
    };
    match action {
        Action::List => {
            let value: Connections = network.request(&url, body)?;
            let mut providers = Vec::new();
            for connection in &value.connections {
                if providers.contains(&connection.provider)
                    || connection.name.len() > 128
                    || connection
                        .account_name
                        .as_ref()
                        .is_some_and(|name| name.len() > 512)
                    || connection.scopes.len() > 64
                    || connection.scopes.iter().any(|scope| scope.len() > 256)
                {
                    return Err(invalid());
                }
                providers.push(connection.provider);
            }
            encode(value)
        }
        Action::Begin { provider } => {
            let value: Authorization = network.request(&url, body)?;
            let browser = endpoint(&server, &value.authorization_url)?;
            let pairs: Vec<_> = browser.query_pairs().collect();
            if browser.path() != format!("/connections/{}/authorize", provider.name())
                || pairs.len() != 1
                || pairs[0].0 != "native"
                || pairs[0].1.is_empty()
                || pairs[0].1.len() > 4096
            {
                return Err(invalid());
            }
            Ok(json!({"authorization_url": browser.as_str(), "pending": pending.unwrap()}))
        }
        Action::Disconnect { .. } => encode(network.request::<Disconnected>(&url, body)?),
        Action::Complete { .. } => unreachable!(),
    }
}

fn complete(session: &Session, pending: Pending, input: &str) -> Result<Value> {
    let invalid_callback = || {
        error(
            "invalid_callback",
            "This connection return is invalid or expired. Start again.",
        )
    };
    let server = validate_registration(&session.registration)?;
    if pending.server != server.as_str()
        || pending.client_id != session.registration.client_id
        || pending.state.len() != 43
        || pending.created_at > now()
        || now() - pending.created_at > 600
    {
        return Err(invalid_callback());
    }
    let callback = Url::parse(input).map_err(|_| invalid_callback())?;
    let mut destination = callback.clone();
    destination.set_query(None);
    destination.set_fragment(None);
    if destination.as_str() != CALLBACK {
        return Err(invalid_callback());
    }
    let pairs: Vec<_> = callback.query_pairs().collect();
    if pairs.len() != 3
        || pairs.iter().filter(|(key, _)| key == "state").count() != 1
        || pairs.iter().filter(|(key, _)| key == "provider").count() != 1
        || pairs.iter().filter(|(key, _)| key == "status").count() != 1
    {
        return Err(invalid_callback());
    }
    let get = |key| {
        pairs
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value.as_ref())
    };
    if get("state") != Some(pending.state.as_str())
        || get("provider") != Some(pending.provider.name())
        || !matches!(get("status"), Some("connected" | "error"))
    {
        return Err(invalid_callback());
    }
    // A browser result never proves a grant exists. Native adapters reload authenticated metadata.
    Ok(json!({"provider": pending.provider, "status": get("status")}))
}

fn encode(value: impl Serialize) -> Result<Value> {
    serde_json::to_value(value).map_err(|_| invalid())
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    match status {
        401 => error("sign_in_required", "Sign in to Atlas again."),
        403 => error("forbidden", "Atlas does not allow this connection."),
        404 | 501 => error(
            "unavailable",
            "Account connections require an updated Atlas server.",
        ),
        _ => error(
            "server",
            "Atlas could not update your connections. Try again.",
        ),
    }
}

#[cfg(test)]
#[path = "connections_tests.rs"]
mod tests;
