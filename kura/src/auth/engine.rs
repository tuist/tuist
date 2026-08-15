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

/// How long a decision stands before it is worked out again.
///
/// Short on purpose, and load-bearing: this is what stands in for invalidating
/// decisions when the principal behind them changes. Working one out again is a
/// local check against the principal the node already holds, not a backend
/// call, so short costs almost nothing — raising it for performance would buy
/// very little and reopen a window where a decision outlives the grants it was
/// made from.
const DECISION_TTL: Duration = Duration::from_secs(5);

/// How long a refusal stands. Shorter still, so a caller who has just been
/// granted access is not locked out by their own rejection and a server that
/// has come back is asked again promptly.
const REFUSAL_TTL: Duration = Duration::from_secs(3);

/// How long a confirmed principal is served before the backend is asked about
/// it again. It is the revocation latency, and it is the same for every
/// credential: expiry says when one runs out, not whether it was withdrawn.
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

/// One credential reaches several targets and actions, and losing a decision
/// costs a local recompute where losing a principal costs a round trip, so the
/// cheaper cache is the one given room.
const DECISIONS_PER_CREDENTIAL: usize = 2;

const _: () = assert!(REVALIDATE_AFTER.as_secs() < CONFIRMED_TTL.as_secs());
const _: () = assert!(REFUSAL_TTL.as_secs() <= DECISION_TTL.as_secs());

/// What the node answers a request with, and what it holds to answer the next
/// one shaped the same way.
///
/// `Unavailable` is kept apart from `Deny` here rather than flattened into it,
/// because the two are the same answer to the caller and different facts about
/// the backend, and the engine reads that difference.
#[derive(Clone, Debug, PartialEq)]
enum CachedDecision {
    Allow,
    Deny(DenyDecision),
    Unavailable(DenyDecision),
}

impl CachedDecision {
    fn label(&self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Deny(_) => "deny",
            Self::Unavailable(_) => "unavailable",
        }
    }

    fn into_access(self) -> AccessDecision {
        match self {
            Self::Allow => AccessDecision::Allow,
            Self::Deny(deny) | Self::Unavailable(deny) => AccessDecision::Deny(deny),
        }
    }
}

impl Decision for CachedDecision {
    fn ttl(&self) -> Duration {
        match self {
            Self::Allow => DECISION_TTL,
            Self::Deny(_) | Self::Unavailable(_) => REFUSAL_TTL,
        }
    }
}

/// What the backend confirmed for a credential, and the two deadlines that
/// govern reusing it.
#[derive(Clone, Debug)]
struct ConfirmedPrincipal {
    principal: Principal,
    /// Answered without asking the backend again until this instant.
    serve_until: Instant,
    /// Answered while the backend cannot be reached until this instant. It
    /// never moves forward while a credential keeps being answered, so neither
    /// an outage nor a run of fresh answers can push it out.
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

impl Decision for ConfirmedPrincipal {
    fn ttl(&self) -> Duration {
        self.reusable_until
            .saturating_duration_since(Instant::now())
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
    /// What the node answers with, keyed on the credential and what the request
    /// names. Everything else below is what it takes to fill this in.
    decisions: Cache<String, CachedDecision>,
    /// Keyed on the credential alone. What a principal may do is a question
    /// asked per request, so one confirmed principal settles every target and
    /// action its own grants cover.
    principals: Cache<String, ConfirmedPrincipal>,
    /// One lock per credential, so exactly one request asks the backend about
    /// it. moka coalesces a decision miss but not a principal that has to be
    /// refreshed behind one.
    consultations: Cache<String, Arc<Mutex<()>>>,
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
            decisions: decision_cache(
                config
                    .cache_max_entries
                    .saturating_mul(DECISIONS_PER_CREDENTIAL),
            ),
            principals: decision_cache(config.cache_max_entries),
            consultations: Cache::builder()
                .max_capacity(config.cache_max_entries as u64)
                .eviction_policy(EvictionPolicy::lru())
                .time_to_idle(UNAVAILABLE_BACKOFF * 20)
                .build(),
            metrics,
        })
    }

    pub async fn evaluate_access(&self, ctx: &RequestContext) -> AccessDecision {
        // Resolved once, then read by the key, the principal check, and the
        // policy alike. Resolving it separately in each is how the key and the
        // policy came to disagree about which project a request named.
        let request = match policy::resolve_request(ctx) {
            Ok(request) => request,
            Err(deny) => return AccessDecision::Deny(deny),
        };
        let credential = credentials(ctx);
        let key = decision_key(&credential, &request);

        let entry = self
            .decisions
            .entry(key)
            .or_insert_with(async {
                let start = Instant::now();
                let decision = self.decide(ctx, &request, &credential).await;
                self.metrics
                    .record_auth_decision("decide", decision.label(), start.elapsed());
                self.metrics.record_auth_cache("decide", "miss");
                decision
            })
            .await;

        // A caller that waited on someone else's evaluation counts as a hit:
        // what the label distinguishes is whether this request cost one.
        if !entry.is_fresh() {
            self.metrics.record_auth_cache("decide", "hit");
        }
        entry.into_value().into_access()
    }

    pub async fn clear_caches(&self) -> usize {
        // Approximate, and only used to decide whether anything was worth
        // reporting; the caches are performance state, not correctness state.
        let held = self.decisions.entry_count() + self.principals.entry_count();
        self.decisions.invalidate_all();
        self.principals.invalidate_all();
        self.consultations.invalidate_all();
        held as usize
    }

    /// Works out what to answer, from the principal the node already holds when
    /// that settles it and from the backend when it does not.
    async fn decide(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
        credential: &str,
    ) -> CachedDecision {
        let credential_key = fingerprint(&credential);
        let held = self.principals.get(&credential_key).await;

        if let Some(confirmed) = &held
            && !confirmed.needs_revalidation(Instant::now())
            && self.allows(request, &confirmed.principal)
        {
            self.metrics.record_auth_cache("authenticate", "hit");
            return CachedDecision::Allow;
        }

        self.consult_backend(ctx, request, credential_key, held)
            .await
    }

    /// Whether a principal settles this request on its own. A principal is
    /// about the credential, not about one target, so the one confirmed for a
    /// read of a project also settles the write the build issues next. One that
    /// does not cover the request settles nothing: the backend may still allow
    /// it through a route the principal's own grants know nothing about.
    fn allows(&self, request: &policy::ResolvedRequest, principal: &Principal) -> bool {
        matches!(
            policy::authorize(request, Some(principal)),
            Authorization::Allow
        )
    }

    /// Asks the backend, with exactly one request per credential doing the
    /// asking.
    ///
    /// A request that cannot take the lock does not queue behind the probe when
    /// it has an answer of its own: a probe against a control plane that black
    /// holes runs for as long as the timeouts allow, and parking every request
    /// for that long to learn something the node is already holding helps
    /// nobody. It answers from what it holds and writes nothing, so no deadline
    /// moves on the strength of a probe that has not come back.
    async fn consult_backend(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
        credential_key: String,
        held: Option<ConfirmedPrincipal>,
    ) -> CachedDecision {
        let lock = self
            .consultations
            .get_with(credential_key.clone(), async { Arc::new(Mutex::new(())) })
            .await;

        let _guard = match lock.try_lock() {
            Ok(guard) => guard,
            Err(_) => {
                if self.reusable(request, &held).is_some() {
                    self.metrics.record_auth_cache("authenticate", "stale");
                    return CachedDecision::Allow;
                }
                lock.lock().await
            }
        };

        // Whoever held the lock may have confirmed a principal that settles
        // this request already.
        if let Some(confirmed) = self.principals.get(&credential_key).await
            && !confirmed.needs_revalidation(Instant::now())
            && self.allows(request, &confirmed.principal)
        {
            self.metrics.record_auth_cache("authenticate", "hit");
            return CachedDecision::Allow;
        }

        self.metrics.record_auth_cache(
            "authenticate",
            if held.is_some() { "revalidate" } else { "miss" },
        );

        match self.evaluate_policy(ctx, request).await {
            Authentication::Principal(principal) => {
                let confirmed = self.confirm(&principal, ctx, request, held.as_ref());
                // A credential already past its own expiry is answered this
                // once, because the backend just vouched for it, but holding it
                // would only hand back something dead on the next request.
                if !confirmed.ttl().is_zero() {
                    self.principals.insert(credential_key, confirmed).await;
                }
                match policy::authorize(request, Some(&principal)) {
                    Authorization::Allow => CachedDecision::Allow,
                    Authorization::Deny(deny) => CachedDecision::Deny(deny),
                }
            }
            Authentication::Deny(deny) => {
                // A 403 is about this target and leaves the principal alone. A
                // 401 says the credential itself is finished, so holding on to
                // a principal for it would keep answering every other target
                // that principal covers.
                if deny.status == 401 {
                    self.principals.invalidate(&credential_key).await;
                }
                CachedDecision::Deny(deny)
            }
            Authentication::Unavailable(deny) => {
                match held.as_ref().and_then(|held| held.held_off(Instant::now())) {
                    Some(reusable) if self.allows(request, &reusable.principal) => {
                        self.principals.insert(credential_key, reusable).await;
                        self.metrics.record_auth_cache("authenticate", "stale");
                        CachedDecision::Allow
                    }
                    // Nothing held settles this request, so the node does not
                    // know.
                    _ => CachedDecision::Unavailable(deny),
                }
            }
        }
    }

    /// The principal a request may be answered from while the backend is out of
    /// reach: still inside its reuse deadline, and covering what is being asked.
    fn reusable(
        &self,
        request: &policy::ResolvedRequest,
        held: &Option<ConfirmedPrincipal>,
    ) -> Option<Principal> {
        let held = held.as_ref()?;
        if Instant::now() >= held.reusable_until || !self.allows(request, &held.principal) {
            return None;
        }
        Some(held.principal.clone())
    }

    /// Takes the consultation lock for this credential and keeps it, standing
    /// in for a probe that is in flight. Holding a real one would mean holding
    /// a real backend call open.
    #[cfg(test)]
    pub(crate) async fn hold_consultation(
        &self,
        ctx: &RequestContext,
    ) -> tokio::sync::OwnedMutexGuard<()> {
        self.consultations
            .get_with(fingerprint(&credentials(ctx)), async {
                Arc::new(Mutex::new(()))
            })
            .await
            .lock_owned()
            .await
    }

    /// Drops the decisions the node has already worked out, so the next request
    /// works its own out. They stand for seconds by design, which is still
    /// longer than a test should wait.
    #[cfg(test)]
    pub(crate) async fn expire_decisions(&self) {
        self.decisions.invalidate_all();
    }

    /// Ages the confirmed principal for this credential so the next request has
    /// to go back to the backend, and drops the decisions it settled. The
    /// deadlines are minutes long by design, which is longer than a test can
    /// wait.
    #[cfg(test)]
    pub(crate) async fn expire_serving_deadline(&self, ctx: &RequestContext) {
        let key = fingerprint(&credentials(ctx));

        if let Some(confirmed) = self.principals.get(&key).await {
            let now = Instant::now();
            self.principals
                .insert(
                    key,
                    ConfirmedPrincipal {
                        serve_until: now.checked_sub(Duration::from_secs(1)).unwrap_or(now),
                        ..confirmed
                    },
                )
                .await;
        }
        self.decisions.invalidate_all();
    }

    async fn evaluate_policy(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
    ) -> Authentication {
        let start = Instant::now();
        let result = policy::authenticate(&self.backend, ctx, request).await;
        self.metrics
            .record_auth_decision("authenticate", result_label(&result), start.elapsed());
        result
    }

    fn confirm(
        &self,
        principal: &Principal,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
        held: Option<&ConfirmedPrincipal>,
    ) -> ConfirmedPrincipal {
        let now = Instant::now();
        let principal = match held {
            Some(held) => policy::merge_principals(&held.principal, principal, request),
            None => principal.clone(),
        };

        let ceiling = match policy::credential_expiry(ctx) {
            Some(remaining) => now + remaining.min(CONFIRMED_TTL),
            None => now + CONFIRMED_TTL,
        };
        // The reuse deadline never moves forward while a credential keeps being
        // answered, so folding in what each answer settles cannot keep a grant
        // alive indefinitely. A credential in continuous use is resolved from
        // scratch once the first answer that started it runs out, which is what
        // bounds how long it can carry one the server has since taken away.
        let reusable_until = held.map_or(ceiling, |held| ceiling.min(held.reusable_until));

        ConfirmedPrincipal {
            principal,
            // Every credential is revalidated on the same schedule, so
            // revocation lands within one window whatever the credential is.
            // Expiry bounds reuse, not revalidation: a token can be withdrawn
            // long before it runs out, and a refresh token presented as a
            // bearer introspects as active while being exactly the kind the
            // server can revoke.
            serve_until: (now + REVALIDATE_AFTER).min(reusable_until),
            reusable_until,
        }
    }
}

fn result_label(result: &Authentication) -> &'static str {
    match result {
        Authentication::Principal(_) => "principal",
        Authentication::Deny(_) => "deny",
        Authentication::Unavailable(_) => "unavailable",
    }
}

/// The credential plus what the request resolved to.
///
/// Resolved rather than raw: `request_target` also reads the target out of the
/// `account_handle` and `project_handle` query parameters, and the fields on
/// the context are only ever filled from the path. Keyed on those fields, a
/// request naming its project in the query looked identical to one naming a
/// different project the same way.
///
/// The scope travels with the identifier because an account target and a
/// project target read different grant buckets.
fn decision_key(credential: &str, request: &policy::ResolvedRequest) -> String {
    fingerprint(&(
        credential,
        request.target.scope.key(),
        &request.target.identifier,
        request.action.key(),
    ))
}

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

    fn deny(message: &str) -> CachedDecision {
        CachedDecision::Deny(DenyDecision {
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

    fn resolved(ctx: &RequestContext) -> policy::ResolvedRequest {
        policy::resolve_request(ctx).expect("a resolvable request")
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
        let held = confirmed(Duration::from_secs(60), Duration::from_secs(600));

        assert!(!held.needs_revalidation(Instant::now()));
    }

    // Past it the entry cannot answer alone: the backend has to be asked before
    // this credential is served again.
    #[test]
    fn a_confirmed_principal_stops_answering_past_its_serving_deadline() {
        let mut held = confirmed(Duration::from_secs(60), Duration::from_secs(600));
        held.serve_until = Instant::now() - Duration::from_secs(1);

        assert!(held.needs_revalidation(Instant::now()));
    }

    // A principal is about the credential, not about one target, so the one
    // confirmed for a read of a project answers the write that follows it.
    // Without this a build's first upload during an outage is refused while a
    // perfectly good principal sits under the read it just did.
    #[test]
    fn a_principal_answers_every_target_and_action_its_grants_cover() {
        let engine = engine();
        let granted = Principal {
            id: "a".into(),
            kind: "account".into(),
            attributes: serde_json::json!({
                "cache_grants": { "project": { "write": ["acme/ios"] } }
            }),
        };

        let mut read = ctx_with_token("token");
        read.namespace_id = Some("ios".into());
        let mut write = read.clone();
        write.method = "PUT".into();
        write.operation = "artifact.write".into();
        let mut other_project = read.clone();
        other_project.namespace_id = Some("android".into());

        assert!(engine.allows(&resolved(&read), &granted));
        assert!(engine.allows(&resolved(&write), &granted));
        assert!(!engine.allows(&resolved(&other_project), &granted));
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
    fn a_credential_carrying_an_expiry_is_held_no_longer_than_that_expiry() {
        let engine = engine();
        let mut ctx = ctx_with_token(&token_expiring_in(120));
        ctx.tenant_id = Some("acme".into());

        let held = engine.confirm(&principal("a"), &ctx, &resolved(&ctx), None);

        assert_eq!(held.serve_until, held.reusable_until);
        assert!(held.reusable_until <= Instant::now() + Duration::from_secs(120));
        assert!(held.reusable_until > Instant::now() + Duration::from_secs(110));
    }

    // Carrying an expiry is not a reason to skip revalidation. Expiry says when
    // a credential runs out, not whether it has been withdrawn, and a token the
    // server can revoke reaches this branch.
    #[test]
    fn a_credential_carrying_a_long_expiry_is_still_revalidated() {
        let engine = engine();
        let ctx = ctx_with_token(&token_expiring_in(60 * 60));

        let held = engine.confirm(&principal("a"), &ctx, &resolved(&ctx), None);

        assert!(held.serve_until < held.reusable_until);
        assert!(held.serve_until <= Instant::now() + REVALIDATE_AFTER);
    }

    // A credential that carries no expiry gets the cache's own deadlines: a
    // serving window, and a longer window it may be reused within.
    #[test]
    fn a_credential_carrying_no_expiry_gets_the_caches_own_deadlines() {
        let engine = engine();
        let ctx = ctx_with_token("opaque-token");

        let held = engine.confirm(&principal("a"), &ctx, &resolved(&ctx), None);

        assert!(held.serve_until < held.reusable_until);
        assert!(held.reusable_until > Instant::now() + REVALIDATE_AFTER);
    }

    // Folding one answer into the next is what stops a token reaching two
    // projects from paying a call every time it changes which one it asks
    // about. It must not also stop the credential from ever being resolved
    // from scratch, or a grant the server has taken away would live as long as
    // the build does.
    #[test]
    fn folding_in_a_new_answer_never_pushes_the_reuse_deadline_out() {
        let engine = engine();
        let ctx = ctx_with_token("opaque-token");

        let first = engine.confirm(&principal("a"), &ctx, &resolved(&ctx), None);
        let second = engine.confirm(&principal("b"), &ctx, &resolved(&ctx), Some(&first));

        assert!(second.reusable_until <= first.reusable_until);
        assert!(second.serve_until > Instant::now());
    }

    // An expiry further out than the cache's own bound does not extend it.
    #[test]
    fn a_far_future_expiry_is_capped_at_the_reuse_bound() {
        let engine = engine();
        let ctx = ctx_with_token(&token_expiring_in(60 * 60 * 24 * 28));

        let held = engine.confirm(&principal("a"), &ctx, &resolved(&ctx), None);

        assert!(held.reusable_until <= Instant::now() + CONFIRMED_TTL);
    }

    // A refusal about one project says nothing about another, so the two must
    // not share a denial entry.
    #[test]
    fn a_denial_is_held_against_one_project_only() {
        let mut first = ctx_with_token("token");
        first.tenant_id = Some("acme".into());
        first.namespace_id = Some("ios".into());

        let mut second = first.clone();
        second.namespace_id = Some("android".into());

        assert_ne!(
            decision_key("token", &resolved(&first)),
            decision_key("token", &resolved(&second))
        );
    }

    // A refusal to write is not a refusal to read, for the same reason.
    #[test]
    fn a_denial_is_held_against_one_action_only() {
        let mut read = ctx_with_token("token");
        read.tenant_id = Some("acme".into());
        read.namespace_id = Some("ios".into());

        let mut write = read.clone();
        write.method = "PUT".into();
        write.operation = "artifact.write".into();

        assert_ne!(
            decision_key("token", &resolved(&read)),
            decision_key("token", &resolved(&write))
        );
    }

    // A refusal stands for less time than an allow, so a caller who has just
    // been granted access is not locked out by their own rejection.
    #[test]
    fn a_decision_carries_its_own_lifetime_into_the_cache() {
        let expiry = DecisionExpiry;
        let created = Instant::now();
        let refusal = CachedDecision::Deny(DenyDecision {
            status: 403,
            message: "no".into(),
        });

        assert_eq!(
            Expiry::<String, CachedDecision>::expire_after_create(
                &expiry,
                &"k".to_string(),
                &CachedDecision::Allow,
                created
            ),
            Some(DECISION_TTL)
        );
        assert_eq!(
            Expiry::<String, CachedDecision>::expire_after_create(
                &expiry,
                &"k".to_string(),
                &refusal,
                created
            ),
            Some(REFUSAL_TTL)
        );
        assert!(REFUSAL_TTL < DECISION_TTL);
    }

    // Replacing an entry has to reset its lifetime. moka's default keeps the
    // one the replaced entry was created with, which would pin a revalidated
    // principal to the deadline of the principal it replaced.
    #[test]
    fn replacing_a_decision_resets_its_lifetime() {
        let expiry = DecisionExpiry;

        assert_eq!(
            Expiry::<String, CachedDecision>::expire_after_update(
                &expiry,
                &"k".to_string(),
                &CachedDecision::Allow,
                Instant::now(),
                Some(Duration::from_secs(1)),
            ),
            Some(DECISION_TTL)
        );
    }

    // moka documents that it recovers when the caller running `init` panics,
    // but says nothing about that caller being cancelled. These evaluations are
    // request-scoped, so a client that disconnects mid-request drops the one
    // everyone else is waiting on. Pinned here because the crate does not
    // promise it and an upgrade could take it away.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_cancelled_evaluation_does_not_strand_the_next_caller() {
        let cache: Cache<String, CachedDecision> = decision_cache(16);
        let entered = Arc::new(AtomicUsize::new(0));

        let abandoned_cache = cache.clone();
        let abandoned_entered = entered.clone();
        let abandoned = tokio::spawn(async move {
            abandoned_cache
                .get_with("k".to_string(), async move {
                    abandoned_entered.fetch_add(1, Ordering::SeqCst);
                    std::future::pending::<()>().await;
                    CachedDecision::Allow
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
