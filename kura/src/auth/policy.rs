//! The cache authorization policy: who a caller is, and whether they may do
//! what they are asking for.
//!
//! Authentication is answered from the token itself whenever it can be, and
//! falls back to asking Tuist's server only when it cannot. Authorization is
//! pure — by the time it runs, everything it needs is on the principal.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use serde_json::{Value, json};
use tracing::warn;

use super::grants::CacheGrants;
use super::target::{Action, RequestTarget, Scope, request_action, request_target};
use super::tuist::{EXPIRY_LEEWAY, TuistBackend};
use crate::auth::{DenyDecision, Principal, RequestContext};

/// What a request is asking, resolved once and then read by everything that
/// needs it. Resolving it per consumer is how the cache key and the policy came
/// to disagree about which project a request named.
#[derive(Clone, Debug)]
pub struct ResolvedRequest {
    pub target: RequestTarget,
    pub action: Action,
}

/// The credential check comes first: a request carrying none is refused for
/// that before its target matters.
pub fn resolve_request(ctx: &RequestContext) -> Result<ResolvedRequest, DenyDecision> {
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

#[derive(Clone, Debug, PartialEq)]
pub enum Authentication {
    Principal(Principal),
    Deny(DenyDecision),
    /// The backend could not be reached or could not answer, so this is not a
    /// verdict on the token. Kept apart from `Deny` because the engine may
    /// answer it from a principal the backend already confirmed, which it must
    /// never do for a backend that did answer.
    Unavailable(DenyDecision),
}

impl Authentication {
    fn deny(status: u16, message: &str) -> Self {
        Self::Deny(DenyDecision {
            status,
            message: message.into(),
        })
    }

    fn unavailable(reason: &str) -> Self {
        warn!("authentication backend unavailable: {reason}");
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

#[derive(Clone, Debug, PartialEq)]
pub enum Authorization {
    Allow,
    Deny(DenyDecision),
}

fn authorization_header(ctx: &RequestContext) -> Option<&str> {
    ctx.headers
        .get("authorization")
        .or_else(|| ctx.headers.get("Authorization"))
        .map(String::as_str)
        .filter(|header| !header.is_empty())
}

fn bearer_token(authorization: &str) -> &str {
    authorization
        .strip_prefix("Bearer")
        .map(|token| token.trim_start())
        .unwrap_or(authorization)
}

fn principal_from_grants(id: Option<&str>, kind: Option<&str>, grants: &CacheGrants) -> Principal {
    Principal {
        id: id.unwrap_or("tuist").to_owned(),
        kind: kind.unwrap_or("subject").to_owned(),
        attributes: json!({
            "cache_grants": grants,
            "accounts": grants.accounts(),
            "projects": grants.projects(),
        }),
    }
}

/// Folds what the backend just confirmed into what the node already held for
/// the same credential.
///
/// The two answers are about different targets, and they can come from
/// different routes: introspection speaks in grants and the legacy route speaks
/// in bare handles. Replacing one with the other drops whatever the other had
/// settled, and the next request for it goes back to the backend — a token
/// reaching two projects would alternate, paying a call every time it changed
/// which one it asked about. Both shapes normalize to grants, which is the
/// shape `authorize` prefers when it finds one.
///
/// The fold must not overrule a refusal. A server narrowing a token — a project
/// dropped from its grants, a user removed from a project — refuses the request
/// that triggered the consultation, and folding what the node held back in
/// would re-grant exactly what was just taken away, for every request after it.
/// Withdrawing what this request asked for keeps the case the fold exists for
/// without that.
pub fn merge_principals(
    held: &Principal,
    fresh: &Principal,
    request: &ResolvedRequest,
) -> Principal {
    let ResolvedRequest { target, action } = request;
    let merged = CacheGrants::from_principal(&fresh.attributes)
        .merged(&CacheGrants::from_principal(&held.attributes));

    let grants = if CacheGrants::from_principal(&fresh.attributes).allow(target, action) {
        merged
    } else {
        merged.withdraw(target, action)
    };
    let accounts = grants.accounts();
    let projects = grants.projects();

    Principal {
        id: fresh.id.clone(),
        kind: fresh.kind.clone(),
        attributes: json!({
            "cache_grants": grants,
            "accounts": accounts,
            "projects": projects,
        }),
    }
}

/// A principal that predates cache grants: it carries bare handles, and the
/// absence of `cache_grants` is what later lets it use the handle fallback.
fn principal_from_handles(
    id: Option<&str>,
    kind: Option<&str>,
    accounts: Vec<String>,
    projects: Vec<String>,
) -> Principal {
    Principal {
        id: id.unwrap_or("tuist").to_owned(),
        kind: kind.unwrap_or("subject").to_owned(),
        attributes: json!({ "accounts": accounts, "projects": projects }),
    }
}

fn string_field<'a>(body: &'a Value, key: &str) -> Option<&'a str> {
    body.get(key).and_then(Value::as_str)
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
    request: &ResolvedRequest,
) -> Authentication {
    let Some(authorization) = authorization_header(ctx) else {
        return Authentication::deny(401, "Missing Authorization header");
    };
    let token = bearer_token(authorization);
    let ResolvedRequest { target, action } = request;

    if let Some(Ok(claims)) = backend.verify_token(token)
        && let Some(authentication) = from_verified_claims(&claims, target, action)
    {
        return authentication;
    }

    // Past this point the credential is going to the server, and a credential
    // past its own expiry has nothing to gain there: the server validates `exp`
    // too and answers inactive. Refusing here keeps a client looping on a stale
    // token off the control plane, and keeps the engine from holding an entry
    // that is already dead on arrival. It refuses over the same window the
    // verifier above accepts over, or a credential inside that window would be
    // read from its own grants and refused everything they do not cover.
    if credential_expired(ctx) {
        return Authentication::deny(401, "Invalid or expired token");
    }

    if backend.introspection_configured() {
        return authenticate_via_introspection(backend, token, authorization, target, action).await;
    }

    // Without introspection the only remaining answer is the legacy route, and
    // it only speaks about projects.
    if target.scope == Scope::Project {
        return authenticate_via_cache_access(backend, authorization).await;
    }

    // Not an outage: this node was never given the credentials that would let
    // it ask about an account-scoped request, so retrying cannot help.
    Authentication::deny(
        503,
        "Authentication backend is not configured for account-scoped requests",
    )
}

/// What a verified token alone can settle. `None` means the token was readable
/// but does not itself prove this request, so the caller keeps looking.
fn from_verified_claims(
    claims: &Value,
    target: &RequestTarget,
    action: &Action,
) -> Option<Authentication> {
    let grants = CacheGrants::from_body(claims);
    let id = string_field(claims, "sub");
    let kind = string_field(claims, "type");

    if grants.allow(target, action) {
        return Some(Authentication::Principal(principal_from_grants(
            id, kind, &grants,
        )));
    }

    // Tokens minted before grants existed carry bare project handles instead.
    // The `scopes` claim marks the newer format, whose handles are not
    // authorization.
    if claims.get("scopes").is_none() && target.scope == Scope::Project {
        let projects = normalized_handles(claims.get("projects"));
        if projects.iter().any(|project| project == &target.identifier) {
            return Some(Authentication::Principal(principal_from_handles(
                id,
                kind,
                Vec::new(),
                projects,
            )));
        }
    }

    None
}

async fn authenticate_via_introspection(
    backend: &TuistBackend,
    token: &str,
    authorization: &str,
    target: &RequestTarget,
    action: &Action,
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
        let grants = CacheGrants::from_body(&response.body);

        // A token can be active and still not prove this project: its grants
        // may predate the project. The legacy route still answers for those.
        if target.scope == Scope::Project && !grants.allow(target, action) {
            return authenticate_via_cache_access(backend, authorization).await;
        }

        return Authentication::Principal(principal_from_grants(
            string_field(&response.body, "sub"),
            string_field(&response.body, "principal_kind"),
            &grants,
        ));
    }

    if target.scope == Scope::Project {
        return authenticate_via_cache_access(backend, authorization).await;
    }

    Authentication::deny(401, "Invalid or expired token")
}

async fn authenticate_via_cache_access(
    backend: &TuistBackend,
    authorization: &str,
) -> Authentication {
    let response = match backend.cache_access(authorization).await {
        Ok(response) => response,
        Err(error) => return Authentication::unavailable(&error),
    };

    match response.status {
        200 => Authentication::Principal(principal_from_handles(
            None,
            None,
            Vec::new(),
            project_handles(&response.body),
        )),
        401 => Authentication::deny(401, "Invalid or expired token"),
        status => Authentication::unavailable(&format!("cache access returned status {status}")),
    }
}

pub fn authorize(request: &ResolvedRequest, principal: Option<&Principal>) -> Authorization {
    let Some(principal) = principal else {
        return Authorization::Deny(DenyDecision {
            status: 401,
            message: "Unauthorized".into(),
        });
    };
    let ResolvedRequest { target, action } = request;

    match CacheGrants::from_principal_attributes(&principal.attributes) {
        Some(grants) => {
            if grants.allow(target, action) {
                return Authorization::Allow;
            }
        }
        None => {
            if target.scope == Scope::Project {
                let projects = normalized_handles(principal.attributes.get("projects"));
                if projects.iter().any(|project| project == &target.identifier) {
                    return Authorization::Allow;
                }
            }
        }
    }

    Authorization::Deny(DenyDecision {
        status: 403,
        message: format!(
            "Forbidden: {} '{}' is not granted to this principal for {}",
            target.scope.key(),
            target.identifier,
            action.key()
        ),
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;

    fn ctx() -> RequestContext {
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
            headers: BTreeMap::new(),
            query: BTreeMap::new(),
            status_code: None,
        }
    }

    fn granted_principal() -> Principal {
        principal_from_grants(
            Some("user"),
            Some("subject"),
            &CacheGrants::from_body(&json!({
                "cache_grants": { "project": { "write": ["acme/ios"] } }
            })),
        )
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

        let authentication = from_verified_claims(
            &claims,
            &request_target(&ctx()).expect("target"),
            &Action::Read,
        );

        let Some(Authentication::Principal(principal)) = authentication else {
            panic!("expected a principal, got {authentication:?}");
        };
        assert_eq!(principal.id, "user");
        assert_eq!(principal.attributes["projects"], json!(["acme/ios"]));
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
            from_verified_claims(
                &claims,
                &request_target(&ctx()).expect("target"),
                &Action::Read
            ),
            None
        );
    }

    // Tokens minted before grants existed carry bare handles and no `scopes`.
    #[test]
    fn falls_back_to_bare_handles_only_for_tokens_that_predate_scopes() {
        let legacy = json!({ "sub": "user", "projects": ["ACME/iOS"] });
        let scoped = json!({ "sub": "user", "scopes": [], "projects": ["ACME/iOS"] });
        let target = request_target(&ctx()).expect("target");

        assert!(matches!(
            from_verified_claims(&legacy, &target, &Action::Read),
            Some(Authentication::Principal(_))
        ));
        assert_eq!(from_verified_claims(&scoped, &target, &Action::Read), None);
    }

    #[test]
    fn an_account_scoped_request_never_uses_the_project_handle_fallback() {
        let mut context = ctx();
        context.namespace_id = None;
        let claims = json!({ "sub": "user", "projects": ["acme"] });

        assert_eq!(
            from_verified_claims(
                &claims,
                &request_target(&context).expect("target"),
                &Action::Read
            ),
            None
        );
    }

    // Built directly rather than through `resolve_request`, so these can drive
    // `authorize` without also standing up a credential it never reads.
    fn resolved(ctx: &RequestContext) -> ResolvedRequest {
        ResolvedRequest {
            target: request_target(ctx).expect("a resolvable target"),
            action: request_action(ctx),
        }
    }

    #[test]
    fn authorizes_a_principal_whose_grants_cover_the_request() {
        assert_eq!(
            authorize(&resolved(&ctx()), Some(&granted_principal())),
            Authorization::Allow
        );
    }

    #[test]
    fn refuses_a_write_to_a_principal_granted_only_reads() {
        let principal = principal_from_grants(
            Some("user"),
            None,
            &CacheGrants::from_body(&json!({
                "cache_grants": { "project": { "read": ["acme/ios"] } }
            })),
        );
        let mut context = ctx();
        context.method = "PUT".into();
        context.operation = "artifact.write".into();

        let Authorization::Deny(deny) = authorize(&resolved(&context), Some(&principal)) else {
            panic!("expected a denial");
        };
        assert_eq!(deny.status, 403);
        assert!(deny.message.contains("project 'acme/ios'"));
        assert!(deny.message.ends_with("for write"));
    }

    #[test]
    fn refuses_a_request_with_no_principal() {
        let Authorization::Deny(deny) = authorize(&resolved(&ctx()), None) else {
            panic!("expected a denial");
        };
        assert_eq!(deny.status, 401);
    }

    #[test]
    fn authorizes_a_legacy_principal_from_its_project_handles() {
        let principal = principal_from_handles(None, None, Vec::new(), vec!["acme/ios".into()]);

        assert_eq!(
            authorize(&resolved(&ctx()), Some(&principal)),
            Authorization::Allow
        );
    }

    // A principal built from grants has already had its say, so its handles are
    // not a second chance; only a principal carrying no grants at all falls back.
    #[test]
    fn does_not_let_a_granted_principal_fall_back_to_its_handles() {
        let principal = principal_from_grants(
            Some("user"),
            None,
            &CacheGrants::from_body(&json!({
                "cache_grants": { "project": { "read": ["acme/web"] } }
            })),
        );
        let mut principal = principal;
        principal.attributes["projects"] = json!(["acme/ios"]);

        assert!(matches!(
            authorize(&resolved(&ctx()), Some(&principal)),
            Authorization::Deny(_)
        ));
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
