//! Cross-verb helpers: workspace target lookup and cache-state
//! rendering. These are tiny on their own; the value is forcing every
//! verb through one shape so adding a new verb doesn't reinvent the
//! same boilerplate slightly differently.

use std::path::Path;

use anyhow::{anyhow, Context, Result};
use once_core::CacheState;
use once_frontend::Target;

/// Load every target declared in the workspace and pick the one whose
/// id matches `target_id`. Returns an error if the workspace fails to
/// load or no target has the requested id. Verbs that operate on a
/// single target funnel through this so the error wording is uniform.
pub fn find_target(workspace: &Path, target_id: &str) -> Result<(Vec<Target>, usize)> {
    let targets = once_frontend::load_workspace(workspace).context("loading workspace")?;
    let idx = targets
        .iter()
        .position(|t| t.id() == target_id)
        .ok_or_else(|| anyhow!("no target matches `{target_id}`"))?;
    Ok((targets, idx))
}

/// The short string Once prints for a [`CacheState`]. Repeated
/// in every verb that emits structured output, so it lives here to
/// keep the spelling uniform (`hit` / `miss`, no trailing space).
#[must_use]
pub fn cache_tag(cache: CacheState) -> &'static str {
    match cache {
        CacheState::Hit => "hit",
        CacheState::Miss => "miss",
    }
}

#[must_use]
pub fn relative_path(from: &str, to: &str) -> String {
    if from.is_empty() {
        return to.to_string();
    }
    let from_parts = from
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let to_parts = to
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let mut shared = 0;
    while shared < from_parts.len()
        && shared < to_parts.len()
        && from_parts[shared] == to_parts[shared]
    {
        shared += 1;
    }

    let mut parts = Vec::new();
    for _ in shared..from_parts.len() {
        parts.push("..".to_string());
    }
    for part in &to_parts[shared..] {
        parts.push((*part).to_string());
    }
    if parts.is_empty() {
        ".".to_string()
    } else {
        parts.join("/")
    }
}
