//! Wire format for messages between the sidecar and the BEAM-side
//! `Condukt.Sandbox.NetworkPolicy.K8s.ControlBridge`. NDJSON, one frame per
//! line. Tagged with `"type"` so the channel can carry multiple
//! message kinds without ambiguity.
//!
//! Frame kinds:
//!
//!   * `event` — sidecar -> BEAM. A `Condukt.Sandbox.NetworkPolicy.Event`
//!     wrapping a request's lifecycle step.
//!   * `decision_request` — sidecar -> BEAM. Asks the BEAM to make a
//!     policy decision about a request the sidecar is about to
//!     forward. The sidecar holds the connection until a `decision`
//!     comes back (or its `decide_timeout` fires).
//!   * `decision` — BEAM -> sidecar. The decision the sidecar was
//!     waiting on, keyed by `id`.

use crate::proxy::policy::MatchedRule;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::net::SocketAddr;

#[allow(clippy::enum_variant_names)]
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    RequestOpened,
    RequestClosed,
    RequestAllowed,
    RequestDenied,
    /// The request was allowed but never completed cleanly: the
    /// workspace rejected the session CA, the upstream was
    /// unreachable, or the stream broke mid-flight. Carries the
    /// failure label in `reason`.
    RequestFailed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub id: String,
    pub session_id: Option<String>,
    pub host: String,
    pub port: u16,
    pub remote_addr: Option<String>,
    pub scheme: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub method: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request_headers: Option<HashMap<String, String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub response_status: Option<i32>,
    #[serde(default)]
    pub bytes_in: u64,
    #[serde(default)]
    pub bytes_out: u64,
    pub started_at: DateTime<Utc>,
    pub finished_at: Option<DateTime<Utc>>,
}

impl Request {
    pub fn new(
        host: String,
        port: u16,
        remote: Option<SocketAddr>,
        session_id: Option<String>,
    ) -> Self {
        Request {
            id: uuid::Uuid::new_v4().to_string(),
            session_id,
            host,
            port,
            remote_addr: remote.map(|a| a.to_string()),
            scheme: if port == 443 {
                "https".into()
            } else {
                "http".into()
            },
            method: None,
            path: None,
            request_headers: None,
            response_status: None,
            bytes_in: 0,
            bytes_out: 0,
            started_at: Utc::now(),
            finished_at: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub kind: Kind,
    pub request: Request,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    /// Which policy rule produced an allow/deny decision (index into
    /// the rule list plus its kind). Absent for the default action and
    /// for lifecycle-only events.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub matched_rule: Option<MatchedRule>,
    pub at: DateTime<Utc>,
}

impl Event {
    pub fn new(kind: Kind, request: Request) -> Self {
        Event {
            kind,
            request,
            reason: None,
            matched_rule: None,
            at: Utc::now(),
        }
    }

    pub fn with_reason(mut self, reason: impl Into<String>) -> Self {
        self.reason = Some(reason.into());
        self
    }

    pub fn with_matched_rule(mut self, rule: MatchedRule) -> Self {
        self.matched_rule = Some(rule);
        self
    }
}

/// Tagged outbound frame sent from the sidecar to the BEAM.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Outbound {
    Event(Box<Event>),
    DecisionRequest {
        id: String,
        session_id: Option<String>,
        host: String,
        port: u16,
        scheme: String,
    },
}

/// Tagged inbound frame received from the BEAM. Currently only
/// `decision` is meaningful; additional shapes can be added without
/// breaking existing senders thanks to `#[serde(other)]` on the
/// fallthrough variant.
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Inbound {
    Decision {
        id: String,
        action: DecisionAction,
        #[serde(default)]
        reason: Option<String>,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DecisionAction {
    Allow,
    Deny,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proxy::policy::MatchedRule;
    use serde_json::json;

    fn request() -> Request {
        Request::new("api.github.com".into(), 443, None, Some("s1".into()))
    }

    #[test]
    fn request_new_infers_scheme_from_port() {
        assert_eq!(request().scheme, "https");
        let http = Request::new("h".into(), 80, None, None);
        assert_eq!(http.scheme, "http");
        assert!(http.session_id.is_none());
    }

    #[test]
    fn outbound_event_is_tagged_and_snake_cased() {
        let ev = Event::new(Kind::RequestDenied, request())
            .with_reason("matched_deny_list")
            .with_matched_rule(MatchedRule {
                index: 1,
                kind: "deny".into(),
            });

        let v = serde_json::to_value(Outbound::Event(Box::new(ev))).unwrap();
        assert_eq!(v["type"], "event");
        assert_eq!(v["kind"], "request_denied");
        assert_eq!(v["reason"], "matched_deny_list");
        assert_eq!(v["matched_rule"]["index"], 1);
        assert_eq!(v["matched_rule"]["kind"], "deny");
        assert_eq!(v["request"]["host"], "api.github.com");
    }

    #[test]
    fn optional_fields_are_omitted_when_absent() {
        let v = serde_json::to_value(Outbound::Event(Box::new(Event::new(
            Kind::RequestOpened,
            request(),
        ))))
        .unwrap();

        assert!(v.get("reason").is_none());
        assert!(v.get("matched_rule").is_none());
        assert!(v["request"].get("method").is_none());
    }

    #[test]
    fn decision_request_is_tagged() {
        let v = serde_json::to_value(Outbound::DecisionRequest {
            id: "d1".into(),
            session_id: Some("s1".into()),
            host: "evil.com".into(),
            port: 443,
            scheme: "https".into(),
        })
        .unwrap();

        assert_eq!(v["type"], "decision_request");
        assert_eq!(v["id"], "d1");
        assert_eq!(v["host"], "evil.com");
    }

    #[test]
    fn inbound_decision_parses_action_and_optional_reason() {
        let parsed: Inbound =
            serde_json::from_value(json!({"type": "decision", "id": "d1", "action": "deny"}))
                .unwrap();

        match parsed {
            Inbound::Decision { id, action, reason } => {
                assert_eq!(id, "d1");
                assert_eq!(action, DecisionAction::Deny);
                assert!(reason.is_none());
            }
            other => panic!("expected Decision, got {other:?}"),
        }
    }

    #[test]
    fn unknown_inbound_type_falls_through_instead_of_erroring() {
        let parsed: Inbound =
            serde_json::from_value(json!({"type": "from_the_future", "x": 1})).unwrap();
        assert!(matches!(parsed, Inbound::Unknown));
    }
}
