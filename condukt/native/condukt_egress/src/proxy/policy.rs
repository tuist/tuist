//! Sidecar-side mirror of `Condukt.Sandbox.NetworkPolicy`.
//!
//! The BEAM authors the policy and bakes it into the pod as a JSON
//! file at `/etc/condukt/policy.json`. The sidecar reads it once at
//! startup, holds it in memory for the lifetime of the session, and
//! evaluates every connection against it.
//!
//! The shape is a Plug-style pipeline. `rules` is an ordered list
//! where each entry either short-circuits with `allow` / `deny` or
//! returns `continue` and lets the next rule run. If every rule
//! continues, `default` fires.
//!
//! Three rule types are sidecar-evaluable today:
//!
//!   * `allow` matches against a host glob list, allow on hit.
//!   * `deny` matches against a host glob list, deny on hit.
//!   * `decide` defers to the BEAM via the control channel.
//!
//! Policy is immutable once the pod starts.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct Policy {
    #[serde(default)]
    pub rules: Vec<Rule>,

    #[serde(default = "default_deny")]
    pub default: Action,

    #[serde(default)]
    pub redact: Vec<String>,

    #[serde(default = "default_max_body_capture")]
    pub max_body_capture: usize,

    /// Maximum time (milliseconds) the sidecar waits for a `decision`
    /// reply from the BEAM when a `decide` rule fires. Mirrors
    /// `Condukt.Sandbox.NetworkPolicy.decide_timeout`.
    #[serde(default = "default_decide_timeout_ms")]
    pub decide_timeout_ms: u64,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum Rule {
    Allow {
        #[serde(default)]
        hosts: Vec<String>,
    },
    Deny {
        #[serde(default)]
        hosts: Vec<String>,
    },
    Decide,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Default)]
#[serde(rename_all = "lowercase")]
pub enum Action {
    Allow,
    #[default]
    Deny,
}

fn default_deny() -> Action {
    Action::Deny
}

fn default_max_body_capture() -> usize {
    4096
}

fn default_decide_timeout_ms() -> u64 {
    5_000
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    /// Static rule said allow.
    Allow,
    /// Static rule (or default) said deny, with a stable reason label.
    Deny(DenyReason),
    /// A `decide` rule fired; the sidecar should round-trip to the
    /// BEAM and use whatever decision comes back.
    Decide,
}

/// Provenance for a decision: which entry in the rule list produced
/// it. Travels on the event so the BEAM can attribute allows/denies to
/// a specific rule. The default action carries no matched rule.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MatchedRule {
    pub index: usize,
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DenyReason {
    MatchedDenyList,
    DefaultDeny,
}

impl DenyReason {
    pub fn as_str(&self) -> &'static str {
        match self {
            DenyReason::MatchedDenyList => "matched_deny_list",
            DenyReason::DefaultDeny => "default_deny",
        }
    }
}

impl Policy {
    /// Walk the rule pipeline against a hostname. Mirrors the BEAM-side
    /// `Condukt.Sandbox.NetworkPolicy.evaluate/3` for the host-only
    /// rules. Returns the first non-`continue` outcome, or the default
    /// action if every rule passes.
    pub fn evaluate(&self, host: &str) -> (Decision, Option<MatchedRule>) {
        let host_lc = host.to_ascii_lowercase();

        for (index, rule) in self.rules.iter().enumerate() {
            match rule {
                Rule::Allow { hosts } => {
                    if matches_any(&host_lc, hosts) {
                        return (Decision::Allow, Some(matched(index, "allow")));
                    }
                }
                Rule::Deny { hosts } => {
                    if matches_any(&host_lc, hosts) {
                        return (
                            Decision::Deny(DenyReason::MatchedDenyList),
                            Some(matched(index, "deny")),
                        );
                    }
                }
                Rule::Decide => {
                    return (Decision::Decide, Some(matched(index, "decide")));
                }
            }
        }

        let decision = match self.default {
            Action::Allow => Decision::Allow,
            Action::Deny => Decision::Deny(DenyReason::DefaultDeny),
        };
        (decision, None)
    }
}

fn matched(index: usize, kind: &str) -> MatchedRule {
    MatchedRule {
        index,
        kind: kind.to_string(),
    }
}

fn matches_any(host: &str, patterns: &[String]) -> bool {
    patterns.iter().any(|p| matches_one(host, p))
}

fn matches_one(host: &str, pattern: &str) -> bool {
    let pattern = pattern.to_ascii_lowercase();
    let tokens = compile(&pattern);
    match_tokens(&tokens, host)
}

fn compile(pattern: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let chars: Vec<char> = pattern.chars().collect();
    let mut i = 0;
    let mut literal = String::new();

    while i < chars.len() {
        if chars[i] == '*' {
            if !literal.is_empty() {
                tokens.push(Token::Literal(literal.clone()));
                literal.clear();
            }
            if i + 1 < chars.len() && chars[i + 1] == '*' {
                tokens.push(Token::DoubleStar);
                i += 2;
            } else {
                tokens.push(Token::Star);
                i += 1;
            }
        } else {
            literal.push(chars[i]);
            i += 1;
        }
    }
    if !literal.is_empty() {
        tokens.push(Token::Literal(literal));
    }

    tokens
}

#[derive(Debug, Clone)]
enum Token {
    Literal(String),
    Star,
    DoubleStar,
}

fn match_tokens(tokens: &[Token], input: &str) -> bool {
    match tokens.split_first() {
        None => input.is_empty(),
        Some((Token::Literal(lit), rest)) => {
            if let Some(remaining) = input.strip_prefix(lit.as_str()) {
                match_tokens(rest, remaining)
            } else {
                false
            }
        }
        Some((Token::Star, rest)) => {
            for (idx, ch) in input.char_indices() {
                if ch == '.' {
                    if idx == 0 {
                        return false;
                    }
                    return match_tokens(rest, &input[idx..]);
                }
            }
            if input.is_empty() {
                false
            } else {
                match_tokens(rest, "")
            }
        }
        Some((Token::DoubleStar, rest)) => {
            if input.is_empty() {
                return false;
            }
            for (idx, _) in input.char_indices().skip(1) {
                if match_tokens(rest, &input[idx..]) {
                    return true;
                }
            }
            match_tokens(rest, "")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(rules: Vec<Rule>, default: Action) -> Policy {
        Policy {
            rules,
            default,
            redact: vec![],
            max_body_capture: 4096,
            decide_timeout_ms: 5_000,
        }
    }

    #[test]
    fn allow_hosts_short_circuits() {
        let policy = p(
            vec![Rule::Allow {
                hosts: vec!["api.github.com".into()],
            }],
            Action::Deny,
        );
        let (decision, matched) = policy.evaluate("api.github.com");
        assert_eq!(decision, Decision::Allow);
        assert_eq!(
            matched,
            Some(MatchedRule {
                index: 0,
                kind: "allow".into()
            })
        );
    }

    #[test]
    fn deny_hosts_short_circuits() {
        let policy = p(
            vec![Rule::Deny {
                hosts: vec!["secret.example.com".into()],
            }],
            Action::Deny,
        );
        let (decision, matched) = policy.evaluate("secret.example.com");
        assert_eq!(decision, Decision::Deny(DenyReason::MatchedDenyList));
        assert_eq!(matched.unwrap().kind, "deny");
    }

    #[test]
    fn order_matters() {
        let deny_first = p(
            vec![
                Rule::Deny {
                    hosts: vec!["evil.com".into()],
                },
                Rule::Allow {
                    hosts: vec!["evil.com".into()],
                },
            ],
            Action::Allow,
        );
        let (decision, matched) = deny_first.evaluate("evil.com");
        assert_eq!(decision, Decision::Deny(DenyReason::MatchedDenyList));
        assert_eq!(matched.unwrap().index, 0);

        let allow_first = p(
            vec![
                Rule::Allow {
                    hosts: vec!["evil.com".into()],
                },
                Rule::Deny {
                    hosts: vec!["evil.com".into()],
                },
            ],
            Action::Deny,
        );
        assert_eq!(allow_first.evaluate("evil.com").0, Decision::Allow);
    }

    #[test]
    fn decide_rule_returns_decide_variant() {
        let policy = p(vec![Rule::Decide], Action::Deny);
        let (decision, matched) = policy.evaluate("anything.com");
        assert_eq!(decision, Decision::Decide);
        assert_eq!(matched.unwrap().kind, "decide");
    }

    #[test]
    fn allow_hosts_before_decide_short_circuits_the_round_trip() {
        let policy = p(
            vec![
                Rule::Allow {
                    hosts: vec!["api.github.com".into()],
                },
                Rule::Decide,
            ],
            Action::Deny,
        );
        assert_eq!(policy.evaluate("api.github.com").0, Decision::Allow);
        let (decision, matched) = policy.evaluate("evil.com");
        assert_eq!(decision, Decision::Decide);
        assert_eq!(matched.unwrap().index, 1);
    }

    #[test]
    fn default_fires_with_no_matched_rule() {
        let policy_deny = p(vec![], Action::Deny);
        let (decision, matched) = policy_deny.evaluate("anything.com");
        assert_eq!(decision, Decision::Deny(DenyReason::DefaultDeny));
        assert_eq!(matched, None);

        let policy_allow = p(vec![], Action::Allow);
        assert_eq!(policy_allow.evaluate("anything.com").0, Decision::Allow);
    }

    #[test]
    fn parses_wire_format() {
        let json = r#"{
          "rules": [
            {"type": "deny", "hosts": ["evil.com"]},
            {"type": "allow", "hosts": ["api.github.com"]},
            {"type": "decide"}
          ],
          "default": "deny",
          "decide_timeout_ms": 5000
        }"#;
        let policy: Policy = serde_json::from_str(json).unwrap();
        assert_eq!(policy.rules.len(), 3);
        assert_eq!(policy.default, Action::Deny);
        assert_eq!(policy.decide_timeout_ms, 5_000);
    }
}
