use super::{MAX_TASK_ACTION_PREDICTIONS, TASK_ACTION_MANIFEST_VERSION};
use crate::{ActionPrediction, CacheDigest, TaskActionManifest};
use eyre::{Context, Result, bail};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

/// Whether `task` is a well-formed task action identity.
///
/// Identities name files and directories in the store, so anything that reads
/// the store back has to be able to tell an identity from whatever else a user
/// left lying there.
pub fn is_task_identity(task: &str) -> bool {
    task.len() == 64
        && task
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

pub(super) fn validate_task_identity(task: &str) -> Result<()> {
    if !is_task_identity(task) {
        bail!("invalid task action identity");
    }
    Ok(())
}

/// Where a store keeps its task prediction manifests.
pub(super) fn task_manifest_dir(store: &Path) -> PathBuf {
    store.join("task-manifests").join("v1")
}

/// The action digests a task's prediction manifest recorded.
///
/// Read straight off disk rather than through an agent, because a collector
/// needs the action set of tasks no session is running. A manifest that is
/// missing or no longer parseable yields no actions rather than an error: this
/// is a prediction index, so the worst a thin answer costs is a cold prefetch,
/// or an object collected earlier than it deserved.
pub fn task_manifest_actions(store: &Path, task: &str) -> Result<Vec<CacheDigest>> {
    validate_task_identity(task)?;
    let path = task_manifest_dir(store).join(format!("{task}.json"));
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
        }
    };
    let Ok(manifest) = serde_json::from_slice::<TaskActionManifest>(&bytes) else {
        return Ok(Vec::new());
    };
    if validate_task_manifest(&manifest, task).is_err() {
        return Ok(Vec::new());
    }
    Ok(manifest
        .predictions
        .into_iter()
        .map(|prediction| prediction.action)
        .collect())
}

pub(super) fn validate_task_manifest(manifest: &TaskActionManifest, task: &str) -> Result<()> {
    if manifest.task == task && manifest.validate() {
        Ok(())
    } else {
        bail!("invalid task action manifest")
    }
}

/// Refresh preferred values at the back of the durable LRU, then retire the
/// oldest unprotected history needed to keep the manifest bounded.
pub(super) fn update_task_predictions(
    predictions: Vec<ActionPrediction>,
    updates: &BTreeMap<CacheDigest, ActionPrediction>,
    protected: &BTreeSet<CacheDigest>,
) -> Result<Vec<ActionPrediction>> {
    update_task_predictions_in_order(predictions, updates.values().cloned().collect(), protected)
}

/// Append ordered task prediction updates and keep the manifest bounded.
///
/// `predictions` and `updates` are ordered from oldest to newest. An update
/// replaces any existing prediction for the same invocation and keeps the
/// update's position in the supplied order. If `updates` repeats an invocation,
/// its last value and position win. Invocations in `protected` are not retired;
/// protecting more entries than the manifest limit returns an error.
pub fn update_task_predictions_in_order(
    predictions: Vec<ActionPrediction>,
    mut updates: Vec<ActionPrediction>,
    protected: &BTreeSet<CacheDigest>,
) -> Result<Vec<ActionPrediction>> {
    if protected.len() > MAX_TASK_ACTION_PREDICTIONS {
        bail!("this task run contains too many action predictions");
    }
    let mut update_invocations = BTreeSet::new();
    updates = updates
        .into_iter()
        .rev()
        .filter(|prediction| update_invocations.insert(prediction.invocation.clone()))
        .collect();
    updates.reverse();
    let mut predictions: Vec<_> = predictions
        .into_iter()
        .filter(|prediction| !update_invocations.contains(&prediction.invocation))
        .collect();
    predictions.extend(updates);
    let mut excess = predictions
        .len()
        .saturating_sub(MAX_TASK_ACTION_PREDICTIONS);
    let mut kept = Vec::with_capacity(predictions.len() - excess);
    for prediction in predictions {
        if excess > 0 && !protected.contains(&prediction.invocation) {
            excess -= 1;
        } else {
            kept.push(prediction);
        }
    }
    Ok(kept)
}

/// Merge two manifest snapshots through the same bounded durable-LRU rule.
///
/// `required` values from the update side win over the base. `fallbacks` win
/// only when the base has no newer value for the invocation. Other overlap is
/// inherited from the base, while update-only history remains eligible for
/// pruning before either kind of preferred value.
pub(super) fn merge_task_manifests(
    task: &str,
    base: TaskActionManifest,
    update: TaskActionManifest,
    required: &BTreeSet<CacheDigest>,
    fallbacks: &BTreeSet<CacheDigest>,
) -> Result<TaskActionManifest> {
    validate_task_manifest(&base, task)?;
    validate_task_manifest(&update, task)?;
    let base_predictions: BTreeMap<_, _> = base
        .predictions
        .iter()
        .map(|prediction| (&prediction.invocation, prediction))
        .collect();
    let updates: Vec<_> = update
        .predictions
        .iter()
        .filter(|prediction| {
            required.contains(&prediction.invocation)
                || (fallbacks.contains(&prediction.invocation)
                    && base_predictions
                        .get(&prediction.invocation)
                        .is_none_or(|base| *base == *prediction))
        })
        .cloned()
        .collect();
    let protected = required
        .iter()
        .cloned()
        .chain(
            updates
                .iter()
                .map(|prediction| prediction.invocation.clone()),
        )
        .collect();
    let mut predictions: Vec<_> = update
        .predictions
        .into_iter()
        .filter(|prediction| !base_predictions.contains_key(&prediction.invocation))
        .collect();
    predictions.extend(base.predictions);
    let predictions = update_task_predictions_in_order(predictions, updates, &protected)?;
    let manifest = TaskActionManifest {
        version: TASK_ACTION_MANIFEST_VERSION,
        task: task.to_owned(),
        predictions,
    };
    validate_task_manifest(&manifest, task)?;
    Ok(manifest)
}
