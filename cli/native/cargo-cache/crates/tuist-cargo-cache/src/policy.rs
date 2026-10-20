//! What the surrounding context permits, whatever the configuration asks for.
//!
//! Cache writes are only trusted from a CI context that a pull request cannot
//! influence, so untrusted contexts read the remote cache but never publish to
//! it. CI uses shared actions by default; eager incremental reuse is an explicit
//! opt-in for both local builds and persistent runners.

use tuist_cargo_cache_core::RemoteCacheMode;

/// Whether output is being read in a CI job rather than on a developer's machine.
pub(crate) fn is_ci() -> bool {
    env_truthy(std::env::var("CI").ok()) || env_truthy(std::env::var("GITHUB_ACTIONS").ok())
}

/// Resolve the remote-cache mode that is actually permitted here.
///
/// Returns `None` when the configured mode leaves nothing to do.
pub fn effective_remote_cache_mode(configured: RemoteCacheMode) -> Option<RemoteCacheMode> {
    effective_remote_cache_mode_with(configured, |name| std::env::var(name).ok())
}

fn effective_remote_cache_mode_with(
    configured: RemoteCacheMode,
    get_env: impl Fn(&str) -> Option<String>,
) -> Option<RemoteCacheMode> {
    if trusted_cache_writer(&get_env) {
        return Some(configured);
    }
    match configured {
        RemoteCacheMode::ReadWrite | RemoteCacheMode::ReadOnly => Some(RemoteCacheMode::ReadOnly),
        RemoteCacheMode::WriteOnly => None,
    }
}

/// Whether incremental compilation is worth allowing here.
///
/// This Cargo-managed mode stays disabled in CI: a fresh runner
/// starts with no incremental state to build on, and an incrementally built
/// member emits a different rlib than a cached one, so every crate above it in
/// the graph misses. Eager incremental reuse has a separate opt-in policy.
pub fn incremental_allowed(configured: bool) -> bool {
    incremental_allowed_with(configured, |name| std::env::var(name).ok())
}

fn incremental_allowed_with(configured: bool, get_env: impl Fn(&str) -> Option<String>) -> bool {
    configured && !env_truthy(get_env("CI"))
}

/// Whether a crate that keeps missing with changed content may compile with its
/// own incremental state.
///
/// CI is excluded for the same reason as [`incremental_allowed`]: a fresh runner
/// has no state to reuse, so the trade is all cost and no saving.
pub fn learned_incremental_allowed(configured: bool) -> bool {
    learned_incremental_allowed_with(configured, |name| std::env::var(name).ok())
}

fn learned_incremental_allowed_with(
    configured: bool,
    get_env: impl Fn(&str) -> Option<String>,
) -> bool {
    configured && !env_truthy(get_env("CI"))
}

fn trusted_cache_writer(get_env: &impl Fn(&str) -> Option<String>) -> bool {
    if env_truthy(get_env("GITHUB_ACTIONS")) {
        return get_env("GITHUB_EVENT_NAME").as_deref() == Some("push")
            && get_env("GITHUB_REF_TYPE").as_deref() == Some("branch")
            && env_truthy(get_env("GITHUB_REF_PROTECTED"));
    }
    if env_truthy(get_env("GITLAB_CI")) {
        return get_env("CI_PIPELINE_SOURCE").as_deref() == Some("push")
            && get_env("CI_COMMIT_TAG").is_none()
            && get_env("CI_MERGE_REQUEST_IID").is_none()
            && env_truthy(get_env("CI_COMMIT_REF_PROTECTED"));
    }
    false
}

fn env_truthy(value: Option<String>) -> bool {
    value.is_some_and(|value| matches!(value.to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn env(values: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> + use<> {
        let values: HashMap<String, String> = values
            .iter()
            .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
            .collect();
        move |name: &str| values.get(name).cloned()
    }

    #[test]
    fn untrusted_contexts_only_read() {
        let local = env(&[]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &local),
            Some(RemoteCacheMode::ReadOnly)
        );
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::WriteOnly, &local),
            None
        );
    }

    #[test]
    fn protected_branch_pushes_may_write() {
        let ci = env(&[
            ("GITHUB_ACTIONS", "true"),
            ("GITHUB_EVENT_NAME", "push"),
            ("GITHUB_REF_TYPE", "branch"),
            ("GITHUB_REF_PROTECTED", "true"),
        ]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &ci),
            Some(RemoteCacheMode::ReadWrite)
        );
    }

    #[test]
    fn pull_requests_may_not_write() {
        let pull_request = env(&[
            ("GITHUB_ACTIONS", "true"),
            ("GITHUB_EVENT_NAME", "pull_request"),
            ("GITHUB_REF_TYPE", "branch"),
            ("GITHUB_REF_PROTECTED", "true"),
        ]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &pull_request),
            Some(RemoteCacheMode::ReadOnly)
        );
    }

    #[test]
    fn merge_requests_may_not_write() {
        let merge_request = env(&[
            ("GITLAB_CI", "true"),
            ("CI_PIPELINE_SOURCE", "push"),
            ("CI_MERGE_REQUEST_IID", "7"),
            ("CI_COMMIT_REF_PROTECTED", "true"),
        ]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &merge_request),
            Some(RemoteCacheMode::ReadOnly)
        );
    }

    #[test]
    fn release_markers_do_not_disable_the_cache() {
        let release = env(&[
            ("TUIST_CARGO_CACHE_RELEASE", "1"),
            ("GITHUB_ACTIONS", "true"),
            ("GITHUB_EVENT_NAME", "push"),
            ("GITHUB_REF_TYPE", "branch"),
            ("GITHUB_REF_PROTECTED", "true"),
        ]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &release),
            Some(RemoteCacheMode::ReadWrite)
        );

        let tag = env(&[
            ("GITHUB_ACTIONS", "true"),
            ("GITHUB_EVENT_NAME", "push"),
            ("GITHUB_REF_TYPE", "tag"),
        ]);
        assert_eq!(
            effective_remote_cache_mode_with(RemoteCacheMode::ReadWrite, &tag),
            Some(RemoteCacheMode::ReadOnly)
        );
    }

    #[test]
    fn ci_never_compiles_incrementally() {
        assert!(!incremental_allowed_with(true, env(&[("CI", "true")])));
        assert!(incremental_allowed_with(true, env(&[])));
        assert!(!incremental_allowed_with(false, env(&[])));
    }

    #[test]
    fn ci_never_learns_to_compile_incrementally() {
        assert!(!learned_incremental_allowed_with(
            true,
            env(&[("CI", "true")])
        ));
        assert!(learned_incremental_allowed_with(true, env(&[])));
        assert!(!learned_incremental_allowed_with(false, env(&[])));
    }
}
