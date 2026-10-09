mod auth;
mod cache;

use reqwest::Url;

use crate::{Error, Result};

pub use auth::{TuistAuth, TuistAuthPrompt, TUIST_APP_OAUTH_CLIENT_ID, TUIST_OAUTH_CLIENT_ID_ENV};
pub use cache::TuistCache;

const PROVIDER_NAME: &str = "tuist";
const ENDPOINTS_PATH: &str = "api/cache/endpoints";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TuistCacheConfig {
    pub url: String,
    pub account: Option<String>,
    pub project: Option<String>,
    pub oauth_client_id: Option<String>,
    pub provider_name: String,
}

fn join_url(base: &str, path: &str) -> Result<Url> {
    let normalized = format!("{}/", base.trim_end_matches('/'));
    let url = Url::parse(&normalized).map_err(|source| Error::InvalidConfig {
        provider: PROVIDER_NAME,
        message: format!("invalid URL `{base}`: {source}"),
    })?;
    url.join(path.trim_start_matches('/'))
        .map_err(|source| Error::InvalidConfig {
            provider: PROVIDER_NAME,
            message: format!("invalid URL path `{path}`: {source}"),
        })
}

fn env_token(name: &str) -> Option<String> {
    std::env::var(name).ok().and_then(|token| {
        let trimmed = token.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

async fn remote_status_message(response: reqwest::Response) -> String {
    let status = response.status();
    let body = response.text().await.unwrap_or_default();
    if body.trim().is_empty() {
        format!("HTTP {}", status.as_u16())
    } else {
        format!("HTTP {}: {}", status.as_u16(), body.trim())
    }
}
