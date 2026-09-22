//! Tool-environment selection.
//!
//! Cache keys are only honest if every environment variable an action
//! observes is part of the [`Action`](crate::Action). Plugins therefore
//! pick a small allowlist of variables to forward instead of inheriting
//! the parent environment wholesale. Doing the selection in one place
//! keeps the policy uniform across plugins: the same baseline keys,
//! with each plugin adding only the keys its toolchain genuinely needs.

use std::collections::BTreeMap;
use std::env;

mod mise;
mod path;

pub use mise::{workspace_tool, workspace_tool_env, workspace_tool_var, ToolEnvError};

/// Variables every spawned tool action wants regardless of toolchain.
/// `PATH` and `HOME` are universal; adding more here would silently
/// expand every plugin's cache key, so the list is kept deliberately
/// small.
const BASE_KEYS: &[&str] = &["PATH", "HOME"];

/// Build a tool environment for a spawned action.
///
/// Returns a deterministic map containing `PATH`, `HOME`, and every
/// `extra_keys` entry that is set in the parent environment. Pass
/// plugin-specific keys (e.g. `RUSTUP_TOOLCHAIN`, `DEVELOPER_DIR`)
/// through `extra_keys`. Duplicates between `BASE_KEYS` and
/// `extra_keys` are harmless.
pub fn tool_env(extra_keys: &[&str]) -> BTreeMap<String, String> {
    select_tool_env(env::vars(), extra_keys)
}

/// Pure selector used by [`tool_env`]; exposed so callers (and tests)
/// can drive the policy with an arbitrary iterator instead of the live
/// process environment.
pub fn select_tool_env<I>(vars: I, extra_keys: &[&str]) -> BTreeMap<String, String>
where
    I: IntoIterator<Item = (String, String)>,
{
    let mut allowed: Vec<&str> = BASE_KEYS.to_vec();
    allowed.extend(extra_keys.iter().copied());
    vars.into_iter()
        .filter(|(k, _)| allowed.contains(&k.as_str()))
        .collect()
}

fn select_extra_env(
    vars: &BTreeMap<String, String>,
    extra_keys: &[&str],
) -> BTreeMap<String, String> {
    extra_keys
        .iter()
        .filter_map(|key| {
            vars.get(*key)
                .map(|value| ((*key).to_string(), value.clone()))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn forwards_base_keys() {
        let env = select_tool_env(
            [
                ("PATH".into(), "/usr/bin".into()),
                ("HOME".into(), "/h".into()),
                ("UNRELATED".into(), "leak".into()),
            ],
            &[],
        );
        assert_eq!(env.get("PATH").map(String::as_str), Some("/usr/bin"));
        assert_eq!(env.get("HOME").map(String::as_str), Some("/h"));
        assert!(!env.contains_key("UNRELATED"));
    }

    #[test]
    fn extra_keys_are_admitted_when_present() {
        let env = select_tool_env(
            [
                ("PATH".into(), "/usr/bin".into()),
                ("RUSTUP_TOOLCHAIN".into(), "1.86.0".into()),
                ("CARGO_HOME".into(), "/c".into()),
                ("UNRELATED".into(), "leak".into()),
            ],
            &["RUSTUP_TOOLCHAIN", "CARGO_HOME"],
        );
        assert_eq!(
            env.get("RUSTUP_TOOLCHAIN").map(String::as_str),
            Some("1.86.0")
        );
        assert_eq!(env.get("CARGO_HOME").map(String::as_str), Some("/c"));
        assert!(!env.contains_key("UNRELATED"));
    }

    #[test]
    fn missing_extras_are_silently_dropped() {
        // An extra key is "include if set" - it is not an error for the
        // parent env to lack it.
        let env = select_tool_env(
            [("PATH".into(), "/usr/bin".into())],
            &["RUSTUP_TOOLCHAIN", "DEVELOPER_DIR"],
        );
        assert_eq!(env.len(), 1);
    }

    #[test]
    fn duplicate_extras_do_not_double_emit() {
        let env = select_tool_env(
            [
                ("PATH".into(), "/usr/bin".into()),
                ("HOME".into(), "/h".into()),
            ],
            &["PATH", "HOME"],
        );
        assert_eq!(env.len(), 2);
    }

    #[test]
    fn arbitrary_prefixed_keys_are_not_admitted() {
        // Earlier policy forwarded `MISE_*` verbatim; today actions
        // must declare every variable they depend on, no prefix
        // passthrough. This test pins the contract.
        let env = select_tool_env(
            [
                ("PATH".into(), "/usr/bin".into()),
                ("MISE_TRUSTED_CONFIG_PATHS".into(), "/ws".into()),
            ],
            &[],
        );
        assert_eq!(env.len(), 1);
        assert!(!env.contains_key("MISE_TRUSTED_CONFIG_PATHS"));
    }

    #[test]
    fn select_extra_env_does_not_forward_path() {
        let env = BTreeMap::from([
            ("PATH".to_string(), "/global".to_string()),
            ("RUSTUP_TOOLCHAIN".to_string(), "1.86.0".to_string()),
        ]);
        let selected = select_extra_env(&env, &["RUSTUP_TOOLCHAIN"]);
        assert_eq!(
            selected.get("RUSTUP_TOOLCHAIN").map(String::as_str),
            Some("1.86.0")
        );
        assert!(!selected.contains_key("PATH"));
    }
}
