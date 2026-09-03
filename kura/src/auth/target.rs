//! Resolving what a request is asking for: which tenant and project it names,
//! and whether it is reading or writing.
//!
//! Kura rolls with mixed versions, so these rules are pinned rather than
//! tidied. Both sides of a deploy have to reach the same answer for the same
//! request, or access flickers as pods roll.

use std::collections::BTreeMap;

use crate::auth::{DenyDecision, RequestContext};

/// What a request names. A request that names no project is asking about the
/// account's own cache, which is a different thing from any project in it.
#[derive(Clone, Copy, Debug, Hash, PartialEq, Eq)]
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

/// Handles compare lowercased, and an empty value counts as absent rather than
/// as a handle named "".
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
    if ends_with_ignore_ascii_case(&ctx.operation, b".read")
        || ends_with_ignore_ascii_case(&ctx.operation, b".inspect")
    {
        return Action::Read;
    }
    if ends_with_ignore_ascii_case(&ctx.operation, b".write")
        || ends_with_ignore_ascii_case(&ctx.operation, b".delete")
    {
        return Action::Write;
    }

    if ctx.method.eq_ignore_ascii_case("GET") || ctx.method.eq_ignore_ascii_case("HEAD") {
        Action::Read
    } else {
        Action::Write
    }
}

fn ends_with_ignore_ascii_case(value: &str, suffix: &[u8]) -> bool {
    let value = value.as_bytes();
    value
        .get(value.len().saturating_sub(suffix.len())..)
        .is_some_and(|ending| ending.eq_ignore_ascii_case(suffix))
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
    use std::sync::{Arc, Barrier};

    use super::*;

    fn allocating_request_action(ctx: &RequestContext) -> Action {
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
            authorization: None,
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

    // Some routes carry the target in the query rather than the path.
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

    #[test]
    fn allocation_free_action_classification_matches_case_insensitive_behavior() {
        let cases = [
            ("artifact.READ", "POST"),
            ("artifact.InSpEcT", "POST"),
            ("artifact.WRITE", "GET"),
            ("artifact.DeLeTe", "GET"),
            ("artifact", "get"),
            ("artifact", "hEaD"),
            ("artifact", "post"),
            ("short", "GET"),
            ("é", "GET"),
        ];

        for (operation, method) in cases {
            let mut context = ctx();
            context.operation = operation.into();
            context.method = method.into();
            assert_eq!(
                request_action(&context),
                allocating_request_action(&context),
                "operation={operation} method={method}"
            );
        }
    }

    #[test]
    #[ignore = "performance benchmark run by autoresearch.sh"]
    fn allocation_free_action_classification_benchmark() {
        const WORKERS: usize = 8;
        const ITERATIONS_PER_WORKER: usize = 1_000_000;
        const SAMPLES: usize = 6;

        let mut operation_context = ctx();
        operation_context.operation = "artifact.read".into();
        operation_context.method = "POST".into();
        let mut method_context = ctx();
        method_context.operation = "request".into();
        method_context.method = "HEAD".into();
        let contexts = Arc::new([operation_context, method_context]);

        let measure = |allocation_free: bool| {
            let barrier = Arc::new(Barrier::new(WORKERS + 1));
            let started_at = std::thread::scope(|scope| {
                for _ in 0..WORKERS {
                    let barrier = barrier.clone();
                    let contexts = contexts.clone();
                    scope.spawn(move || {
                        barrier.wait();
                        for iteration in 0..ITERATIONS_PER_WORKER {
                            let context =
                                std::hint::black_box(&contexts[iteration % contexts.len()]);
                            let action = if allocation_free {
                                request_action(context)
                            } else {
                                allocating_request_action(context)
                            };
                            std::hint::black_box(action);
                        }
                    });
                }
                barrier.wait();
                std::time::Instant::now()
            });
            (WORKERS * ITERATIONS_PER_WORKER) as f64 / started_at.elapsed().as_secs_f64()
        };

        let mut baseline_rates = Vec::with_capacity(SAMPLES - 1);
        let mut candidate_rates = Vec::with_capacity(SAMPLES - 1);
        let mut speedups = Vec::with_capacity(SAMPLES - 1);
        for sample in 0..SAMPLES {
            let (baseline, candidate) = if sample % 2 == 0 {
                (measure(false), measure(true))
            } else {
                let candidate = measure(true);
                (measure(false), candidate)
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
            "METRIC authorization_action_baseline_per_second={:.3}",
            baseline_rates[median]
        );
        println!(
            "METRIC authorization_action_candidate_per_second={:.3}",
            candidate_rates[median]
        );
        println!(
            "METRIC authorization_action_speedup_ratio={:.6}",
            speedups[median]
        );
    }
}
