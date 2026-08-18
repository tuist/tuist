//! The cache grants a token or an introspection response carries, and whether
//! they cover a request.
//!
//! Tuist's server mints these and this reads them back, so the shape is a type
//! rather than a set of map lookups: the two sides agree by convention, and a
//! type is where that convention is written down on this side.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::target::{Action, RequestTarget, Scope};
use crate::auth::Access;

/// Handles are compared lowercased, and an empty handle is treated as absent,
/// matching what the server writes.
fn normalized_handles(value: Option<&Value>) -> Vec<String> {
    let Some(Value::Array(items)) = value else {
        return Vec::new();
    };

    items
        .iter()
        .filter_map(Value::as_str)
        .map(str::trim)
        .filter(|handle| !handle.is_empty())
        .map(str::to_lowercase)
        .collect()
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GrantBucket {
    #[serde(default)]
    pub read: Vec<String>,
    #[serde(default)]
    pub write: Vec<String>,
}

impl GrantBucket {
    fn from_value(value: Option<&Value>) -> Self {
        Self {
            read: normalized_handles(value.and_then(|bucket| bucket.get("read"))),
            write: normalized_handles(value.and_then(|bucket| bucket.get("write"))),
        }
    }

    fn allows(&self, action: &Action, identifier: &str) -> bool {
        let granted = match action {
            Action::Read => &self.read,
            Action::Write => &self.write,
        };
        if granted.iter().any(|handle| handle == identifier) {
            return true;
        }
        // Write implies read, so a writer never has to be granted both.
        matches!(action, Action::Read) && self.write.iter().any(|handle| handle == identifier)
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CacheGrants {
    #[serde(default)]
    pub account: GrantBucket,
    #[serde(default)]
    pub project: GrantBucket,
}

impl CacheGrants {
    /// Reads the grants out of a JWT's claims or an introspection response.
    /// Absent or malformed grants read as empty rather than failing, so a token
    /// that predates them falls through to the paths that handle it.
    pub fn from_body(body: &Value) -> Self {
        Self::from_grants_value(body.get("cache_grants"))
    }

    /// The level these grants give one target: write implies read, so the
    /// answer is the highest action the buckets name it for.
    pub fn level(&self, target: &RequestTarget) -> Access {
        if self.allow(target, &Action::Write) {
            Access::ReadWrite
        } else if self.allow(target, &Action::Read) {
            Access::Read
        } else {
            Access::Refused
        }
    }

    fn from_grants_value(grants: Option<&Value>) -> Self {
        Self {
            account: GrantBucket::from_value(grants.and_then(|grants| grants.get("account"))),
            project: GrantBucket::from_value(grants.and_then(|grants| grants.get("project"))),
        }
    }

    fn bucket(&self, scope: &Scope) -> &GrantBucket {
        match scope {
            Scope::Account => &self.account,
            Scope::Project => &self.project,
        }
    }

    /// A request naming no project is authorized against the account bucket
    /// alone, and one naming a project against the project bucket alone. There
    /// is deliberately no fallback between them: an account grant is access to
    /// the account's own cache, not to every project in it.
    pub fn allow(&self, target: &RequestTarget, action: &Action) -> bool {
        self.bucket(&target.scope)
            .allows(action, &target.identifier)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::auth::target::RequestTarget;

    fn target(scope: Scope, identifier: &str) -> RequestTarget {
        RequestTarget {
            scope,
            account: "acme".into(),
            namespace: None,
            identifier: identifier.into(),
        }
    }

    #[test]
    fn reads_the_grants_the_server_writes() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": {
                "account": { "read": ["acme"], "write": [] },
                "project": { "read": ["acme/ios"], "write": ["acme/ios"] },
            }
        }));

        assert_eq!(grants.account.read, vec!["acme"]);
        assert_eq!(grants.project.write, vec!["acme/ios"]);
    }

    #[test]
    fn absent_or_malformed_grants_grant_nothing() {
        for body in [
            json!({}),
            json!({ "cache_grants": null }),
            json!({ "cache_grants": { "project": 7 } }),
        ] {
            let grants = CacheGrants::from_body(&body);

            assert!(!grants.allow(&target(Scope::Project, "acme/ios"), &Action::Read));
            assert!(!grants.allow(&target(Scope::Account, "acme"), &Action::Read));
            assert_eq!(
                grants.level(&target(Scope::Project, "acme/ios")),
                Access::Refused
            );
        }
    }

    #[test]
    fn compares_handles_lowercased_and_drops_empty_ones() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": { "project": { "read": ["ACME/iOS", "", "  "] } }
        }));

        assert_eq!(grants.project.read, vec!["acme/ios"]);
        assert!(grants.allow(&target(Scope::Project, "acme/ios"), &Action::Read));
    }

    #[test]
    fn lets_a_writer_read_without_being_granted_both() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": { "project": { "write": ["acme/ios"] } }
        }));

        assert!(grants.allow(&target(Scope::Project, "acme/ios"), &Action::Read));
        assert!(grants.allow(&target(Scope::Project, "acme/ios"), &Action::Write));
    }

    #[test]
    fn does_not_let_a_reader_write() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": { "project": { "read": ["acme/ios"] } }
        }));

        assert!(!grants.allow(&target(Scope::Project, "acme/ios"), &Action::Write));
    }

    // The buckets answer different questions, so neither stands in for the
    // other: an account grant is the account's own cache, not its projects'.
    #[test]
    fn does_not_cross_between_the_account_and_project_buckets() {
        let account_only = CacheGrants::from_body(&json!({
            "cache_grants": { "account": { "write": ["acme"] } }
        }));
        assert!(!account_only.allow(&target(Scope::Project, "acme/ios"), &Action::Read));

        let project_only = CacheGrants::from_body(&json!({
            "cache_grants": { "project": { "write": ["acme/ios"] } }
        }));
        assert!(!project_only.allow(&target(Scope::Account, "acme"), &Action::Read));
    }

    // The level is the highest action the buckets name the target for, which
    // is the ordered form of the two `allow` rules above.
    #[test]
    fn the_level_is_the_highest_action_granted() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": {
                "project": { "read": ["acme/web"], "write": ["acme/ios"] }
            }
        }));

        assert_eq!(
            grants.level(&target(Scope::Project, "acme/ios")),
            Access::ReadWrite
        );
        assert_eq!(
            grants.level(&target(Scope::Project, "acme/web")),
            Access::Read
        );
        assert_eq!(
            grants.level(&target(Scope::Project, "acme/api")),
            Access::Refused
        );
    }
}
