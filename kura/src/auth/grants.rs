//! The cache grants a token or an introspection response carries, and whether
//! they cover a request.
//!
//! Tuist's server mints these and this reads them back, so the shape is a type
//! rather than a set of map lookups: the two sides agree by convention, and a
//! type is where that convention is written down on this side.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::target::{Action, RequestTarget, Scope};

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

fn absorb_handles(granted: &mut Vec<String>, incoming: &[String]) {
    for handle in incoming {
        if !granted.iter().any(|existing| existing == handle) {
            granted.push(handle.clone());
        }
    }
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

    /// Every handle this bucket mentions, reads first, without duplicates.
    fn flattened(&self) -> Vec<String> {
        let mut flattened: Vec<String> = Vec::new();
        for handle in self.read.iter().chain(self.write.iter()) {
            if !flattened.iter().any(|existing| existing == handle) {
                flattened.push(handle.clone());
            }
        }
        flattened
    }

    fn absorb(&mut self, other: &Self) {
        absorb_handles(&mut self.read, &other.read);
        absorb_handles(&mut self.write, &other.write);
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

    /// Reads the grants back off a principal, distinguishing a principal that
    /// carries none at all from one that carries empty ones. Only the former
    /// falls back to the legacy project handles: a principal that was built
    /// from grants has already had its say.
    pub fn from_principal_attributes(attributes: &Value) -> Option<Self> {
        match attributes.get("cache_grants") {
            None | Some(Value::Null) => None,
            grants => Some(Self::from_grants_value(grants)),
        }
    }

    /// The grants a principal authorizes with, in one shape.
    ///
    /// A principal built from the legacy route carries bare project handles and
    /// no grants, and `authorize` lets those handles allow any action on them.
    /// Reading them back as read and write grants preserves that exactly, and
    /// it is what lets an answer from one route be folded into an answer from
    /// the other. Account handles are deliberately not seeded: they authorize
    /// nothing on a handle-shaped principal today, and seeding them would widen
    /// what the legacy route granted.
    pub fn from_principal(attributes: &Value) -> Self {
        if let Some(grants) = Self::from_principal_attributes(attributes) {
            return grants;
        }

        let projects = normalized_handles(attributes.get("projects"));
        Self {
            account: GrantBucket::default(),
            project: GrantBucket {
                read: projects.clone(),
                write: projects,
            },
        }
    }

    /// Every handle either side grants, so a credential keeps what one route
    /// settled when the next answer comes from the other.
    pub fn merged(mut self, other: &Self) -> Self {
        self.account.absorb(&other.account);
        self.project.absorb(&other.project);
        self
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

    pub fn accounts(&self) -> Vec<String> {
        self.account.flattened()
    }

    pub fn projects(&self) -> Vec<String> {
        self.project.flattened()
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
        assert_eq!(grants.projects(), vec!["acme/ios"]);
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
            assert!(grants.projects().is_empty());
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

    #[test]
    fn flattens_reads_before_writes_without_duplicates() {
        let grants = CacheGrants::from_body(&json!({
            "cache_grants": {
                "project": { "read": ["acme/ios", "acme/web"], "write": ["acme/ios", "acme/api"] }
            }
        }));

        assert_eq!(grants.projects(), vec!["acme/ios", "acme/web", "acme/api"]);
    }
}
