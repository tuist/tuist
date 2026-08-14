//! Caching and coalescing around the policy.
//!
//! The policy itself is cheap; what is expensive is asking Tuist's server. Both
//! stages are cached, and concurrent misses on the same key are collapsed into
//! one evaluation so a build starting a hundred requests at once makes one
//! backend call rather than a hundred.

use std::sync::Arc;
use std::time::{Duration, Instant};

use moka::Expiry;
use moka::future::Cache;
use moka::policy::EvictionPolicy;
use serde::Serialize;
use sha2::{Digest, Sha256};
use tokio::sync::Mutex;

use super::config::AuthConfig;
use super::policy::{self, Authentication, Authorization};
use super::target::{request_action, request_target};
use super::tuist::TuistBackend;
use crate::auth::{AccessDecision, DenyDecision, Principal, RequestContext};
use crate::metrics::Metrics;

pub type SharedAuth = Arc<AuthEngine>;

/// How long a decision stays cached is a property of the decision, not of the
/// cache: a grant outlives a denial, so that a caller who has just been given
/// access is not locked out by their own rejection.
pub trait Decision {
    fn ttl(&self) -> Duration;
}

impl Decision for Authorization {
    fn ttl(&self) -> Duration {
        Authorization::ttl(self)
    }
}

/// How long a confirmed principal is served before the backend is asked about
/// it again. It is the revocation latency for a credential that carries no
/// expiry of its own.
const REVALIDATE_AFTER: Duration = Duration::from_secs(10 * 60);

/// How long a confirmed principal stays usable at all. Past `REVALIDATE_AFTER`
/// it only answers while the backend cannot be reached, and past this it does
/// not answer at all, so an outage cannot keep a credential alive for as long
/// as the outage lasts.
const CONFIRMED_TTL: Duration = Duration::from_secs(25 * 60);

/// How long a backend that did not answer is left alone before the next
/// request tries it again. Without it every request past the serving deadline
/// dials a control plane that is already down.
const UNAVAILABLE_BACKOFF: Duration = Duration::from_secs(3);

const _: () = assert!(REVALIDATE_AFTER.as_secs() < CONFIRMED_TTL.as_secs());

/// What the backend confirmed for a credential, and the two deadlines that
/// govern reusing it.
#[derive(Clone, Debug)]
struct ConfirmedPrincipal {
    principal: Principal,
    /// Answered without asking the backend again until this instant.
    serve_until: Instant,
    /// Answered while the backend cannot be reached until this instant. Only a
    /// fresh backend answer moves it, so an outage cannot keep pushing it out.
    reusable_until: Instant,
}

impl ConfirmedPrincipal {
    fn needs_revalidation(&self, now: Instant) -> bool {
        now >= self.serve_until
    }

    /// Holds the next backend attempt off for a moment while keeping the reuse
    /// deadline where it was. `None` once the principal is no longer reusable,
    /// which is the point at which the node fails closed.
    fn held_off(&self, now: Instant) -> Option<Self> {
        if now >= self.reusable_until {
            return None;
        }

        Some(Self {
            principal: self.principal.clone(),
            serve_until: (now + UNAVAILABLE_BACKOFF).min(self.reusable_until),
            reusable_until: self.reusable_until,
        })
    }
}

#[derive(Clone, Debug)]
enum CachedAuthentication {
    Confirmed(ConfirmedPrincipal),
    Deny(DenyDecision),
}

impl Decision for CachedAuthentication {
    fn ttl(&self) -> Duration {
        match self {
            Self::Confirmed(confirmed) => confirmed
                .reusable_until
                .saturating_duration_since(Instant::now()),
            Self::Deny(_) => policy::DENY_TTL,
        }
    }
}

struct DecisionExpiry;

impl<K, V: Decision> Expiry<K, V> for DecisionExpiry {
    fn expire_after_create(&self, _key: &K, value: &V, _created_at: Instant) -> Option<Duration> {
        Some(value.ttl())
    }

    // moka's default keeps the deadline the entry was created with, which would
    // pin a revalidated principal to the lifetime of the one it replaced.
    fn expire_after_update(
        &self,
        _key: &K,
        value: &V,
        _updated_at: Instant,
        _duration_until_expiry: Option<Duration>,
    ) -> Option<Duration> {
        Some(value.ttl())
    }
}

pub struct AuthEngine {
    backend: TuistBackend,
    principals: Cache<String, CachedAuthentication>,
    decisions: Cache<String, Authorization>,
    /// One lock per credential, so exactly one request revalidates an entry
    /// past its serving deadline and the rest take that request's outcome.
    /// moka coalesces a miss but not a hit that has to be refreshed.
    revalidations: Cache<String, Arc<Mutex<()>>>,
    metrics: Metrics,
}

fn decision_cache<V>(max_entries: usize) -> Cache<String, V>
where
    V: Decision + Clone + Send + Sync + 'static,
{
    Cache::builder()
        .max_capacity(max_entries as u64)
        // moka defaults to TinyLFU, whose admission filter can reject a new
        // entry outright when the cache is full. A credential seen once or
        // twice is exactly what that filter rejects, and every new build starts
        // as one, so it would re-ask the backend on every request under load.
        .eviction_policy(EvictionPolicy::lru())
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
            revalidations: Cache::builder()
                .max_capacity(config.cache_max_entries as u64)
                .eviction_policy(EvictionPolicy::lru())
                .time_to_idle(UNAVAILABLE_BACKOFF * 20)
                .build(),
            metrics,
        })
    }

    pub async fn evaluate_access(&self, ctx: &RequestContext) -> AccessDecision {
        let principal = match self.resolve_authentication(ctx).await {
            Authentication::Principal(principal) => principal,
            Authentication::Deny(deny) | Authentication::Unavailable(deny) => {
                return AccessDecision::Deny(deny);
            }
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
        self.revalidations.invalidate_all();
        held as usize
    }

    async fn resolve_authentication(&self, ctx: &RequestContext) -> Authentication {
        let key = authentication_key(ctx);

        if let Some(cached) = self.principals.get(&key).await {
            match self.answer_from(cached.clone(), Instant::now()) {
                Some(answer) => {
                    self.metrics.record_auth_cache("authenticate", "hit");
                    return answer;
                }
                None => {
                    if let CachedAuthentication::Confirmed(stale) = cached {
                        return self.revalidate(ctx, key, stale).await;
                    }
                }
            }
        }

        self.authenticate_on_miss(ctx, key).await
    }

    /// What a cache entry answers on its own. `None` for a confirmed principal
    /// past its serving deadline, which has to go back to the backend first.
    fn answer_from(&self, cached: CachedAuthentication, now: Instant) -> Option<Authentication> {
        match cached {
            CachedAuthentication::Deny(deny) => Some(Authentication::Deny(deny)),
            CachedAuthentication::Confirmed(confirmed) if !confirmed.needs_revalidation(now) => {
                Some(Authentication::Principal(confirmed.principal))
            }
            CachedAuthentication::Confirmed(_) => None,
        }
    }

    async fn authenticate_on_miss(&self, ctx: &RequestContext, key: String) -> Authentication {
        let entry = self
            .principals
            .entry(key)
            .or_insert_with(async {
                let result = self.evaluate_policy(ctx).await;
                self.metrics.record_auth_cache("authenticate", "miss");
                self.cache_entry(result, ctx)
            })
            .await;

        // A caller that waited on someone else's evaluation counts as a hit:
        // what the label distinguishes is whether this request cost one.
        if !entry.is_fresh() {
            self.metrics.record_auth_cache("authenticate", "hit");
        }

        match entry.into_value() {
            CachedAuthentication::Confirmed(confirmed) => {
                Authentication::Principal(confirmed.principal)
            }
            CachedAuthentication::Deny(deny) => Authentication::Deny(deny),
        }
    }

    /// Asks the backend about a credential whose serving deadline has passed.
    ///
    /// One request does the asking and publishes what it learned; the rest take
    /// that answer, including a rejection. A backend that answered is taken at
    /// its word either way. One that did not answer says nothing about the
    /// credential, so the principal it already confirmed keeps answering until
    /// its reuse deadline, and the node fails closed after that.
    async fn revalidate(
        &self,
        ctx: &RequestContext,
        key: String,
        stale: ConfirmedPrincipal,
    ) -> Authentication {
        let lock = self
            .revalidations
            .get_with(key.clone(), async { Arc::new(Mutex::new(())) })
            .await;
        let _guard = lock.lock().await;

        // Someone else may have revalidated while this request waited on the
        // lock. Whatever they published is this request's answer too.
        if let Some(cached) = self.principals.get(&key).await
            && let Some(answer) = self.answer_from(cached, Instant::now())
        {
            self.metrics.record_auth_cache("authenticate", "hit");
            return answer;
        }

        self.metrics.record_auth_cache("authenticate", "revalidate");

        match self.evaluate_policy(ctx).await {
            Authentication::Principal(principal) => {
                let confirmed = self.confirm(principal.clone(), ctx);
                self.principals
                    .insert(key, CachedAuthentication::Confirmed(confirmed))
                    .await;
                Authentication::Principal(principal)
            }
            Authentication::Deny(deny) => {
                self.principals
                    .insert(key, CachedAuthentication::Deny(deny.clone()))
                    .await;
                Authentication::Deny(deny)
            }
            Authentication::Unavailable(deny) => match stale.held_off(Instant::now()) {
                Some(held) => {
                    let principal = held.principal.clone();
                    self.principals
                        .insert(key, CachedAuthentication::Confirmed(held))
                        .await;
                    self.metrics.record_auth_cache("authenticate", "stale");
                    Authentication::Principal(principal)
                }
                None => {
                    self.principals.invalidate(&key).await;
                    Authentication::Unavailable(deny)
                }
            },
        }
    }

    /// Ages the confirmed principal for this request so the next call to it has
    /// to revalidate. The deadlines are minutes long by design, which is longer
    /// than a test can wait.
    #[cfg(test)]
    pub(crate) async fn expire_serving_deadline(&self, ctx: &RequestContext) {
        let key = authentication_key(ctx);

        if let Some(CachedAuthentication::Confirmed(confirmed)) = self.principals.get(&key).await {
            let now = Instant::now();
            self.principals
                .insert(
                    key,
                    CachedAuthentication::Confirmed(ConfirmedPrincipal {
                        serve_until: now.checked_sub(Duration::from_secs(1)).unwrap_or(now),
                        ..confirmed
                    }),
                )
                .await;
        }
    }

    async fn evaluate_policy(&self, ctx: &RequestContext) -> Authentication {
        let start = Instant::now();
        let result = policy::authenticate(&self.backend, ctx).await;
        self.metrics
            .record_auth_decision("authenticate", result_label(&result), start.elapsed());
        result
    }

    fn cache_entry(&self, result: Authentication, ctx: &RequestContext) -> CachedAuthentication {
        match result {
            Authentication::Principal(principal) => {
                CachedAuthentication::Confirmed(self.confirm(principal, ctx))
            }
            // A node holding nothing confirmed has no answer to reuse, so an
            // unreachable backend denies. It is cached like any other denial so
            // a control plane that is down is not dialled once per request.
            Authentication::Deny(deny) | Authentication::Unavailable(deny) => {
                CachedAuthentication::Deny(deny)
            }
        }
    }

    fn confirm(&self, principal: Principal, ctx: &RequestContext) -> ConfirmedPrincipal {
        let now = Instant::now();

        // A credential that says when it expires is held until then and never
        // revalidated: the client stops presenting it at that point, so there
        // is nothing for a later answer to change, and reuse past its own
        // deadline is not something an outage should buy it.
        match policy::credential_expiry(ctx) {
            Some(remaining) => {
                let deadline = now + remaining.min(CONFIRMED_TTL);
                ConfirmedPrincipal {
                    principal,
                    serve_until: deadline,
                    reusable_until: deadline,
                }
            }
            None => ConfirmedPrincipal {
                principal,
                serve_until: now + REVALIDATE_AFTER,
                reusable_until: now + CONFIRMED_TTL,
            },
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
        Authentication::Unavailable(_) => "unavailable",
    }
}

/// The credentials plus what the request names.
///
/// The authentication result depends on the target: a token the backend calls
/// active, whose grants do not cover this project, falls through to the legacy
/// route and yields a principal shaped differently from the one those grants
/// produce, and the two authorize different projects. Keyed on the credentials
/// alone, whichever project asked first decided the answer for every other
/// project that token reaches, for as long as the entry lived.
fn authentication_key(ctx: &RequestContext) -> String {
    let credentials = credentials(ctx);

    match request_target(ctx) {
        Ok(target) => fingerprint(&(
            credentials,
            target.scope.key(),
            target.identifier,
            request_action(ctx).key(),
        )),
        // The policy rejects a request whose target it cannot resolve, and that
        // rejection is the same for every such request these credentials carry.
        Err(_) => fingerprint(&(credentials, "unresolved-target")),
    }
}

/// Exactly what authentication reads, so two requests carrying the same token
/// share a result and nothing else about them can split it.
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
    use std::collections::BTreeMap;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use base64::Engine as _;
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;

    use super::*;
    use crate::auth::DenyDecision;

    fn ctx_with_token(token: &str) -> RequestContext {
        let mut headers = BTreeMap::new();
        headers.insert("authorization".into(), format!("Bearer {token}"));

        RequestContext {
            transport: "http".into(),
            route: "/api/cache/cas/{id}".into(),
            method: "GET".into(),
            operation: "artifact.read".into(),
            server_tenant_id: "acme".into(),
            tenant_id: Some("acme".into()),
            namespace_id: Some("ios".into()),
            producer: None,
            artifact_key: None,
            artifact_hash: None,
            headers,
            query: BTreeMap::new(),
            status_code: None,
        }
    }

    /// A token shaped like a JWT whose payload carries `exp`. Nothing verifies
    /// the signature here, which is the point: the node reads `exp` only from a
    /// credential the backend has already confirmed.
    fn token_expiring_in(seconds: u64) -> String {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("a clock after the epoch")
            .as_secs();
        let payload =
            URL_SAFE_NO_PAD.encode(serde_json::json!({ "exp": now + seconds }).to_string());

        format!("header.{payload}.signature")
    }

    fn deny(message: &str) -> Authorization {
        Authorization::Deny(DenyDecision {
            status: 403,
            message: message.into(),
        })
    }

    fn engine() -> AuthEngine {
        AuthEngine::new(
            AuthConfig {
                // Never dialled: these cases decide from what is already held.
                base_url: "http://127.0.0.1:1".into(),
                connect_timeout: Duration::from_millis(1),
                request_timeout: Duration::from_millis(1),
                verifier: None,
                introspection: None,
                cache_max_entries: 16,
            },
            Metrics::new("test".into(), "tenant".into()),
        )
        .expect("build the authorization engine")
    }

    fn principal(id: &str) -> Principal {
        Principal {
            id: id.into(),
            kind: "account".into(),
            attributes: serde_json::json!({}),
        }
    }

    fn confirmed(serve_in: Duration, reusable_in: Duration) -> ConfirmedPrincipal {
        let now = Instant::now();
        ConfirmedPrincipal {
            principal: principal("a"),
            serve_until: now + serve_in,
            reusable_until: now + reusable_in,
        }
    }

    // Inside its serving deadline the entry answers on its own, which is what
    // keeps a build's worth of requests off the backend.
    #[test]
    fn a_confirmed_principal_answers_until_its_serving_deadline() {
        let engine = engine();
        let held = confirmed(Duration::from_secs(60), Duration::from_secs(600));

        assert!(matches!(
            engine.answer_from(CachedAuthentication::Confirmed(held), Instant::now()),
            Some(Authentication::Principal(found)) if found.id == "a"
        ));
    }

    // Past it the entry cannot answer alone: the backend has to be asked before
    // this credential is served again.
    #[test]
    fn a_confirmed_principal_stops_answering_past_its_serving_deadline() {
        let engine = engine();
        let mut held = confirmed(Duration::from_secs(60), Duration::from_secs(600));
        held.serve_until = Instant::now() - Duration::from_secs(1);

        assert!(
            engine
                .answer_from(CachedAuthentication::Confirmed(held), Instant::now())
                .is_none()
        );
    }

    // A control-plane blip must not become a cache outage. The principal the
    // backend did confirm keeps answering, and the next attempt is held off so
    // a control plane that is down is not dialled once per request.
    #[test]
    fn an_unreachable_backend_reuses_the_principal_and_holds_the_next_attempt_off() {
        let held = confirmed(Duration::from_secs(0), Duration::from_secs(600));
        let now = Instant::now();

        let reused = held.held_off(now).expect("the principal is still reusable");

        assert_eq!(reused.reusable_until, held.reusable_until);
        assert!(reused.serve_until > now);
        assert!(reused.serve_until <= now + UNAVAILABLE_BACKOFF);
    }

    // The reuse deadline is the bound on the whole fallback. Past it there is
    // nothing left to answer with and the node fails closed.
    #[test]
    fn a_principal_past_its_reuse_deadline_is_not_reusable() {
        let mut held = confirmed(Duration::from_secs(0), Duration::from_secs(0));
        held.reusable_until = Instant::now() - Duration::from_secs(1);

        assert!(held.held_off(Instant::now()).is_none());
    }

    // Only a fresh backend answer moves the reuse deadline, so repeated
    // fallbacks during an outage cannot walk it forward indefinitely.
    #[test]
    fn reuse_during_an_outage_never_extends_the_reuse_deadline() {
        let held = confirmed(Duration::from_secs(0), Duration::from_secs(600));
        let now = Instant::now();

        let once = held.held_off(now).expect("reusable");
        let twice = once
            .held_off(now + UNAVAILABLE_BACKOFF)
            .expect("still reusable");

        assert_eq!(twice.reusable_until, held.reusable_until);
    }

    // A credential that carries its own expiry is held until then and not
    // revalidated, so the two deadlines coincide and an outage buys it nothing.
    #[test]
    fn a_credential_carrying_an_expiry_is_held_until_that_expiry() {
        let engine = engine();
        let mut ctx = ctx_with_token(&token_expiring_in(120));
        ctx.tenant_id = Some("acme".into());

        let held = engine.confirm(principal("a"), &ctx);

        assert_eq!(held.serve_until, held.reusable_until);
        assert!(held.reusable_until <= Instant::now() + Duration::from_secs(120));
        assert!(held.reusable_until > Instant::now() + Duration::from_secs(110));
    }

    // A credential that carries no expiry gets the cache's own deadlines: a
    // serving window, and a longer window it may be reused within.
    #[test]
    fn a_credential_carrying_no_expiry_gets_the_caches_own_deadlines() {
        let engine = engine();
        let ctx = ctx_with_token("opaque-token");

        let held = engine.confirm(principal("a"), &ctx);

        assert!(held.serve_until < held.reusable_until);
        assert!(held.reusable_until > Instant::now() + REVALIDATE_AFTER);
    }

    // An expiry further out than the cache's own bound does not extend it.
    #[test]
    fn a_far_future_expiry_is_capped_at_the_reuse_bound() {
        let engine = engine();
        let ctx = ctx_with_token(&token_expiring_in(60 * 60 * 24 * 28));

        let held = engine.confirm(principal("a"), &ctx);

        assert!(held.reusable_until <= Instant::now() + CONFIRMED_TTL);
    }

    // The same token asking about two projects must not share an answer: the
    // policy resolves each project separately and can reach a different
    // principal for each.
    #[test]
    fn the_key_separates_two_projects_carrying_the_same_token() {
        let mut first = ctx_with_token("token");
        first.tenant_id = Some("acme".into());
        first.namespace_id = Some("ios".into());

        let mut second = first.clone();
        second.namespace_id = Some("android".into());

        assert_ne!(authentication_key(&first), authentication_key(&second));
    }

    // Reading and writing are separate questions for the same reason.
    #[test]
    fn the_key_separates_a_read_from_a_write() {
        let mut read = ctx_with_token("token");
        read.tenant_id = Some("acme".into());
        read.namespace_id = Some("ios".into());

        let mut write = read.clone();
        write.method = "PUT".into();
        write.operation = "artifact.write".into();

        assert_ne!(authentication_key(&read), authentication_key(&write));
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

    // Replacing an entry has to reset its lifetime. moka's default keeps the
    // one the replaced entry was created with, which would pin a revalidated
    // principal to the deadline of the principal it replaced.
    #[test]
    fn replacing_a_decision_resets_its_lifetime() {
        let expiry = DecisionExpiry;

        assert_eq!(
            Expiry::<String, Authorization>::expire_after_update(
                &expiry,
                &"k".to_string(),
                &Authorization::Allow,
                Instant::now(),
                Some(Duration::from_secs(1)),
            ),
            Some(Authorization::Allow.ttl())
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
