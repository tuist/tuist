//! Deciding whether a cache request is allowed.
//!
//! A request arrives with a token. Where the token can answer for itself the
//! decision is made here and never leaves the node; where it cannot, Tuist's
//! server is asked. Both answers are cached per credentials.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

pub mod config;
pub mod engine;
pub mod grants;
pub mod policy;
#[cfg(test)]
mod policy_tests;
pub mod target;
pub mod tuist;

pub use engine::{AuthEngine, SharedAuth};

/// What a credential may do to one target, as one ordered level.
///
/// Ordered because write implies read: a request is allowed when the level is
/// at least what its action needs, so the level confirmed for a read also
/// answers the write the build issues next, and the other way round. The two
/// refusals are kept apart because they replay differently: `Invalid` is a 401
/// about the credential itself, `Refused` a 403 about this one target.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Access {
    /// The server said the credential itself is invalid or expired.
    Invalid,
    /// The credential is valid but does not reach this target.
    Refused,
    /// The credential would reach this target, but the account's plan has
    /// exhausted its free tier. Ordered above `Refused` so the introspection
    /// floor still only ever rises, and below `Read` so it grants nothing.
    PaymentRequired,
    Read,
    ReadWrite,
}

impl Access {
    /// The level an action needs.
    pub fn required(action: &target::Action) -> Self {
        match action {
            target::Action::Read => Self::Read,
            target::Action::Write => Self::ReadWrite,
        }
    }
}

/// What a request is asking for, as the transports describe it. Both HTTP and
/// gRPC fill this in before authorization sees the request.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RequestContext {
    pub transport: String,
    pub method: String,
    pub operation: String,
    pub server_tenant_id: String,
    pub tenant_id: Option<String>,
    pub namespace_id: Option<String>,
    #[serde(default)]
    pub authorization: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default)]
    pub query: BTreeMap<String, String>,
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
