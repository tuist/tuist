//! The cache authorization policy: what a credential may do to a target.
//!
//! The answer is worked out from the token itself whenever it can be, and from
//! Tuist's server only when it cannot. Either way it comes back as one access
//! level for the credential and target, which is the shape the engine caches.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::Value;
use tracing::warn;

use super::grants::CacheGrants;
use super::target::{Action, RequestTarget, Scope, request_action, request_target};
use super::tuist::{EXPIRY_LEEWAY, TuistBackend};
use crate::auth::{Access, DenyDecision, RequestContext};

/// What a request is asking, resolved once and then read by everything that
/// needs it. Resolving it per consumer is how the cache key and the policy came
/// to disagree about which project a request named.
#[derive(Clone, Debug)]
pub struct ResolvedRequest<'a> {
    pub target: RequestTarget<'a>,
    pub action: Action,
}

/// The credential check comes first: a request carrying none is refused for
/// that before its target matters.
pub fn resolve_request(ctx: &RequestContext) -> Result<ResolvedRequest<'_>, DenyDecision> {
    if authorization_header(ctx).is_none() {
        return Err(DenyDecision {
            status: 401,
            message: "Missing Authorization header".into(),
        });
    }

    Ok(ResolvedRequest {
        target: request_target(ctx)?,
        action: request_action(ctx),
    })
}

/// The 403 a target refusal answers with.
pub fn refusal(request: &ResolvedRequest<'_>) -> DenyDecision {
    DenyDecision {
        status: 403,
        message: format!(
            "Forbidden: {} '{}' is not granted to this principal for {}",
            request.target.scope.key(),
            request.target.identifier,
            request.action.key()
        ),
    }
}

/// The 402 an account whose free tier is exhausted answers with. Distinct from
/// `refusal` because the caller can act on this one.
pub fn payment_required(request: &ResolvedRequest<'_>) -> DenyDecision {
    DenyDecision {
        status: 402,
        message: format!(
            "The account '{}' has reached the limits of the plan 'Tuist Air' and requires upgrading to the plan 'Tuist Pro'.",
            request.target.account
        ),
    }
}

/// The 401 an invalid credential answers with.
pub fn invalid_credential() -> DenyDecision {
    DenyDecision {
        status: 401,
        message: "Invalid or expired token".into(),
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum Authentication {
    /// An authoritative access level for this credential and target, from the
    /// token itself or from the server.
    Access(Access),
    /// A refusal that is not an access level: the node is not configured to
    /// answer this shape of request at all, so caching it buys nothing.
    Deny(DenyDecision),
    /// The backend could not be reached or could not answer, so this is not a
    /// verdict on the token. Kept apart from `Deny` because the engine may
    /// answer it from a level the backend already confirmed, which it must
    /// never do for a backend that did answer.
    Unavailable(DenyDecision),
}

impl Authentication {
    fn unavailable(reason: &str) -> Self {
        warn!(
            event.name = "kura.auth.backend_unavailable",
            error.reason = reason,
            "authentication backend unavailable"
        );
        Self::Unavailable(DenyDecision {
            status: 503,
            message: "Authentication backend unavailable".into(),
        })
    }
}

/// How much life the credential says it has left, read from an unverified
/// `exp` claim.
///
/// Only ever consulted for a credential the backend has just confirmed. A
/// forged `exp` breaks the signature the backend checks, so an `exp` read off
/// a confirmed credential is the one the issuer signed. A credential this
/// cannot be read from — an opaque project or account token, which the server
/// resolves against its own records — is bounded by the cache instead.
pub fn credential_expiry(ctx: &RequestContext) -> Option<Duration> {
    let (expires_at, now) = credential_deadline(ctx)?;
    Some(Duration::from_secs(expires_at.saturating_sub(now)))
}

/// Whether the credential is far enough past its own expiry that the verifier
/// would no longer read it either.
fn credential_expired(ctx: &RequestContext) -> bool {
    credential_deadline(ctx)
        .is_some_and(|(expires_at, now)| now.saturating_sub(expires_at) > EXPIRY_LEEWAY.as_secs())
}

/// The `exp` the credential carries and the time to judge it against, both in
/// seconds since the epoch. `None` when the credential names no deadline.
fn credential_deadline(ctx: &RequestContext) -> Option<(u64, u64)> {
    let token = bearer_token(authorization_header(ctx)?);
    let claims = URL_SAFE_NO_PAD.decode(token.split('.').nth(1)?).ok()?;
    let expires_at = serde_json::from_slice::<Value>(&claims)
        .ok()?
        .get("exp")?
        .as_u64()?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();

    Some((expires_at, now))
}

pub(super) fn authorization_header(ctx: &RequestContext) -> Option<&str> {
    ctx.authorization
        .as_deref()
        .or_else(|| {
            ctx.headers
                .get("authorization")
                .or_else(|| ctx.headers.get("Authorization"))
                .map(String::as_str)
        })
        .filter(|header| !header.is_empty())
}

fn bearer_token(authorization: &str) -> &str {
    authorization
        .strip_prefix("Bearer")
        .map(|token| token.trim_start())
        .unwrap_or(authorization)
}

fn normalized_handles(value: Option<&Value>) -> Vec<String> {
    let Some(Value::Array(items)) = value else {
        return Vec::new();
    };

    items
        .iter()
        .filter_map(Value::as_str)
        .filter(|handle| !handle.is_empty())
        .map(str::to_lowercase)
        .collect()
}

/// The cache-access route answers with projects as either bare names or
/// objects carrying `full_name`, depending on the server's age.
fn project_handles(body: &Value) -> Vec<String> {
    let Some(Value::Array(projects)) = body.get("projects") else {
        return Vec::new();
    };

    projects
        .iter()
        .filter_map(|project| match project {
            Value::String(name) => Some(name.as_str()),
            project => project.get("full_name").and_then(Value::as_str),
        })
        .filter(|name| !name.is_empty())
        .map(str::to_lowercase)
        .collect()
}

pub async fn authenticate(
    backend: &TuistBackend,
    ctx: &RequestContext,
    request: &ResolvedRequest<'_>,
) -> Authentication {
    let Some(authorization) = authorization_header(ctx) else {
        return Authentication::Access(Access::Invalid);
    };
    let token = bearer_token(authorization);
    let ResolvedRequest { target, action } = request;
    let required = Access::required(action);

    if let Some(Ok(claims)) = backend.verify_token(token)
        && let Some(level) = from_verified_claims(&claims, target, required)
    {
        return Authentication::Access(level);
    }

    // Past this point the credential is going to the server, and a credential
    // past its own expiry has nothing to gain there: the server validates `exp`
    // too and answers inactive. Refusing here keeps a client looping on a stale
    // token off the control plane, and keeps the engine from holding an entry
    // that is already dead on arrival. It refuses over the same window the
    // verifier above accepts over, or a credential inside that window would be
    // read from its own grants and refused everything they do not cover.
    if credential_expired(ctx) {
        return Authentication::Access(Access::Invalid);
    }

    if backend.introspection_configured() {
        return via_introspection(backend, token, authorization, target, required).await;
    }

    // Without introspection the only remaining answer is the legacy route, and
    // it only speaks about projects.
    if target.scope == Scope::Project {
        return via_cache_access(backend, authorization, target, Access::Refused).await;
    }

    // Not an outage: this node was never given the credentials that would let
    // it ask about an account-scoped request, so retrying cannot help.
    Authentication::Deny(DenyDecision {
        status: 503,
        message: "Authentication backend is not configured for account-scoped requests".into(),
    })
}

/// What a verified token alone can settle. `None` means the token was readable
/// but its own level does not reach what this action needs, so the caller keeps
/// looking: the server may allow it through a route the claims know nothing
/// about, and only an answer that settles the request is worth skipping the
/// server for.
fn from_verified_claims(
    claims: &Value,
    target: &RequestTarget<'_>,
    required: Access,
) -> Option<Access> {
    let level = CacheGrants::from_body(claims).level(target);
    if level >= required {
        return Some(level);
    }

    // Terminal, not inconclusive. The level is deliberately below `Read` so it
    // grants nothing, which means the check above rejects it exactly as it
    // rejects a credential the grants do not cover. Falling through would send
    // the caller to introspection, and a cache token is not an API credential
    // there, so the answer would come back 401 and the reason would be lost.
    if level == Access::PaymentRequired {
        return Some(level);
    }

    // Tokens minted before grants existed carry bare project handles instead.
    // The `scopes` claim marks the newer format, whose handles are not
    // authorization. A handle carries no action, so it answers as both — which
    // is exactly what it authorized on its own.
    if claims.get("scopes").is_none() && target.scope == Scope::Project {
        let projects = normalized_handles(claims.get("projects"));
        if projects.iter().any(|project| project == &target.identifier) {
            return Some(Access::ReadWrite);
        }
    }

    None
}

async fn via_introspection(
    backend: &TuistBackend,
    token: &str,
    authorization: &str,
    target: &RequestTarget<'_>,
    required: Access,
) -> Authentication {
    let response = match backend.introspect(token).await {
        Ok(response) => response,
        Err(error) => return Authentication::unavailable(&error),
    };

    if response.status != 200 {
        return Authentication::unavailable(&format!(
            "introspection returned status {}",
            response.status
        ));
    }

    if response.body.get("active") == Some(&Value::Bool(true)) {
        let level = CacheGrants::from_body(&response.body).level(target);

        // A token can be active and still not prove this project: its grants
        // may predate the project. The legacy route still answers for those,
        // and the level introspection did establish travels along so a route
        // that cannot widen it does not erase it either.
        // Terminal here for the same reason it is terminal on locally verified
        // claims: it sits below `Read`, so it would otherwise read as a level
        // that simply did not reach far enough and send the caller on again.
        if level == Access::PaymentRequired {
            return Authentication::Access(level);
        }

        if level < required && target.scope == Scope::Project {
            return via_cache_access(backend, authorization, target, level).await;
        }

        return Authentication::Access(level);
    }

    if target.scope == Scope::Project {
        return via_cache_access(backend, authorization, target, Access::Refused).await;
    }

    Authentication::Access(Access::Invalid)
}

/// `floor` is what an earlier route already established, so an answer here can
/// only raise the level, never lower it.
async fn via_cache_access(
    backend: &TuistBackend,
    authorization: &str,
    target: &RequestTarget<'_>,
    floor: Access,
) -> Authentication {
    let response = match backend.cache_access(authorization).await {
        Ok(response) => response,
        Err(error) => return Authentication::unavailable(&error),
    };

    match response.status {
        200 => {
            let covered = project_handles(&response.body)
                .iter()
                .any(|project| project == &target.identifier);
            // A handle carries no action, so it answers as both, exactly what
            // it authorized on its own.
            let level = if covered {
                Access::ReadWrite
            } else if CacheGrants::from_body(&response.body).payment_required_for(target) {
                Access::PaymentRequired
            } else {
                floor
            };
            Authentication::Access(level)
        }
        401 => Authentication::Access(Access::Invalid),
        status => Authentication::unavailable(&format!("cache access returned status {status}")),
    }
}

#[cfg(test)]
mod tests {

    // An unscoped cache token carries no grant for the project, so the level
    // check reads it as a level that did not reach far enough and would send the
    // caller to introspection, where a cache token is not an API credential: the
    // answer comes back 401 and the reason for the refusal is lost.
    #[test]
    fn an_exhausted_plan_on_a_cache_token_is_terminal_without_a_round_trip() {
        let claims = serde_json::json!({
            "cache_grants": {
                "account": { "read": [], "write": [] },
                "project": { "read": [], "write": [] }
            },
            "cache_payment_required": ["acme"]
        });
        let target = RequestTarget {
            scope: Scope::Project,
            account: "acme".into(),
            namespace: Some("ios".into()),
            identifier: "acme/ios".into(),
        };

        assert_eq!(
            from_verified_claims(&claims, &target, Access::Read),
            Some(Access::PaymentRequired)
        );
        assert_eq!(
            from_verified_claims(&claims, &target, Access::ReadWrite),
            Some(Access::PaymentRequired)
        );
    }

    // A credential that simply does not reach the project must still fall
    // through to the routes that can answer for it.
    #[test]
    fn a_token_that_simply_does_not_reach_stays_inconclusive() {
        let claims = serde_json::json!({
            "cache_grants": {
                "account": { "read": [], "write": [] },
                "project": { "read": [], "write": [] }
            }
        });
        let target = RequestTarget {
            scope: Scope::Project,
            account: "acme".into(),
            namespace: Some("ios".into()),
            identifier: "acme/ios".into(),
        };

        assert_eq!(from_verified_claims(&claims, &target, Access::Read), None);
    }
    use std::collections::BTreeMap;

    use serde_json::json;

    use super::*;

    fn ctx() -> RequestContext {
        RequestContext {
            transport: "http".into(),
            method: "GET".into(),
            operation: "artifact.read".into(),
            server_tenant_id: "acme".into(),
            tenant_id: Some("acme".into()),
            namespace_id: Some("ios".into()),
            authorization: None,
            headers: BTreeMap::new(),
        }
    }

    fn target_of(ctx: &RequestContext) -> RequestTarget<'_> {
        request_target(ctx).expect("a resolvable target")
    }

    #[test]
    fn strips_the_bearer_prefix_and_leaves_a_bare_token_alone() {
        assert_eq!(bearer_token("Bearer abc"), "abc");
        assert_eq!(bearer_token("Bearer   abc"), "abc");
        assert_eq!(bearer_token("abc"), "abc");
    }

    #[test]
    fn reads_projects_as_names_or_objects() {
        let body = json!({ "projects": ["ACME/web", { "full_name": "ACME/iOS" }, { "id": 1 }] });

        assert_eq!(project_handles(&body), vec!["acme/web", "acme/ios"]);
    }

    #[test]
    fn a_token_whose_grants_cover_the_request_needs_no_backend() {
        let claims = json!({
            "sub": "user", "type": "user",
            "cache_grants": { "project": { "write": ["acme/ios"] } },
        });

        assert_eq!(
            from_verified_claims(&claims, &target_of(&ctx()), Access::Read),
            Some(Access::ReadWrite)
        );
    }

    // The grants are the authority; a token that carries them but not for this
    // project has to go and ask, even though it names the project elsewhere.
    #[test]
    fn a_token_granting_another_project_does_not_settle_this_one() {
        let claims = json!({
            "sub": "user",
            "scopes": ["account_cache_read"],
            "cache_grants": { "project": { "write": ["acme/web"] } },
            "projects": ["acme/ios"],
        });

        assert_eq!(
            from_verified_claims(&claims, &target_of(&ctx()), Access::Read),
            None
        );
    }

    // A level below what the action needs settles nothing: the server may
    // allow the action through a route the claims know nothing about.
    #[test]
    fn a_read_only_token_does_not_settle_a_write() {
        let claims = json!({
            "sub": "user",
            "cache_grants": { "project": { "read": ["acme/ios"] } },
        });

        assert_eq!(
            from_verified_claims(&claims, &target_of(&ctx()), Access::Read),
            Some(Access::Read)
        );
        assert_eq!(
            from_verified_claims(&claims, &target_of(&ctx()), Access::ReadWrite),
            None
        );
    }

    // Tokens minted before grants existed carry bare handles and no `scopes`.
    #[test]
    fn falls_back_to_bare_handles_only_for_tokens_that_predate_scopes() {
        let legacy = json!({ "sub": "user", "projects": ["ACME/iOS"] });
        let scoped = json!({ "sub": "user", "scopes": [], "projects": ["ACME/iOS"] });
        let context = ctx();
        let target = target_of(&context);

        assert_eq!(
            from_verified_claims(&legacy, &target, Access::Read),
            Some(Access::ReadWrite)
        );
        assert_eq!(from_verified_claims(&scoped, &target, Access::Read), None);
    }

    #[test]
    fn an_account_scoped_request_never_uses_the_project_handle_fallback() {
        let mut context = ctx();
        context.namespace_id = None;
        let claims = json!({ "sub": "user", "projects": ["acme"] });

        assert_eq!(
            from_verified_claims(&claims, &target_of(&context), Access::Read),
            None
        );
    }

    #[test]
    fn a_refusal_names_the_target_and_the_action() {
        let mut context = ctx();
        context.method = "PUT".into();
        context.operation = "artifact.write".into();
        let request = ResolvedRequest {
            target: target_of(&context),
            action: request_action(&context),
        };

        let deny = refusal(&request);

        assert_eq!(deny.status, 403);
        assert!(deny.message.contains("project 'acme/ios'"));
        assert!(deny.message.ends_with("for write"));
    }

    // A request naming a tenant this server does not serve is refused where the
    // target is resolved, before anything asks who is carrying it.
    #[test]
    fn refuses_a_request_naming_another_server_tenant() {
        let mut context = ctx();
        context.tenant_id = Some("other".into());
        context
            .headers
            .insert("authorization".into(), "Bearer token".into());

        let deny = resolve_request(&context).expect_err("expected a denial");

        assert_eq!(deny.status, 403);
        assert!(deny.message.contains("routed to server for"));
    }

    // And a request carrying no credential is refused for that first, whatever
    // its target would have resolved to.
    #[test]
    fn refuses_a_request_carrying_no_credential_before_resolving_its_target() {
        let mut context = ctx();
        context.headers.clear();
        context.tenant_id = None;

        let deny = resolve_request(&context).expect_err("expected a denial");

        assert_eq!(deny.status, 401);
        assert!(deny.message.contains("Missing Authorization"));
    }
}
