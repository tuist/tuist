//! Caching and coalescing around the policy.
//!
//! The policy is cheap when the token answers for itself and expensive when
//! Tuist's server has to be asked, so what the server (or the token) settles is
//! held per credential and target as one access level, and concurrent requests
//! for a level that is not held collapse into one consultation.

use std::sync::Arc;
use std::time::{Duration, Instant};

use moka::Expiry;
use moka::policy::EvictionPolicy;
use moka::{future::Cache as AsyncCache, sync::Cache};
use sha2::{Digest, Sha256};
use tokio::sync::Mutex;
use tracing::{Instrument, field};

use super::config::AuthConfig;
use super::policy::{self, Authentication};
use super::tuist::TuistBackend;
use crate::auth::{Access, AccessDecision, DenyDecision, RequestContext};
use crate::{
    metrics::Metrics,
    telemetry::{record_trace_context, trace_export_active},
};

pub type SharedAuth = Arc<AuthEngine>;

/// How long an evaluation is authoritative for what it refused. It bounds a
/// `Refused` or `Invalid` entry, and it is how long a level refuses an action
/// above it before the server is asked whether some other route allows it. Kept
/// short so a permission just granted is not locked out by the answer that
/// preceded it, and a server that has come back is asked again promptly.
const REFUSAL_TTL: Duration = Duration::from_secs(3);

/// How long a level is served before the backend is asked about it again, the
/// same for every credential: this is how long a revocation, a deactivated
/// user, or a narrowed grant can go unnoticed, and expiry says when a
/// credential runs out, not whether it was withdrawn.
const REVALIDATE_AFTER: Duration = Duration::from_secs(10 * 60);

/// How long an entry lives at all — the reuse ceiling. Past `REVALIDATE_AFTER`
/// it answers only while the backend cannot be reached, and past this it is
/// gone, so an outage cannot keep a credential alive for as long as the outage
/// lasts. Every write comes from a fresh authoritative answer, so the ceiling
/// restarts with each one; what an outage can never do is restart it, because
/// nothing is written while the backend is out of reach.
const CONFIRMED_TTL: Duration = Duration::from_secs(25 * 60);

/// How long a backend that did not answer is left alone before the next
/// request tries it again, per credential. Without it every cold target of
/// every credential dials a control plane that is already down, serially, each
/// paying the full timeout.
const UNAVAILABLE_BACKOFF: Duration = Duration::from_secs(3);

const _: () = assert!(REFUSAL_TTL.as_secs() <= REVALIDATE_AFTER.as_secs());
const _: () = assert!(REVALIDATE_AFTER.as_secs() < CONFIRMED_TTL.as_secs());

/// What one evaluation settled for one credential and target, and the two
/// windows that govern reusing it. The entry's own cache lifetime is the third
/// deadline: the reuse ceiling, past which it is simply absent.
#[derive(Clone, Debug)]
struct AccessEntry {
    access: Access,
    /// When the answer was worked out, compared against the revocation marker:
    /// an entry evaluated before the credential was reported invalid is void.
    evaluated_at: Instant,
    /// Served without asking the backend again until this instant. Past it the
    /// entry answers only while the backend cannot be reached.
    serve_until: Instant,
    /// The refusals this evaluation implies are replayed until this instant —
    /// a level asked for an action above it refuses without a round trip.
    settled_until: Instant,
    /// How long the entry lives in the cache, handed to the expiry below.
    lifetime: Duration,
}

impl AccessEntry {
    fn serves(&self, now: Instant) -> bool {
        now < self.serve_until
    }

    fn settles_refusals(&self, now: Instant) -> bool {
        now < self.settled_until
    }
}

struct EntryExpiry;

impl<K> Expiry<K, AccessEntry> for EntryExpiry {
    fn expire_after_create(
        &self,
        _key: &K,
        value: &AccessEntry,
        _created_at: Instant,
    ) -> Option<Duration> {
        Some(value.lifetime)
    }

    // moka's default keeps the deadline the entry was created with, which would
    // pin a revalidated answer to the lifetime of the one it replaced.
    fn expire_after_update(
        &self,
        _key: &K,
        value: &AccessEntry,
        _updated_at: Instant,
        _duration_until_expiry: Option<Duration>,
    ) -> Option<Duration> {
        Some(value.lifetime)
    }
}

#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
struct CredentialKey([u8; 32]);

#[derive(Clone, Debug, Hash, PartialEq, Eq)]
struct EntryKey {
    credential: CredentialKey,
    scope: crate::auth::target::Scope,
    identifier: String,
}

/// What the engine answers a request with. Uncached — the entry above is the
/// cached thing, and an answer is worked out from it per request.
enum Outcome {
    Allow,
    Refuse(DenyDecision),
    Unavailable(DenyDecision),
}

impl Outcome {
    fn label(&self) -> &'static str {
        match self {
            Self::Allow => "allow",
            Self::Refuse(_) => "deny",
            Self::Unavailable(_) => "unavailable",
        }
    }

    fn into_access(self) -> AccessDecision {
        match self {
            Self::Allow => AccessDecision::Allow,
            Self::Refuse(deny) | Self::Unavailable(deny) => AccessDecision::Deny(deny),
        }
    }
}

/// What the entry alone answers, or `None` when the backend has to be asked:
/// nothing held, a level past its serving deadline, or an action above a level
/// whose refusal window has passed — the server may allow it through a route
/// the level knows nothing about, so it is asked rather than refused.
fn settle(
    entry: Option<&AccessEntry>,
    required: Access,
    request: &policy::ResolvedRequest,
    now: Instant,
) -> Option<Outcome> {
    let entry = entry?;
    match entry.access {
        Access::Invalid => Some(Outcome::Refuse(policy::invalid_credential())),
        Access::Refused => Some(Outcome::Refuse(policy::refusal(request))),
        Access::PaymentRequired => Some(Outcome::Refuse(policy::payment_required(request))),
        level if level >= required => entry.serves(now).then_some(Outcome::Allow),
        _ => entry
            .settles_refusals(now)
            .then_some(Outcome::Refuse(policy::refusal(request))),
    }
}

/// The answer a fresh evaluation gives the request that paid for it.
fn respond(access: Access, required: Access, request: &policy::ResolvedRequest) -> Outcome {
    if access == Access::Invalid {
        return Outcome::Refuse(policy::invalid_credential());
    }
    if access == Access::PaymentRequired {
        return Outcome::Refuse(policy::payment_required(request));
    }
    if access >= required {
        Outcome::Allow
    } else {
        Outcome::Refuse(policy::refusal(request))
    }
}

/// How long an entry may live: a refusal for its short replay window, a level
/// until the credential's own expiry or the ceiling, whichever comes first.
fn entry_lifetime(access: Access, expiry: Option<Duration>) -> Duration {
    match access {
        Access::Invalid | Access::Refused | Access::PaymentRequired => REFUSAL_TTL,
        _ => expiry.map_or(CONFIRMED_TTL, |left| left.min(CONFIRMED_TTL)),
    }
}

fn unreachable_deny() -> DenyDecision {
    DenyDecision {
        status: 503,
        message: "Authentication backend unavailable".into(),
    }
}

pub struct AuthEngine {
    backend: TuistBackend,
    /// One entry per credential and target: the access level the last
    /// evaluation settled. Everything else below is what it takes to fill this
    /// in and to void it.
    entries: Cache<EntryKey, AccessEntry>,
    /// One lock per entry key, so exactly one request asks the backend a given
    /// question at a time.
    consultations: AsyncCache<EntryKey, Arc<Mutex<()>>>,
    /// When a credential was last reported invalid. A 401 is about the
    /// credential, not one target, and there is no way to enumerate a
    /// credential's entries — so they are voided by comparison instead: an
    /// entry evaluated before the marker is dead. The marker lives as long as
    /// the longest entry can, so nothing written before it can outlive it.
    revocations: Cache<CredentialKey, Instant>,
    /// Credentials whose last consultation could not reach the backend.
    /// Presence holds the next attempt off, so an outage costs one probe per
    /// credential per backoff window rather than one per cold target.
    unreachable: Cache<CredentialKey, ()>,
    metrics: Metrics,
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
            entries: Cache::builder()
                .max_capacity(config.cache_max_entries as u64)
                // moka defaults to TinyLFU, whose admission filter can reject a
                // new entry outright when the cache is full. A credential seen
                // once or twice is exactly what that filter rejects, and every
                // new build starts as one, so it would re-ask the backend on
                // every request under load.
                .eviction_policy(EvictionPolicy::lru())
                .expire_after(EntryExpiry)
                .build(),
            consultations: AsyncCache::builder()
                .max_capacity(config.cache_max_entries as u64)
                .eviction_policy(EvictionPolicy::lru())
                .time_to_idle(UNAVAILABLE_BACKOFF * 20)
                .build(),
            revocations: Cache::builder()
                .max_capacity(config.cache_max_entries as u64)
                .eviction_policy(EvictionPolicy::lru())
                // The marker has to outlive every entry written before it, and
                // no entry lives past the reuse ceiling.
                .time_to_live(CONFIRMED_TTL)
                .build(),
            unreachable: Cache::builder()
                .max_capacity(config.cache_max_entries as u64)
                .eviction_policy(EvictionPolicy::lru())
                .time_to_live(UNAVAILABLE_BACKOFF)
                .build(),
            metrics,
        })
    }

    pub async fn evaluate_access(&self, ctx: &RequestContext) -> AccessDecision {
        // Resolved once, then read by the key, the entry check, and the policy
        // alike. Resolving it separately in each is how the key and the policy
        // came to disagree about which project a request named.
        let request = match policy::resolve_request(ctx) {
            Ok(request) => request,
            Err(deny) => return AccessDecision::Deny(deny),
        };
        let required = Access::required(&request.action);
        let credential_key = fingerprint(policy::authorization_header(ctx).unwrap_or_default());
        let entry_key = entry_key(&credential_key, &request.target);

        let start = Instant::now();
        let outcome = self
            .answer(ctx, &request, required, credential_key, entry_key)
            .await;
        self.metrics
            .record_auth_decision("decide", outcome.label(), start.elapsed());
        outcome.into_access()
    }

    async fn answer(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
        required: Access,
        credential_key: CredentialKey,
        entry_key: EntryKey,
    ) -> Outcome {
        let held = self.valid_entry(&entry_key, &credential_key);
        if let Some(outcome) = settle(held.as_ref(), required, request, Instant::now()) {
            self.metrics.record_auth_cache("access", "hit");
            return outcome;
        }

        self.consult(ctx, request, required, credential_key, entry_key, held)
            .await
    }

    /// Asks the backend, with exactly one request per credential and target
    /// doing the asking.
    async fn consult(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
        required: Access,
        credential_key: CredentialKey,
        entry_key: EntryKey,
        held: Option<AccessEntry>,
    ) -> Outcome {
        // A backend that just failed to answer is left alone for a moment,
        // whoever is asking about whatever target.
        if self.unreachable.get(&credential_key).is_some() {
            return self.without_backend(required, held.as_ref());
        }

        let lock = self
            .consultations
            .get_with(entry_key.clone(), async { Arc::new(Mutex::new(())) })
            .await;

        let _guard = match lock.try_lock() {
            Ok(guard) => guard,
            Err(_) => {
                // The probe in flight is asking this exact question. A level
                // that still answers it is served rather than parked behind
                // the probe: against a backend that black-holes, that probe
                // runs for as long as the timeouts allow. The answer writes
                // nothing, so it cannot outlive what the probe comes back
                // with by more than this one request.
                if held.as_ref().is_some_and(|entry| entry.access >= required) {
                    self.metrics.record_auth_cache("access", "stale");
                    return Outcome::Allow;
                }
                lock.lock().await
            }
        };

        // Whoever held the lock before us may have just written the answer.
        let held = self.valid_entry(&entry_key, &credential_key);
        if let Some(outcome) = settle(held.as_ref(), required, request, Instant::now()) {
            self.metrics.record_auth_cache("access", "hit");
            return outcome;
        }

        self.metrics
            .record_auth_cache("access", if held.is_some() { "revalidate" } else { "miss" });

        match self.evaluate_policy(ctx, request).await {
            Authentication::Access(access) => {
                if access == Access::Invalid {
                    // The credential itself is finished, so every entry it has
                    // is finished with it, not only this target's. The marker
                    // is written first, so the entry stored below survives its
                    // own revocation check.
                    self.revocations.insert(credential_key, Instant::now());
                }
                self.remember(entry_key, access, ctx);
                respond(access, required, request)
            }
            // Cheap to re-derive — no round trip reached the backend — so
            // caching it buys nothing.
            Authentication::Deny(deny) => Outcome::Refuse(deny),
            Authentication::Unavailable(_) => {
                self.unreachable.insert(credential_key, ());
                self.without_backend(required, held.as_ref())
            }
        }
    }

    /// The answer when the backend cannot be reached: a level that covers the
    /// request keeps serving it until its entry runs out, and a node holding
    /// nothing that covers it fails closed.
    fn without_backend(&self, required: Access, held: Option<&AccessEntry>) -> Outcome {
        if held.is_some_and(|entry| entry.access >= required) {
            self.metrics.record_auth_cache("access", "stale");
            return Outcome::Allow;
        }
        Outcome::Unavailable(unreachable_deny())
    }

    fn remember(&self, entry_key: EntryKey, access: Access, ctx: &RequestContext) {
        let lifetime = entry_lifetime(access, policy::credential_expiry(ctx));
        // A credential already past its own expiry is answered this once,
        // because the backend just vouched for it, but holding it would only
        // hand back something dead on the next request.
        if lifetime.is_zero() {
            return;
        }

        let now = Instant::now();
        self.entries.insert(
            entry_key,
            AccessEntry {
                access,
                evaluated_at: now,
                serve_until: now + REVALIDATE_AFTER,
                settled_until: now + REFUSAL_TTL,
                lifetime,
            },
        );
    }

    /// The entry for this key, unless the credential has been reported invalid
    /// since it was written.
    fn valid_entry(
        &self,
        entry_key: &EntryKey,
        credential_key: &CredentialKey,
    ) -> Option<AccessEntry> {
        let entry = self.entries.get(entry_key)?;
        if let Some(revoked_at) = self.revocations.get(credential_key)
            && entry.evaluated_at < revoked_at
        {
            return None;
        }
        Some(entry)
    }

    async fn evaluate_policy(
        &self,
        ctx: &RequestContext,
        request: &policy::ResolvedRequest,
    ) -> Authentication {
        let start = Instant::now();
        let authenticate_span = if trace_export_active() {
            let span = tracing::info_span!(
                "kura.auth.authenticate",
                kura.auth.cache = "miss",
                kura.auth.result = field::Empty,
                trace_id = field::Empty,
                span_id = field::Empty,
            );
            record_trace_context(&span);
            span
        } else {
            tracing::Span::none()
        };
        let result = policy::authenticate(&self.backend, ctx, request)
            .instrument(authenticate_span.clone())
            .await;
        authenticate_span.record("kura.auth.result", result_label(&result));
        self.metrics
            .record_auth_decision("authenticate", result_label(&result), start.elapsed());
        result
    }

    pub async fn clear_caches(&self) -> usize {
        // Approximate, and only used to decide whether anything was worth
        // reporting; the caches are performance state, not correctness state.
        let held = self.entries.entry_count();
        self.entries.invalidate_all();
        self.consultations.invalidate_all();
        self.revocations.invalidate_all();
        self.unreachable.invalidate_all();
        held as usize
    }

    /// Takes the consultation lock for this request's question and keeps it,
    /// standing in for a probe that is in flight. Holding a real one would
    /// mean holding a real backend call open.
    #[cfg(test)]
    pub(crate) async fn hold_consultation(
        &self,
        ctx: &RequestContext,
    ) -> tokio::sync::OwnedMutexGuard<()> {
        let request = policy::resolve_request(ctx).expect("a resolvable request");
        let credential_key = fingerprint(policy::authorization_header(ctx).unwrap_or_default());
        self.consultations
            .get_with(entry_key(&credential_key, &request.target), async {
                Arc::new(Mutex::new(()))
            })
            .await
            .lock_owned()
            .await
    }

    /// Lifts the backoff left by a failed probe so the next request dials the
    /// backend again, standing in for the seconds a test cannot wait.
    #[cfg(test)]
    pub(crate) async fn clear_unavailable_backoff(&self, ctx: &RequestContext) {
        self.unreachable.invalidate(&fingerprint(
            policy::authorization_header(ctx).unwrap_or_default(),
        ));
    }

    /// Ages the entry for this request's target so the next request has to go
    /// back to the backend. The windows are minutes long by design, which is
    /// longer than a test can wait.
    #[cfg(test)]
    pub(crate) async fn expire_serving_deadline(&self, ctx: &RequestContext) {
        let request = policy::resolve_request(ctx).expect("a resolvable request");
        let credential_key = fingerprint(policy::authorization_header(ctx).unwrap_or_default());
        let key = entry_key(&credential_key, &request.target);

        if let Some(entry) = self.entries.get(&key) {
            let now = Instant::now();
            let just_passed = now.checked_sub(Duration::from_secs(1)).unwrap_or(now);
            self.entries.insert(
                key,
                AccessEntry {
                    serve_until: just_passed,
                    settled_until: just_passed,
                    ..entry
                },
            );
        }
    }
}

fn result_label(result: &Authentication) -> &'static str {
    match result {
        Authentication::Access(_) => "access",
        Authentication::Deny(_) => "deny",
        Authentication::Unavailable(_) => "unavailable",
    }
}

/// The credential plus what the request resolved to — and deliberately not the
/// action: the level answers both actions, so a write asks the same question as
/// the read before it.
///
/// Resolved rather than raw: `request_target` also reads the target out of the
/// `account_handle` and `project_handle` query parameters, and the fields on
/// the context are only ever filled from the path. Keyed on those fields, a
/// request naming its project in the query looked identical to one naming a
/// different project the same way.
///
/// Injective by construction: the fingerprint is fixed-width and the scope is
/// from a closed set, so the identifier can carry anything.
fn entry_key(
    credential_key: &CredentialKey,
    target: &crate::auth::target::RequestTarget,
) -> EntryKey {
    EntryKey {
        credential: *credential_key,
        scope: target.scope,
        identifier: target.identifier.clone(),
    }
}

fn fingerprint(value: &str) -> CredentialKey {
    CredentialKey(Sha256::digest(value.as_bytes()).into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::target::{Action, RequestTarget, Scope};

    async fn measure_cache_lookup(
        legacy: bool,
        legacy_entries: AsyncCache<String, AccessEntry>,
        legacy_revocations: AsyncCache<String, Instant>,
        entries: Cache<EntryKey, AccessEntry>,
        revocations: Cache<CredentialKey, Instant>,
        authorization: Arc<str>,
        target: Arc<RequestTarget>,
    ) -> f64 {
        const WORKERS: usize = 8;
        const ITERATIONS_PER_WORKER: usize = 100_000;

        let barrier = Arc::new(tokio::sync::Barrier::new(WORKERS + 1));
        let mut workers = tokio::task::JoinSet::new();
        for _ in 0..WORKERS {
            let legacy_entries = legacy_entries.clone();
            let legacy_revocations = legacy_revocations.clone();
            let entries = entries.clone();
            let revocations = revocations.clone();
            let authorization = authorization.clone();
            let target = target.clone();
            let barrier = barrier.clone();
            workers.spawn(async move {
                barrier.wait().await;
                for _ in 0..ITERATIONS_PER_WORKER {
                    if legacy {
                        let credential = authorization.to_string();
                        let encoded =
                            serde_json::to_vec(&credential).expect("serialize credential");
                        let credential_key = format!("{:x}", Sha256::digest(&encoded));
                        let entry_key = format!(
                            "{credential_key}:{}:{}",
                            target.scope.key(),
                            target.identifier
                        );
                        let entry = legacy_entries.get(&entry_key).await;
                        let revoked = legacy_revocations.get(&credential_key).await;
                        std::hint::black_box((entry, revoked));
                    } else {
                        let credential_key = fingerprint(&authorization);
                        let entry_key = entry_key(&credential_key, &target);
                        let entry = entries.get(&entry_key);
                        let revoked = revocations.get(&credential_key);
                        std::hint::black_box((entry, revoked));
                    }
                }
            });
        }

        barrier.wait().await;
        let started_at = Instant::now();
        while let Some(result) = workers.join_next().await {
            result.expect("lookup worker");
        }
        (WORKERS * ITERATIONS_PER_WORKER) as f64 / started_at.elapsed().as_secs_f64()
    }

    fn request() -> policy::ResolvedRequest {
        policy::ResolvedRequest {
            target: RequestTarget {
                scope: Scope::Project,
                account: "acme".into(),
                namespace: Some("ios".into()),
                identifier: "acme/ios".into(),
            },
            action: Action::Read,
        }
    }

    fn entry(access: Access) -> AccessEntry {
        let now = Instant::now();
        AccessEntry {
            access,
            evaluated_at: now,
            serve_until: now + REVALIDATE_AFTER,
            settled_until: now + REFUSAL_TTL,
            lifetime: CONFIRMED_TTL,
        }
    }

    fn aged(mut entry: AccessEntry) -> AccessEntry {
        let just_passed = Instant::now()
            .checked_sub(Duration::from_secs(1))
            .unwrap_or_else(Instant::now);
        entry.serve_until = just_passed;
        entry.settled_until = just_passed;
        entry
    }

    #[test]
    fn a_level_answers_every_action_at_or_below_it_within_its_serving_window() {
        let held = entry(Access::ReadWrite);

        for required in [Access::Read, Access::ReadWrite] {
            assert!(matches!(
                settle(Some(&held), required, &request(), Instant::now()),
                Some(Outcome::Allow)
            ));
        }
    }

    #[test]
    fn a_level_past_its_serving_window_sends_the_request_back_to_the_backend() {
        let held = aged(entry(Access::ReadWrite));

        assert!(settle(Some(&held), Access::Read, &request(), Instant::now()).is_none());
    }

    // A fresh evaluation is authoritative for its refusals too: a write asked
    // of a read-only level is refused without a round trip, for the same short
    // window a refused entry stands.
    #[test]
    fn an_action_above_the_level_is_refused_only_inside_the_settled_window() {
        let held = entry(Access::Read);

        let Some(Outcome::Refuse(deny)) =
            settle(Some(&held), Access::ReadWrite, &request(), Instant::now())
        else {
            panic!("expected a refusal inside the settled window");
        };
        assert_eq!(deny.status, 403);

        // Past the window the server may allow the action through a route the
        // level knows nothing about, so the request goes back to it.
        let held = aged(held);
        assert!(settle(Some(&held), Access::ReadWrite, &request(), Instant::now()).is_none());
    }

    // A blocked account reaches the node as absence from the grants, which is
    // indistinguishable from never having had access. Answering 403 sends the
    // caller after a permissions problem they do not have.
    #[test]
    fn an_exhausted_plan_answers_with_its_own_status() {
        let Some(Outcome::Refuse(deny)) = settle(
            Some(&entry(Access::PaymentRequired)),
            Access::Read,
            &request(),
            Instant::now(),
        ) else {
            panic!("expected the plan refusal to replay");
        };
        assert_eq!(deny.status, 402);
        assert!(deny.message.contains("Tuist Pro"));

        // And on a fresh evaluation, not only a replayed one.
        let Outcome::Refuse(fresh) = respond(Access::PaymentRequired, Access::Read, &request())
        else {
            panic!("expected a fresh plan refusal");
        };
        assert_eq!(fresh.status, 402);
    }

    // It grants nothing, so a write must not slip through on the ordering that
    // places it above `Refused`.
    #[test]
    fn an_exhausted_plan_grants_no_action() {
        assert!(Access::PaymentRequired < Access::Read);
        assert!(Access::PaymentRequired < Access::ReadWrite);
        assert!(Access::PaymentRequired > Access::Refused);
    }

    #[test]
    fn refusals_replay_with_their_own_status() {
        let Some(Outcome::Refuse(refused)) = settle(
            Some(&entry(Access::Refused)),
            Access::Read,
            &request(),
            Instant::now(),
        ) else {
            panic!("expected the refusal to replay");
        };
        assert_eq!(refused.status, 403);

        let Some(Outcome::Refuse(invalid)) = settle(
            Some(&entry(Access::Invalid)),
            Access::Read,
            &request(),
            Instant::now(),
        ) else {
            panic!("expected the 401 to replay");
        };
        assert_eq!(invalid.status, 401);
    }

    #[test]
    fn nothing_held_settles_nothing() {
        assert!(settle(None, Access::Read, &request(), Instant::now()).is_none());
    }

    // The lifetime is the reuse ceiling: a refusal stands for seconds, a level
    // until the credential's own expiry or the ceiling, whichever comes first.
    #[test]
    fn a_lifetime_is_bounded_by_the_credential_expiry_and_the_ceiling() {
        assert_eq!(entry_lifetime(Access::Refused, None), REFUSAL_TTL);
        assert_eq!(entry_lifetime(Access::Invalid, None), REFUSAL_TTL);
        assert_eq!(entry_lifetime(Access::ReadWrite, None), CONFIRMED_TTL);
        assert_eq!(
            entry_lifetime(Access::ReadWrite, Some(Duration::from_secs(120))),
            Duration::from_secs(120)
        );
        assert_eq!(
            entry_lifetime(Access::Read, Some(CONFIRMED_TTL * 4)),
            CONFIRMED_TTL
        );
        assert_eq!(
            entry_lifetime(Access::ReadWrite, Some(Duration::ZERO)),
            Duration::ZERO
        );
    }

    #[test]
    fn an_entry_carries_its_own_lifetime_into_the_cache() {
        let expiry = EntryExpiry;
        let mut held = entry(Access::ReadWrite);
        held.lifetime = Duration::from_secs(120);

        assert_eq!(
            Expiry::<String, AccessEntry>::expire_after_create(
                &expiry,
                &"k".to_string(),
                &held,
                Instant::now()
            ),
            Some(Duration::from_secs(120))
        );
    }

    // Replacing an entry has to reset its lifetime: every write comes from a
    // fresh authoritative answer, and moka's default would keep the deadline
    // of the entry being replaced.
    #[test]
    fn replacing_an_entry_resets_its_lifetime() {
        let expiry = EntryExpiry;

        assert_eq!(
            Expiry::<String, AccessEntry>::expire_after_update(
                &expiry,
                &"k".to_string(),
                &entry(Access::ReadWrite),
                Instant::now(),
                Some(Duration::from_secs(1)),
            ),
            Some(CONFIRMED_TTL)
        );
    }

    // The action is deliberately not in the key: the level answers both, so a
    // write asks the same question as the read before it. Everything else is.
    #[test]
    fn the_key_separates_credentials_and_targets_but_not_actions() {
        let ios = request().target;
        let android = RequestTarget {
            identifier: "acme/android".into(),
            namespace: Some("android".into()),
            ..ios.clone()
        };
        let account = RequestTarget {
            scope: Scope::Account,
            account: "acme".into(),
            namespace: None,
            identifier: "acme".into(),
        };

        let credential = fingerprint("cred");
        let other = fingerprint("other");
        assert_eq!(entry_key(&credential, &ios), entry_key(&credential, &ios));
        assert_ne!(
            entry_key(&credential, &ios),
            entry_key(&credential, &android)
        );
        assert_ne!(entry_key(&credential, &ios), entry_key(&other, &ios));
        assert_ne!(
            entry_key(&credential, &account),
            entry_key(&credential, &ios)
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 8)]
    #[ignore = "performance benchmark run by autoresearch.sh"]
    async fn authorization_cache_lookup_benchmark() {
        const SAMPLES: usize = 6;

        let authorization: Arc<str> = format!("Bearer {}", "credential".repeat(96)).into();
        let target = Arc::new(request().target);
        let held = entry(Access::ReadWrite);

        let encoded = serde_json::to_vec(&authorization.as_ref()).expect("serialize credential");
        let legacy_credential_key = format!("{:x}", Sha256::digest(&encoded));
        let legacy_entry_key = format!(
            "{legacy_credential_key}:{}:{}",
            target.scope.key(),
            target.identifier
        );
        let legacy_entries = AsyncCache::builder()
            .max_capacity(1_000)
            .eviction_policy(EvictionPolicy::lru())
            .expire_after(EntryExpiry)
            .build();
        legacy_entries.insert(legacy_entry_key, held.clone()).await;
        let legacy_revocations = AsyncCache::builder()
            .max_capacity(1_000)
            .eviction_policy(EvictionPolicy::lru())
            .time_to_live(CONFIRMED_TTL)
            .build();

        let credential_key = fingerprint(&authorization);
        let entries = Cache::builder()
            .max_capacity(1_000)
            .eviction_policy(EvictionPolicy::lru())
            .expire_after(EntryExpiry)
            .build();
        entries.insert(entry_key(&credential_key, &target), held);
        let revocations = Cache::builder()
            .max_capacity(1_000)
            .eviction_policy(EvictionPolicy::lru())
            .time_to_live(CONFIRMED_TTL)
            .build();
        assert!(
            entries.get(&entry_key(&credential_key, &target)).is_some(),
            "the typed key must resolve the stored entry"
        );

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let arguments = || {
                (
                    legacy_entries.clone(),
                    legacy_revocations.clone(),
                    entries.clone(),
                    revocations.clone(),
                    authorization.clone(),
                    target.clone(),
                )
            };
            let (baseline, candidate) = if sample % 2 == 0 {
                let (old_entries, old_revocations, entries, revocations, authorization, target) =
                    arguments();
                let baseline = measure_cache_lookup(
                    true,
                    old_entries,
                    old_revocations,
                    entries,
                    revocations,
                    authorization,
                    target,
                )
                .await;
                let (old_entries, old_revocations, entries, revocations, authorization, target) =
                    arguments();
                let candidate = measure_cache_lookup(
                    false,
                    old_entries,
                    old_revocations,
                    entries,
                    revocations,
                    authorization,
                    target,
                )
                .await;
                (baseline, candidate)
            } else {
                let (old_entries, old_revocations, entries, revocations, authorization, target) =
                    arguments();
                let candidate = measure_cache_lookup(
                    false,
                    old_entries,
                    old_revocations,
                    entries,
                    revocations,
                    authorization,
                    target,
                )
                .await;
                let (old_entries, old_revocations, entries, revocations, authorization, target) =
                    arguments();
                let baseline = measure_cache_lookup(
                    true,
                    old_entries,
                    old_revocations,
                    entries,
                    revocations,
                    authorization,
                    target,
                )
                .await;
                (baseline, candidate)
            };
            if sample > 0 {
                baseline_rates.push(baseline);
                candidate_rates.push(candidate);
                speedups.push(candidate / baseline);
            }
        }
        baseline_rates.sort_by(f64::total_cmp);
        candidate_rates.sort_by(f64::total_cmp);
        speedups.sort_by(f64::total_cmp);
        let median = speedups.len() / 2;

        println!(
            "METRIC auth_cache_lookup_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC auth_cache_lookup_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC auth_cache_lookup_speedup_ratio={:.6}",
            speedups[median]
        );
    }
}
