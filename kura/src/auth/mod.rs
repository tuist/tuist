//! Deciding whether a cache request is allowed.
//!
//! A request arrives with a token. Where the token can answer for itself the
//! decision is made here and never leaves the node; where it cannot, Tuist's
//! server is asked. Both answers are cached per credentials.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub mod config;
pub mod engine;
pub mod grants;
pub mod policy;
#[cfg(test)]
mod policy_tests;
pub mod target;
pub mod tuist;

pub use engine::{AuthEngine, SharedAuth};

/// Who a request is from, and what they hold. `attributes` carries the cache
/// grants and the handles they flatten to.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Principal {
    pub id: String,
    pub kind: String,
    #[serde(default)]
    pub attributes: Value,
}

/// What a request is asking for, as the transports describe it. Both HTTP and
/// gRPC fill this in before authorization sees the request.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RequestContext {
    pub transport: String,
    pub route: String,
    pub method: String,
    pub operation: String,
    pub server_tenant_id: String,
    pub tenant_id: Option<String>,
    pub namespace_id: Option<String>,
    pub producer: Option<String>,
    pub artifact_key: Option<String>,
    pub artifact_hash: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default)]
    pub query: BTreeMap<String, String>,
    pub status_code: Option<u16>,
}

#[derive(Clone, Debug)]
pub enum AccessDecision {
    Allow,
    Deny(DenyDecision),
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DenyDecision {
    pub status: u16,
    pub message: String,
}
