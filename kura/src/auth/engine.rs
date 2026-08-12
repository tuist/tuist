//! Caching and coalescing around the policy.
//!
//! The policy itself is cheap; what is expensive is asking Tuist's server. Both
//! stages are cached per credentials, and concurrent misses on the same key are
//! collapsed into one evaluation so a build starting a hundred requests at once
//! makes one backend call rather than a hundred.

use std::sync::Arc;
use std::time::{Duration, Instant};

use moka::Expiry;
use moka::future::Cache;
use serde::Serialize;
use sha2::{Digest, Sha256};

use super::config::AuthConfig;
use super::policy::{self, Authentication, Authorization};
use super::tuist::TuistBackend;
use crate::auth::{AccessDecision, Principal, RequestContext};
use crate::metrics::Metrics;

pub type SharedAuth = Arc<AuthEngine>;

/// How long a decision stays cached is a property of the decision, not of the
/// cache: a grant outlives a denial, so that a caller who has just been given
/// access is not locked out by their own rejection.
pub trait Decision {
    fn ttl(&self) -> Duration;
}

impl Decision for Authentication {
    fn ttl(&self) -> Duration {
        Authentication::ttl(self)
    }
}

impl Decision for Authorization {
    fn ttl(&self) -> Duration {
        Authorization::ttl(self)
    }
}

struct DecisionExpiry;

impl<K, V: Decision> Expiry<K, V> for DecisionExpiry {
    fn expire_after_create(&self, _key: &K, value: &V, _created_at: Instant) -> Option<Duration> {
        Some(value.ttl())
    }
}

pub struct AuthEngine {
    backend: TuistBackend,
    principals: Cache<String, Authentication>,
    decisions: Cache<String, Authorization>,
    metrics: Metrics,
}

fn decision_cache<V>(max_entries: usize) -> Cache<String, V>
where
    V: Decision + Clone + Send + Sync + 'static,
{
    Cache::builder()
        .max_capacity(max_entries as u64)
        .expire_after(DecisionExpiry)
        .build()
}

impl AuthEngine {
    pub fn from_env(metrics: Metrics) -> Result<Option<SharedAuth>, String> {
        let Some(config) = AuthConfig::from_env()? else {
            return Ok(None);
        };
        Ok(Some(Arc::new(Self::new(config, metrics)?)))
    }

    pub fn new(config: AuthConfig, metrics: Metrics) -> Result<Self, String> {
        let backend = TuistBackend::new(
            config.base_url.clone(),
            config.connect_timeout,
            config.request_timeout,
            config.verifier.clone(),
            config.introspection.clone(),
            metrics.clone(),
        )?;

        Ok(Self {
            backend,
            principals: decision_cache(config.cache_max_entries),
            decisions: decision_cache(config.cache_max_entries),
            metrics,
        })
    }

    pub async fn evaluate_access(&self, ctx: &RequestContext) -> AccessDecision {
        let principal = match self.resolve_authentication(ctx).await {
            Authentication::Principal(principal) => principal,
            Authentication::Deny(deny) => return AccessDecision::Deny(deny),
        };

        match self.resolve_authorization(ctx, &principal).await {
            Authorization::Allow => AccessDecision::Allow,
            Authorization::Deny(deny) => AccessDecision::Deny(deny),
        }
    }

    pub async fn clear_caches(&self) -> usize {
        // Approximate, and only used to decide whether anything was worth
        // reporting; the caches are performance state, not correctness state.
        let held = self.principals.entry_count() + self.decisions.entry_count();
        self.principals.invalidate_all();
        self.decisions.invalidate_all();
        held as usize
    }

    // The key covers the credentials only, so a token that has already been
    // resolved is not resolved again for the next request carrying it. What the
    // token may do is settled per request by the authorization stage below.
    async fn resolve_authentication(&self, ctx: &RequestContext) -> Authentication {
        let key = fingerprint(&credentials(ctx));

        let entry = self
            .principals
            .entry(key)
            .or_insert_with(async {
                let start = Instant::now();
                let result = policy::authenticate(&self.backend, ctx).await;
                self.metrics.record_auth_decision(
                    "authenticate",
                    result_label(&result),
                    start.elapsed(),
                );
                self.metrics.record_auth_cache("authenticate", "miss");
                result
            })
            .await;

        // A caller that waited on someone else's evaluation counts as a hit:
        // what the label distinguishes is whether this request cost one.
        if !entry.is_fresh() {
            self.metrics.record_auth_cache("authenticate", "hit");
        }
        entry.into_value()
    }

    async fn resolve_authorization(
        &self,
        ctx: &RequestContext,
        principal: &Principal,
    ) -> Authorization {
        let key = fingerprint(&(
            credentials(ctx),
            principal,
            &ctx.server_tenant_id,
            &ctx.tenant_id,
            &ctx.namespace_id,
            &ctx.operation,
            &ctx.producer,
            &ctx.route,
            &ctx.method,
        ));

        let entry = self
            .decisions
            .entry(key)
            .or_insert_with(async {
                let start = Instant::now();
                let result = policy::authorize(ctx, Some(principal));
                self.metrics.record_auth_decision(
                    "authorize",
                    match result {
                        Authorization::Allow => "allow",
                        Authorization::Deny(_) => "deny",
                    },
                    start.elapsed(),
                );
                self.metrics.record_auth_cache("authorize", "miss");
                result
            })
            .await;

        if !entry.is_fresh() {
            self.metrics.record_auth_cache("authorize", "hit");
        }
        entry.into_value()
    }
}

fn result_label(result: &Authentication) -> &'static str {
    match result {
        Authentication::Principal(_) => "principal",
        Authentication::Deny(_) => "deny",
    }
}

/// Exactly what authentication reads, so two requests carrying the same token
/// share a result and nothing else about them can split it. The hook this
/// replaced also keyed on `cookie`, `proxy-authorization` and `x-api-key`,
/// which no policy has ever consulted.
fn credentials(ctx: &RequestContext) -> String {
    ctx.headers
        .get("authorization")
        .or_else(|| ctx.headers.get("Authorization"))
        .cloned()
        .unwrap_or_default()
}

fn fingerprint<T: Serialize>(value: &T) -> String {
    let encoded = serde_json::to_vec(value).unwrap_or_default();
    let mut hasher = Sha256::new();
    hasher.update(&encoded);
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::auth::DenyDecision;

    fn deny(message: &str) -> Authorization {
        Authorization::Deny(DenyDecision {
            status: 403,
            message: message.into(),
        })
    }

    #[test]
    fn a_decision_carries_its_own_lifetime_into_the_cache() {
        let expiry = DecisionExpiry;
        let created = Instant::now();

        assert_eq!(
            Expiry::<String, Authorization>::expire_after_create(
                &expiry,
                &"k".to_string(),
                &Authorization::Allow,
                created
            ),
            Some(Authorization::Allow.ttl())
        );
        assert_eq!(
            Expiry::<String, Authorization>::expire_after_create(
                &expiry,
                &"k".to_string(),
                &deny("no"),
                created
            ),
            Some(deny("no").ttl())
        );
    }

    // moka documents that it recovers when the caller running `init` panics,
    // but says nothing about that caller being cancelled. These evaluations are
    // request-scoped, so a client that disconnects mid-request drops the one
    // everyone else is waiting on. Pinned here because the crate does not
    // promise it and an upgrade could take it away.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_cancelled_evaluation_does_not_strand_the_next_caller() {
        let cache: Cache<String, Authorization> = decision_cache(16);
        let entered = Arc::new(AtomicUsize::new(0));

        let abandoned_cache = cache.clone();
        let abandoned_entered = entered.clone();
        let abandoned = tokio::spawn(async move {
            abandoned_cache
                .get_with("k".to_string(), async move {
                    abandoned_entered.fetch_add(1, Ordering::SeqCst);
                    std::future::pending::<()>().await;
                    Authorization::Allow
                })
                .await
        });

        while entered.load(Ordering::SeqCst) == 0 {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        abandoned.abort();
        let _ = abandoned.await;

        let resolved = tokio::time::timeout(
            Duration::from_secs(5),
            cache.get_with("k".to_string(), async { deny("evaluated by the survivor") }),
        )
        .await
        .expect("a cancelled evaluation must not strand later callers");

        assert_eq!(resolved, deny("evaluated by the survivor"));
    }
}
