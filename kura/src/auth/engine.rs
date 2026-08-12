//! Caching and coalescing around the policy.
//!
//! The policy itself is cheap; what is expensive is asking Tuist's server. Both
//! stages are cached per credentials, and concurrent misses on the same key are
//! collapsed into one evaluation so a build starting a hundred requests at once
//! makes one backend call rather than a hundred.

use std::collections::HashMap;
use std::sync::{Arc, Mutex as StdMutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use sha2::{Digest, Sha256};
use tokio::sync::{RwLock, broadcast};
use tracing::warn;

use super::config::AuthConfig;
use super::policy::{self, Authentication, Authorization};
use super::tuist::TuistBackend;
use crate::auth::{AccessDecision, Principal, RequestContext};
use crate::metrics::Metrics;

pub type SharedAuth = Arc<AuthEngine>;

pub struct AuthEngine {
    config: AuthConfig,
    backend: TuistBackend,
    principal_cache: RwLock<HashMap<String, Cached<Authentication>>>,
    decision_cache: RwLock<HashMap<String, Cached<Authorization>>>,
    authenticate_flight: SingleFlight<Authentication>,
    authorize_flight: SingleFlight<Authorization>,
    metrics: Metrics,
}

#[derive(Clone)]
struct Cached<T> {
    expires_at: Instant,
    result: T,
}

// Collapses concurrent misses on the same key into one evaluation. Without it a
// burst of requests carrying the same credentials each calls the backend.
struct SingleFlight<T> {
    inflight: StdMutex<HashMap<String, broadcast::Sender<T>>>,
}

enum Flight<'a, T: Clone> {
    Leader(FlightGuard<'a, T>),
    Follower(broadcast::Receiver<T>),
}

impl<T: Clone> SingleFlight<T> {
    fn new() -> Self {
        Self {
            inflight: StdMutex::new(HashMap::new()),
        }
    }

    fn join(&self, key: &str) -> Flight<'_, T> {
        let mut inflight = self
            .inflight
            .lock()
            .expect("single-flight mutex is never held across a panic");
        match inflight.get(key) {
            Some(sender) => Flight::Follower(sender.subscribe()),
            None => {
                let (sender, _) = broadcast::channel(1);
                inflight.insert(key.to_owned(), sender.clone());
                Flight::Leader(FlightGuard {
                    flight: self,
                    key: key.to_owned(),
                    sender,
                    settled: false,
                })
            }
        }
    }

    fn forget(&self, key: &str) {
        self.inflight
            .lock()
            .expect("single-flight mutex is never held across a panic")
            .remove(key);
    }
}

// Held by the leader while it evaluates. Publishing hands the result to every
// follower; dropping without publishing (the request was cancelled) closes the
// channel so followers retry instead of hanging.
struct FlightGuard<'a, T: Clone> {
    flight: &'a SingleFlight<T>,
    key: String,
    sender: broadcast::Sender<T>,
    settled: bool,
}

impl<T: Clone> FlightGuard<'_, T> {
    fn publish(mut self, result: T) {
        self.settle();
        let _ = self.sender.send(result);
    }

    fn settle(&mut self) {
        if !self.settled {
            self.settled = true;
            self.flight.forget(&self.key);
        }
    }
}

impl<T: Clone> Drop for FlightGuard<'_, T> {
    fn drop(&mut self) {
        self.settle();
    }
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
            config,
            backend,
            principal_cache: RwLock::new(HashMap::new()),
            decision_cache: RwLock::new(HashMap::new()),
            authenticate_flight: SingleFlight::new(),
            authorize_flight: SingleFlight::new(),
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
        let mut principal_cache = self.principal_cache.write().await;
        let principals = principal_cache.len();
        principal_cache.clear();
        drop(principal_cache);

        let mut decision_cache = self.decision_cache.write().await;
        let decisions = decision_cache.len();
        decision_cache.clear();

        principals + decisions
    }

    // The key covers the credentials only, so a token that has already been
    // resolved is not resolved again for the next request carrying it. What the
    // token may do is settled per request by the authorization stage below.
    async fn resolve_authentication(&self, ctx: &RequestContext) -> Authentication {
        let key = fingerprint(&credentials(ctx));

        loop {
            if let Some(result) = cached(&self.principal_cache, &key).await {
                self.metrics.record_auth_cache("authenticate", "hit");
                return result;
            }

            match self.authenticate_flight.join(&key) {
                Flight::Leader(guard) => {
                    self.metrics.record_auth_cache("authenticate", "miss");
                    let start = Instant::now();
                    let result = policy::authenticate(&self.backend, ctx).await;
                    self.metrics.record_auth_decision(
                        "authenticate",
                        result_label(&result),
                        start.elapsed(),
                    );
                    self.store(&self.principal_cache, &key, result.clone(), result.ttl())
                        .await;
                    guard.publish(result.clone());
                    return result;
                }
                Flight::Follower(mut receiver) => {
                    // A closed channel means the leader was cancelled before
                    // publishing. Retry: either its result landed in the cache,
                    // or we take leadership.
                    if let Ok(result) = receiver.recv().await {
                        self.metrics.record_auth_cache("authenticate", "coalesced");
                        return result;
                    }
                }
            }
        }
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

        loop {
            if let Some(result) = cached(&self.decision_cache, &key).await {
                self.metrics.record_auth_cache("authorize", "hit");
                return result;
            }

            match self.authorize_flight.join(&key) {
                Flight::Leader(guard) => {
                    self.metrics.record_auth_cache("authorize", "miss");
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
                    self.store(&self.decision_cache, &key, result.clone(), result.ttl())
                        .await;
                    guard.publish(result.clone());
                    return result;
                }
                Flight::Follower(mut receiver) => {
                    // A closed channel means the leader was cancelled before
                    // publishing. Retry: either its result landed in the cache,
                    // or we take leadership.
                    if let Ok(result) = receiver.recv().await {
                        self.metrics.record_auth_cache("authorize", "coalesced");
                        return result;
                    }
                }
            }
        }
    }

    async fn store<T: Clone>(
        &self,
        cache: &RwLock<HashMap<String, Cached<T>>>,
        key: &str,
        result: T,
        ttl: Duration,
    ) {
        let mut cache = cache.write().await;
        // Expiry alone does not bound the map, so a sweep of dead entries runs
        // before the cap is enforced.
        if cache.len() >= self.config.cache_max_entries {
            let now = Instant::now();
            cache.retain(|_, entry| entry.expires_at > now);
        }
        if cache.len() >= self.config.cache_max_entries {
            warn!(
                "authorization cache is at its {} entry cap; not caching",
                self.config.cache_max_entries
            );
            return;
        }

        cache.insert(
            key.to_owned(),
            Cached {
                expires_at: Instant::now() + ttl,
                result,
            },
        );
    }
}

async fn cached<T: Clone>(cache: &RwLock<HashMap<String, Cached<T>>>, key: &str) -> Option<T> {
    let entry = cache.read().await;
    entry
        .get(key)
        .filter(|entry| entry.expires_at > Instant::now())
        .map(|entry| entry.result.clone())
}

fn result_label(result: &Authentication) -> &'static str {
    match result {
        Authentication::Principal(_) => "principal",
        Authentication::Deny(_) => "deny",
    }
}

/// Only the credentials, never the rest of the request: two requests carrying
/// the same token share an authentication result.
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
