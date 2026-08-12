//! Resolving what a request is asking for, and whether a set of grants covers
//! it. Ported from the policy that used to live in the Lua hook, so the rules
//! here are deliberately the ones that shipped rather than the ones that read
//! best: a half-rolled fleet has to authorize identically either side.

use std::collections::BTreeMap;

use crate::auth::{DenyDecision, RequestContext};

/// What a request names. A request that names no project is asking about the
/// account's own cache, which is a different thing from any project in it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Scope {
    Account,
    Project,
}

impl Scope {
    pub fn key(&self) -> &'static str {
        match self {
            Scope::Account => "account",
            Scope::Project => "project",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Action {
    Read,
    Write,
}

impl Action {
    pub fn key(&self) -> &'static str {
        match self {
            Action::Read => "read",
            Action::Write => "write",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RequestTarget {
    pub scope: Scope,
    pub account: String,
    pub namespace: Option<String>,
    /// `account` for an account-scoped request, `account/namespace` otherwise.
    /// This is what grant handles are compared against.
    pub identifier: String,
}

/// Lowercased, with empty treated as absent: the hook compared handles as
/// lowercase strings and treated `""` the same as nil.
fn normalized(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_lowercase)
}

fn query_value(query: &BTreeMap<String, String>, key: &str) -> Option<String> {
    normalized(query.get(key).map(String::as_str))
}

fn server_tenant(ctx: &RequestContext) -> Option<String> {
    normalized(Some(ctx.server_tenant_id.as_str()))
}

/// The tenant the request names, falling back to the query because some routes
/// carry it there rather than in the path.
fn request_tenant(ctx: &RequestContext) -> Option<String> {
    normalized(ctx.tenant_id.as_deref())
        .or_else(|| query_value(&ctx.query, "account_handle"))
        .or_else(|| query_value(&ctx.query, "tenant_id"))
}

fn request_namespace(ctx: &RequestContext) -> Option<String> {
    normalized(ctx.namespace_id.as_deref())
        .or_else(|| query_value(&ctx.query, "project_handle"))
        .or_else(|| query_value(&ctx.query, "namespace_id"))
}

/// Read or write, from the operation when it says, and from the method when it
/// does not.
pub fn request_action(ctx: &RequestContext) -> Action {
    let operation = ctx.operation.to_lowercase();

    if operation.ends_with(".read") || operation.ends_with(".inspect") {
        return Action::Read;
    }
    if operation.ends_with(".write") || operation.ends_with(".delete") {
        return Action::Write;
    }

    match ctx.method.to_uppercase().as_str() {
        "GET" | "HEAD" => Action::Read,
        _ => Action::Write,
    }
}

pub fn request_target(ctx: &RequestContext) -> Result<RequestTarget, DenyDecision> {
    let Some(tenant) = server_tenant(ctx) else {
        return Err(DenyDecision {
            status: 503,
            message: "Server tenant is unavailable".into(),
        });
    };

    let requested_tenant = request_tenant(ctx);

    if let Some(requested) = &requested_tenant
        && requested != &tenant
    {
        return Err(DenyDecision {
            status: 403,
            message: format!("Forbidden: tenant '{requested}' is routed to server for '{tenant}'"),
        });
    }

    // gRPC carries the instance out of band, so only HTTP has to name it.
    if requested_tenant.is_none() && ctx.transport != "grpc" {
        return Err(DenyDecision {
            status: 400,
            message: "Missing tenant_id/account_handle".into(),
        });
    }

    let namespace = request_namespace(ctx);

    Ok(match namespace {
        None => RequestTarget {
            scope: Scope::Account,
            account: tenant.clone(),
            namespace: None,
            identifier: tenant,
        },
        Some(namespace) => RequestTarget {
            identifier: format!("{tenant}/{namespace}"),
            scope: Scope::Project,
            account: tenant,
            namespace: Some(namespace),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx() -> RequestContext {
        RequestContext {
            transport: "http".into(),
            route: "/api/cache/cas/{id}".into(),
            method: "GET".into(),
            operation: "artifact.read".into(),
            server_tenant_id: "acme".into(),
            tenant_id: Some("acme".into()),
            namespace_id: None,
            producer: Some("xcode".into()),
            artifact_key: None,
            artifact_hash: None,
            headers: BTreeMap::new(),
            query: BTreeMap::new(),
            status_code: None,
        }
    }

    #[test]
    fn a_request_naming_no_project_is_account_scoped() {
        let target = request_target(&ctx()).expect("should resolve");

        assert_eq!(target.scope, Scope::Account);
        assert_eq!(target.identifier, "acme");
    }

    #[test]
    fn a_request_naming_a_project_is_project_scoped() {
        let mut context = ctx();
        context.namespace_id = Some("iOS".into());

        let target = request_target(&context).expect("should resolve");

        assert_eq!(target.scope, Scope::Project);
        assert_eq!(target.identifier, "acme/ios");
    }

    // Some routes carry the target in the query rather than the path, and the
    // hook read both.
    #[test]
    fn falls_back_to_the_query_for_the_target() {
        let mut context = ctx();
        context.tenant_id = None;
        context.namespace_id = None;
        context.query.insert("account_handle".into(), "ACME".into());
        context.query.insert("project_handle".into(), "iOS".into());

        let target = request_target(&context).expect("should resolve");

        assert_eq!(target.identifier, "acme/ios");
    }

    #[test]
    fn refuses_a_tenant_this_server_does_not_serve() {
        let mut context = ctx();
        context.tenant_id = Some("other".into());

        let deny = request_target(&context).expect_err("should deny");

        assert_eq!(deny.status, 403);
        assert!(deny.message.contains("other"));
        assert!(deny.message.contains("acme"));
    }

    #[test]
    fn requires_http_requests_to_name_a_tenant() {
        let mut context = ctx();
        context.tenant_id = None;

        let deny = request_target(&context).expect_err("should deny");

        assert_eq!(deny.status, 400);
    }

    // gRPC carries the instance out of band, so it is allowed to omit it and
    // fall back to the tenant this node serves.
    #[test]
    fn lets_grpc_omit_the_tenant() {
        let mut context = ctx();
        context.tenant_id = None;
        context.transport = "grpc".into();

        let target = request_target(&context).expect("should resolve");

        assert_eq!(target.identifier, "acme");
    }

    #[test]
    fn reports_an_unavailable_server_tenant_rather_than_denying_the_caller() {
        let mut context = ctx();
        context.server_tenant_id = String::new();

        let deny = request_target(&context).expect_err("should deny");

        assert_eq!(deny.status, 503);
    }

    #[test]
    fn reads_the_action_from_the_operation_before_the_method() {
        let mut context = ctx();

        context.operation = "artifact.write".into();
        context.method = "GET".into();
        assert_eq!(request_action(&context), Action::Write);

        context.operation = "artifact.inspect".into();
        assert_eq!(request_action(&context), Action::Read);

        context.operation = "artifact.delete".into();
        assert_eq!(request_action(&context), Action::Write);
    }

    #[test]
    fn falls_back_to_the_method_when_the_operation_does_not_say() {
        let mut context = ctx();
        context.operation = "artifact".into();

        context.method = "HEAD".into();
        assert_eq!(request_action(&context), Action::Read);

        context.method = "POST".into();
        assert_eq!(request_action(&context), Action::Write);
    }
}
