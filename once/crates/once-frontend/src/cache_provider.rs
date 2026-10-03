use serde::Deserialize;

use crate::error::{Error, Result};

pub const DEFAULT_TUIST_URL: &str = "https://tuist.dev";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CacheProviderConfig {
    Local,
    Named(NamedCacheProviderConfig),
    Tuist(TuistCacheProviderConfig),
}

impl Default for CacheProviderConfig {
    fn default() -> Self {
        Self::Local
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NamedCacheProviderConfig {
    pub name: String,
    pub account: Option<String>,
    pub project: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TuistCacheProviderConfig {
    pub url: String,
    pub account: Option<String>,
    pub project: Option<String>,
    pub oauth_client_id: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct InfrastructureToml {
    pub cache: Option<CacheProviderToml>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub(crate) enum CacheProviderToml {
    Named(NamedCacheProviderToml),
    Direct(DirectCacheProviderToml),
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct NamedCacheProviderToml {
    name: String,
    account: Option<String>,
    project: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum DirectCacheProviderToml {
    Local,
    Tuist {
        url: Option<String>,
        account: Option<String>,
        project: Option<String>,
        oauth_client_id: Option<String>,
    },
}

impl CacheProviderToml {
    pub(crate) fn into_config(self, display_name: &str) -> Result<CacheProviderConfig> {
        match self {
            Self::Named(named) => {
                let name = named.name.trim().to_string();
                if name.is_empty() {
                    return Err(Error::Eval {
                        path: display_name.to_string(),
                        message: "cache_provider name must not be empty".to_string(),
                    });
                }
                Ok(CacheProviderConfig::Named(NamedCacheProviderConfig {
                    name,
                    account: non_empty(named.account),
                    project: non_empty(named.project),
                }))
            }
            Self::Direct(DirectCacheProviderToml::Local) => Ok(CacheProviderConfig::Local),
            Self::Direct(DirectCacheProviderToml::Tuist {
                url,
                account,
                project,
                oauth_client_id,
            }) => {
                let url = non_empty(url).unwrap_or_else(|| DEFAULT_TUIST_URL.to_string());
                Ok(CacheProviderConfig::Tuist(TuistCacheProviderConfig {
                    url,
                    account: non_empty(account),
                    project: non_empty(project),
                    oauth_client_id: non_empty(oauth_client_id),
                }))
            }
        }
    }
}

fn non_empty(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tuist_config_defaults_url() {
        let config = CacheProviderToml::Direct(DirectCacheProviderToml::Tuist {
            url: None,
            account: Some("acme".to_string()),
            project: Some("app".to_string()),
            oauth_client_id: None,
        })
        .into_config("once.toml")
        .unwrap();

        let CacheProviderConfig::Tuist(config) = config else {
            panic!("expected tuist config");
        };
        assert_eq!(config.url, DEFAULT_TUIST_URL);
        assert_eq!(config.oauth_client_id, None);
        assert_eq!(config.account.as_deref(), Some("acme"));
        assert_eq!(config.project.as_deref(), Some("app"));
    }

    #[test]
    fn named_config_keeps_scope_in_workspace() {
        let config = CacheProviderToml::Named(NamedCacheProviderToml {
            name: "tuist".to_string(),
            account: Some("acme".to_string()),
            project: Some("app".to_string()),
        })
        .into_config("once.toml")
        .unwrap();

        assert_eq!(
            config,
            CacheProviderConfig::Named(NamedCacheProviderConfig {
                name: "tuist".to_string(),
                account: Some("acme".to_string()),
                project: Some("app".to_string()),
            })
        );
    }
}
