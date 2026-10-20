//! Store inspection and garbage collection.
//!
//! The store holds six trees: `cas/v1` for content-addressed objects,
//! `action-results/v1` for the results that reference them, `task-manifests/v1`
//! for the prediction index, `checkouts/v1` for the checkouts that have built
//! each identity, `build-receipts/v1` for exact completed build closures, and
//! `sessions/v1` for per-build event streams. Only the first two are collected
//! for size; manifests and receipts are small, checkout records expire with
//! their checkout claims, and session streams are bounded by age and count
//! because they are history rather than cache content.

mod events;

use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tuist_cargo_cache_core::{
    ActionPrediction, CacheDigest, CacheDirectory, LocalCas, RemoteActionResult, RustcMetadata,
    TaskActionManifest, is_task_identity, merge_task_action_predictions, task_manifest_actions,
};

const CAS_DIR: &str = "cas/v1";
const ACTION_RESULTS_DIR: &str = "action-results/v1";
const CHECKOUTS_DIR: &str = "checkouts/v1";
const SWEEP_STAMP: &str = "gc/v1/last-sweep";
const SWEEP_LOCK: &str = "gc/v1/sweep.lock";
const CHECKOUT_RECORD_VERSION: u8 = 1;
const BUILD_RECEIPTS_DIR: &str = "build-receipts/v1";
const BUILD_RECEIPT_VERSION: u8 = 1;
const IMPORT_STAGING_DIR: &str = "import-staging";
const EXPORT_MANIFEST: &str = "tuist_cargo_cache-cache-export-v1.json";
const EXPORT_VERSION: u8 = 2;
const LEGACY_EXPORT_VERSION: u8 = 1;

const IMPORT_STAGING_RETENTION: Duration = Duration::from_secs(24 * 60 * 60);
const SESSION_RETENTION: Duration = Duration::from_secs(7 * 24 * 60 * 60);
const MAX_SESSIONS: usize = 256;

/// How long a checkout's claim outlives the last build that renewed it.
///
/// Existence alone is not enough to keep a claim alive. An identity covers one
/// exact command line against one exact lockfile, so a checkout that lives for
/// years accumulates an identity per lockfile it ever had -- and every one of
/// them would go on rooting the actions of a build nobody will run again.
/// Without this bound the rooted set only grows, until everything is rooted and
/// the ordering means nothing. A build renews the claims it uses, so anything
/// this stale belongs to a command that has moved on.
const CHECKOUT_RETENTION: Duration = Duration::from_secs(30 * 24 * 60 * 60);

#[derive(Debug, Default, PartialEq, Eq)]
pub struct StoreStats {
    pub objects: u64,
    pub object_bytes: u64,
    pub action_results: u64,
    pub action_result_bytes: u64,
    pub live_checkouts: u64,
    /// Claims that root nothing any more: a checkout that is gone, or one that
    /// is still there but has not renewed this claim inside the retention
    /// window. Reported as stale rather than gone because those are different
    /// things and only one of them means the directory is missing.
    pub stale_checkouts: u64,
}

impl StoreStats {
    pub fn total_bytes(&self) -> u64 {
        self.object_bytes.saturating_add(self.action_result_bytes)
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct GcOutcome {
    pub removed_objects: u64,
    pub removed_action_results: u64,
    pub removed_checkout_records: u64,
    /// Event streams dropped on age or count. These bytes are not included in
    /// `remaining_bytes` because session history is not cache content.
    pub removed_session_streams: u64,
    pub removed_bytes: u64,
    pub remaining_bytes: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ProjectUsage {
    pub workspace_root: PathBuf,
    pub identities: u64,
    pub action_bytes: u64,
    pub target_bytes: u64,
    pub live: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub struct LargestEntry {
    pub kind: &'static str,
    pub path: PathBuf,
    pub bytes: u64,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct VerifyOutcome {
    pub checked_objects: u64,
    pub checked_action_results: u64,
    pub problems: Vec<PathBuf>,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct RemoveProjectOutcome {
    pub removed_checkout_records: u64,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct TransferOutcome {
    pub actions: u64,
    pub objects: u64,
    pub bytes: u64,
}

/// A cache import together with named higher-level CAS roots it carried.
#[derive(Debug)]
#[non_exhaustive]
pub struct ImportOutcome {
    pub transfer: TransferOutcome,
    pub attachments: BTreeMap<String, CacheDigest>,
}

/// Extra CAS roots carried by a cache export for a higher-level transport.
#[derive(Debug, Default)]
pub struct ExportAdditions {
    /// Stable names by which the importer can discover selected objects.
    pub attachments: BTreeMap<String, CacheDigest>,
    /// Every object the attachments reach, including the named objects.
    pub objects: BTreeSet<CacheDigest>,
}

/// One Cargo workspace and the target directory recorded for its build.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct WorkspaceTarget {
    pub workspace_root: PathBuf,
    pub target_dir: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ExportManifest {
    version: u8,
    tasks: Vec<TaskActionManifest>,
    actions: Vec<CacheDigest>,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    attachments: BTreeMap<String, CacheDigest>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    objects: Vec<CacheDigest>,
}

/// The exact cache predictions completed by one top-level build command.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct BuildReceipt {
    version: u8,
    workspace_root: PathBuf,
    identity: String,
    completed_nanos: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    group: Option<String>,
    predictions: Vec<ActionPrediction>,
}

/// Record an exact completed build for checkout and grouped exports.
pub fn record_build_receipt(
    store: &Path,
    run: &str,
    identity: &str,
    workspace_root: &Path,
    group: Option<&str>,
    predictions: Vec<ActionPrediction>,
) -> Result<()> {
    if !is_task_identity(run) || !is_task_identity(identity) {
        eyre::bail!("invalid build receipt identity");
    }
    if !(TaskActionManifest {
        version: 1,
        task: identity.to_owned(),
        predictions: predictions.clone(),
    })
    .validate()
    {
        eyre::bail!("invalid build receipt prediction");
    }
    if let Some(group) = group {
        validate_export_group(group)?;
    }
    // A build that used exactly what the last one did leaves that receipt
    // standing. Only its timestamp would change, and the export it feeds
    // wants the prediction set, not the hour. A group receipt is per run and
    // always written.
    if group.is_none()
        && read_build_receipt(&latest_receipt_path(store, workspace_root)).is_some_and(|latest| {
            latest.identity == identity
                && latest.workspace_root == workspace_root
                && latest.group.is_none()
                && latest.predictions == predictions
        })
    {
        return Ok(());
    }
    let key = workspace_key(workspace_root);
    let lock_path = store
        .join(BUILD_RECEIPTS_DIR)
        .join("locks")
        .join(format!("{key}.lock"));
    std::fs::create_dir_all(lock_path.parent().expect("receipt lock has a parent"))?;
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;
    let completed_nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos().try_into().unwrap_or(u64::MAX))
        .unwrap_or_default();
    let receipt = BuildReceipt {
        version: BUILD_RECEIPT_VERSION,
        workspace_root: workspace_root.to_path_buf(),
        identity: identity.to_owned(),
        completed_nanos,
        group: group.map(str::to_owned),
        predictions,
    };
    let bytes = serde_json::to_vec(&receipt)?;
    write_atomic(&latest_receipt_path(store, workspace_root), &bytes)?;
    if let Some(group) = group {
        write_atomic(&group_receipt_path(store, group, run), &bytes)?;
    }
    Ok(())
}

fn workspace_key(workspace_root: &Path) -> String {
    CacheDigest::blake3(workspace_root.to_string_lossy().as_bytes()).hash
}

fn latest_receipt_path(store: &Path, workspace_root: &Path) -> PathBuf {
    store
        .join(BUILD_RECEIPTS_DIR)
        .join("checkouts")
        .join(format!("{}.json", workspace_key(workspace_root)))
}

fn group_receipt_path(store: &Path, group: &str, run: &str) -> PathBuf {
    store
        .join(BUILD_RECEIPTS_DIR)
        .join("groups")
        .join(group_key(group))
        .join(format!("{run}.json"))
}

fn group_key(group: &str) -> String {
    CacheDigest::blake3(group.as_bytes()).hash
}

fn read_build_receipt(path: &Path) -> Option<BuildReceipt> {
    let bytes = std::fs::read(path).ok()?;
    let receipt = serde_json::from_slice::<BuildReceipt>(&bytes).ok()?;
    let valid = TaskActionManifest {
        version: 1,
        task: receipt.identity.clone(),
        predictions: receipt.predictions.clone(),
    }
    .validate();
    (receipt.version == BUILD_RECEIPT_VERSION && valid).then_some(receipt)
}

fn validate_export_group(group: &str) -> Result<()> {
    if group.is_empty() || group.len() > 256 || group.chars().any(char::is_control) {
        eyre::bail!("invalid build export group");
    }
    Ok(())
}

/// How an export is laid out on disk.
///
/// Both forms carry the same manifest and the same `cas/v1` and
/// `action-results/v1` layout; they differ only in whether that tree is
/// wrapped in a tar. A transport that archives and compresses a directory
/// itself, such as `actions/cache`, would otherwise write every byte twice:
/// once into the tar and once again when the importer unpacks it.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum ExportForm {
    /// One tar file: portable, and what a standalone bundle should be.
    #[default]
    Tar,
    /// A directory tree, for transports that archive directories themselves.
    Directory,
}

impl std::str::FromStr for ExportForm {
    type Err = eyre::Report;

    fn from_str(text: &str) -> Result<Self> {
        match text {
            "tar" => Ok(Self::Tar),
            "directory" => Ok(Self::Directory),
            other => eyre::bail!("unknown export format {other:?}; expected tar or directory"),
        }
    }
}

/// Export the complete local cache closure of this checkout's most recent build.
pub fn export_checkout(
    store: &Path,
    workspace_root: &Path,
    archive: &Path,
) -> Result<TransferOutcome> {
    let receipt = read_build_receipt(&latest_receipt_path(store, workspace_root))
        .filter(|receipt| receipt.workspace_root == workspace_root)
        .ok_or_else(|| {
            eyre::eyre!(
                "no completed tuist_cargo_cache build is recorded for {}",
                workspace_root.display()
            )
        })?;
    export_receipts(
        store,
        vec![receipt],
        archive,
        ExportAdditions::default(),
        ExportForm::Tar,
    )
}

/// Return the target directory recorded for this checkout's latest build.
pub fn checkout_workspace_target(
    store: &Path,
    workspace_root: &Path,
) -> Result<Option<WorkspaceTarget>> {
    let Some(receipt) = read_build_receipt(&latest_receipt_path(store, workspace_root))
        .filter(|receipt| receipt.workspace_root == workspace_root)
    else {
        return Ok(None);
    };
    Ok(workspace_target_for_receipt(store, &receipt))
}

/// Return every Cargo target represented by the pending receipts in a group.
pub fn group_workspace_targets(store: &Path, group: &str) -> Result<Vec<WorkspaceTarget>> {
    validate_export_group(group)?;
    let root = store
        .join(BUILD_RECEIPTS_DIR)
        .join("groups")
        .join(group_key(group));
    let targets = walk_files(&root)?
        .into_iter()
        .filter_map(|entry| read_build_receipt(&entry.path))
        .filter(|receipt| receipt.group.as_deref() == Some(group))
        .filter_map(|receipt| workspace_target_for_receipt(store, &receipt))
        .collect::<BTreeSet<_>>();
    Ok(targets.into_iter().collect())
}

fn workspace_target_for_receipt(store: &Path, receipt: &BuildReceipt) -> Option<WorkspaceTarget> {
    let record = read_checkout_record(&checkout_record_path(
        store,
        &receipt.identity,
        &receipt.workspace_root,
    ))?;
    (record.workspace_root == receipt.workspace_root && record.target_dir != record.workspace_root)
        .then_some(WorkspaceTarget {
            workspace_root: record.workspace_root,
            target_dir: record.target_dir,
        })
}

/// Export one checkout's closure together with higher-level CAS attachments.
pub fn export_checkout_with(
    store: &Path,
    workspace_root: &Path,
    archive: &Path,
    additions: ExportAdditions,
) -> Result<TransferOutcome> {
    let receipt = read_build_receipt(&latest_receipt_path(store, workspace_root))
        .filter(|receipt| receipt.workspace_root == workspace_root)
        .ok_or_else(|| {
            eyre::eyre!(
                "no completed tuist_cargo_cache build is recorded for {}",
                workspace_root.display()
            )
        })?;
    export_receipts(store, vec![receipt], archive, additions, ExportForm::Tar)
}

/// Export one checkout's closure in the requested form.
pub fn export_checkout_as(
    store: &Path,
    workspace_root: &Path,
    destination: &Path,
    additions: ExportAdditions,
    form: ExportForm,
) -> Result<TransferOutcome> {
    let receipt = read_build_receipt(&latest_receipt_path(store, workspace_root))
        .filter(|receipt| receipt.workspace_root == workspace_root)
        .ok_or_else(|| {
            eyre::eyre!(
                "no completed tuist_cargo_cache build is recorded for {}",
                workspace_root.display()
            )
        })?;
    export_receipts(store, vec![receipt], destination, additions, form)
}

/// Export the union of every completed build recorded under one CI group.
pub fn export_group(store: &Path, group: &str, archive: &Path) -> Result<TransferOutcome> {
    export_group_with(store, group, archive, ExportAdditions::default())
}

/// Export a grouped closure together with higher-level CAS attachments.
pub fn export_group_with(
    store: &Path,
    group: &str,
    archive: &Path,
    additions: ExportAdditions,
) -> Result<TransferOutcome> {
    export_group_as(store, group, archive, additions, ExportForm::Tar)
}

/// Export a grouped closure in the requested form.
pub fn export_group_as(
    store: &Path,
    group: &str,
    destination: &Path,
    additions: ExportAdditions,
    form: ExportForm,
) -> Result<TransferOutcome> {
    validate_export_group(group)?;
    let root = store
        .join(BUILD_RECEIPTS_DIR)
        .join("groups")
        .join(group_key(group));
    let receipts = walk_files(&root)?
        .into_iter()
        .filter_map(|entry| read_build_receipt(&entry.path).map(|receipt| (entry.path, receipt)))
        .filter(|(_, receipt)| receipt.group.as_deref() == Some(group))
        .collect::<Vec<_>>();
    if receipts.is_empty() {
        eyre::bail!(
            "no completed tuist_cargo_cache builds are recorded for export group {group:?}"
        );
    }
    let outcome = export_receipts(
        store,
        receipts
            .iter()
            .map(|(_, receipt)| receipt.clone())
            .collect(),
        destination,
        additions,
        form,
    )?;
    // A receipt is a pending-export root. Retire only the files this export
    // consumed, and only after its complete archive has been published. A
    // concurrent build can add another uniquely named receipt to the group
    // without this cleanup deleting work the archive did not include.
    for (path, _) in receipts {
        std::fs::remove_file(path)?;
    }
    let _ = std::fs::remove_dir(root);
    Ok(outcome)
}

fn export_receipts(
    store: &Path,
    mut receipts: Vec<BuildReceipt>,
    archive: &Path,
    additions: ExportAdditions,
    form: ExportForm,
) -> Result<TransferOutcome> {
    receipts.sort_by(|left, right| {
        left.completed_nanos
            .cmp(&right.completed_nanos)
            .then_with(|| {
                // Concurrent commands may complete on the same clock tick. Use
                // their persisted predictions to break ties, not directory order.
                fn key(prediction: &ActionPrediction) -> (&CacheDigest, &CacheDigest, &str, &str) {
                    (
                        &prediction.invocation,
                        &prediction.action,
                        &prediction.adapter,
                        &prediction.payload,
                    )
                }
                left.predictions
                    .iter()
                    .map(key)
                    .cmp(right.predictions.iter().map(key))
            })
    });
    let mut actions = BTreeSet::new();
    let mut tasks = BTreeMap::new();
    for receipt in receipts {
        actions.extend(
            receipt
                .predictions
                .iter()
                .map(|prediction| prediction.action.clone()),
        );
        // Keep predictions from every command in receipt order. Deduplication
        // below makes the most recently completed command win an overlap.
        tasks
            .entry(receipt.identity)
            .or_insert_with(Vec::new)
            .extend(receipt.predictions);
    }
    let tasks = tasks
        .into_iter()
        .map(|(task, predictions)| {
            let mut invocations = BTreeSet::new();
            let mut predictions = predictions
                .into_iter()
                .rev()
                .filter(|prediction| invocations.insert(prediction.invocation.clone()))
                .collect::<Vec<_>>();
            predictions.reverse();
            TaskActionManifest {
                version: 1,
                task,
                predictions,
            }
        })
        .collect::<Vec<_>>();
    if tasks.iter().any(|task| !task.validate()) {
        eyre::bail!("combined export predictions exceed task manifest limits");
    }
    validate_export_additions(&additions)?;
    let mut closure = strict_closure(store, &actions)?;
    let cas = LocalCas::new(store);
    for digest in &additions.objects {
        require_object(&cas, &mut closure, digest)?;
    }
    // Hash the leaves before they are packed. An export is what another
    // machine will trust, so publishing a blob this store has since corrupted
    // would move the failure to whoever restores it.
    verify_pending(&mut closure.pending).wrap_err("cache closure is incomplete or corrupt")?;
    let parent = archive
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let manifest = serde_json::to_vec(&ExportManifest {
        version: if additions.attachments.is_empty() && additions.objects.is_empty() {
            LEGACY_EXPORT_VERSION
        } else {
            EXPORT_VERSION
        },
        tasks,
        actions: actions.iter().cloned().collect(),
        attachments: additions.attachments.clone(),
        objects: additions.objects.iter().cloned().collect(),
    })?;
    let members = closure
        .objects
        .iter()
        .chain(closure.results.iter())
        .collect::<Vec<_>>();
    let bytes = match form {
        ExportForm::Tar => write_tar_export(store, archive, parent, &manifest, &members)?,
        ExportForm::Directory => {
            write_directory_export(store, archive, parent, &manifest, &members)?
        }
    };
    Ok(TransferOutcome {
        actions: actions.len() as u64,
        objects: closure.objects.len() as u64,
        bytes,
    })
}

/// Write the export as one tar file, published atomically by rename.
fn write_tar_export(
    store: &Path,
    archive: &Path,
    parent: &Path,
    manifest: &[u8],
    members: &[&PathBuf],
) -> Result<u64> {
    let temporary = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-export-")
        .tempfile_in(parent)?;
    let mut builder = tar::Builder::new(temporary.reopen()?);
    append_bytes(&mut builder, Path::new(EXPORT_MANIFEST), manifest)?;
    for path in members {
        append_file(&mut builder, store, path)?;
    }
    builder.finish()?;
    drop(builder);
    temporary
        .persist(archive)
        .map_err(|error| error.error)
        .wrap_err_with(|| format!("failed to publish {}", archive.display()))?;
    Ok(std::fs::metadata(archive)?.len())
}

/// Write the export as a directory, published atomically by rename.
///
/// Built beside the destination and moved into place, so an interrupted export
/// leaves a `.tuist_cargo_cache-export-` directory rather than a bundle that looks complete
/// and is not.
fn write_directory_export(
    store: &Path,
    destination: &Path,
    parent: &Path,
    manifest: &[u8],
    members: &[&PathBuf],
) -> Result<u64> {
    let staging = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-export-")
        .tempdir_in(parent)?;
    std::fs::write(staging.path().join(EXPORT_MANIFEST), manifest)?;
    let mut bytes = manifest.len() as u64;
    for path in members {
        let relative = path.strip_prefix(store)?;
        let target = staging.path().join(relative);
        std::fs::create_dir_all(target.parent().expect("export member has a parent"))?;
        bytes += std::fs::copy(path, &target)?;
    }
    let staged = staging.keep();
    // `rename` will not replace a populated directory, so an existing bundle
    // has to move out of the way first. Move it aside rather than deleting it:
    // if publication then fails, deleting first would have left no bundle at
    // all, which is worse than the stale one the caller started with.
    let retired = match std::fs::symlink_metadata(destination) {
        Ok(_) => {
            let holder = tempfile::Builder::new()
                .prefix(".tuist_cargo_cache-export-retired-")
                .tempdir_in(parent)?;
            let moved = holder.path().join("bundle");
            std::fs::rename(destination, &moved)
                .wrap_err_with(|| format!("failed to replace {}", destination.display()))?;
            Some((holder, moved))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => {
            return Err(error)
                .wrap_err_with(|| format!("failed to replace {}", destination.display()));
        }
    };
    if let Err(error) = std::fs::rename(&staged, destination) {
        let _ = std::fs::remove_dir_all(&staged);
        if let Some((holder, moved)) = retired
            && std::fs::rename(&moved, destination).is_err()
        {
            // Putting the old bundle back has failed too, and letting the
            // holder drop here would delete the only remaining copy of it.
            // Keep it instead, and say where it went: a stale bundle the
            // caller has to move back by hand still beats no bundle at all.
            let kept = holder.keep();
            log::warn!(
                "could not restore {} after a failed export; its previous contents are at {}",
                destination.display(),
                kept.join("bundle").display()
            );
        }
        return Err(error).wrap_err_with(|| format!("failed to publish {}", destination.display()));
    }
    // The replaced bundle is only discarded once the new one is in place.
    drop(retired);
    Ok(bytes)
}

/// Validate a cache export in isolation, then publish its objects and actions.
pub fn import_archive(store: &Path, archive: &Path) -> Result<TransferOutcome> {
    Ok(import_archive_with_attachments(store, archive)?.transfer)
}

/// Import a cache archive and return its named higher-level CAS roots.
pub fn import_archive_with_attachments(store: &Path, archive: &Path) -> Result<ImportOutcome> {
    // A directory bundle is read where it lies. Unpacking one into staging
    // would write every byte a second time, which is the whole cost the
    // directory form exists to avoid.
    let staged;
    let _staging_lock;
    let root = if archive.is_dir() {
        _staging_lock = None;
        validate_directory_bundle(archive)?;
        archive
    } else {
        // Stage inside the store, not the system temp directory. Publication
        // moves the verified files with `fs::rename`, which only works within
        // one filesystem; a `$TMPDIR` on another device silently downgrades
        // every object to a copy and a second hash, and unpacking a
        // multi-gigabyte export into a container's `/tmp` can run out of room.
        let staging_root = store.join(IMPORT_STAGING_DIR);
        std::fs::create_dir_all(&staging_root)?;
        staged = tempfile::Builder::new()
            .prefix("import-")
            .tempdir_in(&staging_root)?;
        // Held for the rest of the import so a concurrent sweep can tell this
        // tree from one a killed process abandoned. The gap between creating
        // the directory and taking the lock needs no closing: a sweep only
        // considers trees a day old, and this one is new.
        _staging_lock = Some(lock_import_staging(staged.path())?);
        unpack_archive(archive, staged.path())?;
        staged.path()
    };
    // Measure a directory bundle now: publication moves its objects into the
    // store, so by the end there is nothing left to measure.
    let bundle_bytes = archive.is_dir().then(|| tree_bytes(archive));
    let manifest: ExportManifest =
        serde_json::from_slice(&std::fs::read(root.join(EXPORT_MANIFEST))?)?;
    let actions = manifest.actions.iter().cloned().collect::<BTreeSet<_>>();
    let task_identities = manifest
        .tasks
        .iter()
        .map(|task| task.task.as_str())
        .collect::<BTreeSet<_>>();
    if !matches!(manifest.version, LEGACY_EXPORT_VERSION | EXPORT_VERSION)
        || (manifest.version == LEGACY_EXPORT_VERSION
            && (!manifest.attachments.is_empty() || !manifest.objects.is_empty()))
        || manifest.tasks.is_empty()
        || actions.len() != manifest.actions.len()
        || task_identities.len() != manifest.tasks.len()
        || manifest.tasks.iter().any(|task| !task.validate())
        || manifest
            .actions
            .iter()
            .any(|action| action.algorithm != "blake3" || action.validate().is_err())
        || manifest.tasks.iter().any(|task| {
            task.predictions
                .iter()
                .any(|prediction| !actions.contains(&prediction.action))
        })
        || manifest
            .attachments
            .keys()
            .any(|name| !valid_attachment_name(name))
        || manifest.attachments.values().any(|digest| {
            digest.algorithm != "blake3"
                || digest.validate().is_err()
                || !manifest.objects.contains(digest)
        })
        || manifest.objects.iter().collect::<BTreeSet<_>>().len() != manifest.objects.len()
        || manifest
            .objects
            .iter()
            .any(|digest| digest.algorithm != "blake3" || digest.validate().is_err())
    {
        eyre::bail!("unsupported or invalid cache export manifest");
    }
    let mut closure =
        strict_closure(root, &actions).wrap_err("cache export is incomplete or corrupt")?;
    let staged_cas = LocalCas::new(root);
    for digest in &manifest.objects {
        require_object(&staged_cas, &mut closure, digest)
            .wrap_err("cache export attachment is incomplete or corrupt")?;
    }
    verify_pending(&mut closure.pending).wrap_err("cache export is incomplete or corrupt")?;

    // Read every action result before anything is published. Publication moves
    // a directory bundle's objects into the store, and a bundle cannot be
    // re-imported once that has happened, so every failure that can be moved
    // ahead of it should be: a malformed result has to fail while the bundle
    // is still whole. What remains after this point is filesystem failure on
    // the store itself, which a retry would not survive either.
    let results = closure
        .results
        .iter()
        .map(|path| {
            let result: RemoteActionResult = serde_json::from_slice(&std::fs::read(path)?)
                .wrap_err_with(|| format!("action result is invalid: {}", path.display()))?;
            Ok(result)
        })
        .collect::<Result<Vec<_>>>()
        .wrap_err("cache export is incomplete or corrupt")?;

    let cas = LocalCas::new(store);
    for path in &closure.objects {
        let relative = path.strip_prefix(root)?;
        let source = root.join(relative);
        let digest = addressed_digest(root, &source, false)
            .ok_or_else(|| eyre::eyre!("invalid cache object path {}", relative.display()))?;
        // `strict_closure` verified every path in `objects` against its
        // content-addressed name. Preserve that proof and move the owned
        // staging file instead of hashing or copying the bytes again.
        cas.adopt_verified_file(&digest, &source)?;
    }
    let action_cache = tuist_cargo_cache_core::LocalActionCache::new(store);
    for result in &results {
        action_cache.store(result)?;
    }
    for task in manifest.tasks {
        merge_imported_manifest(store, task)?;
    }
    let bytes = match bundle_bytes {
        Some(bytes) => {
            // Publication moved the objects out of the bundle, so what is left
            // is a shell of empty directories. Removing it keeps a restored
            // bundle out of the job's disk budget for the rest of the run.
            std::fs::remove_dir_all(archive)
                .wrap_err_with(|| format!("failed to remove {}", archive.display()))?;
            bytes
        }
        None => std::fs::metadata(archive)?.len(),
    };
    Ok(ImportOutcome {
        transfer: TransferOutcome {
            actions: actions.len() as u64,
            objects: closure.objects.len() as u64,
            bytes,
        },
        attachments: manifest.attachments,
    })
}

fn validate_export_additions(additions: &ExportAdditions) -> Result<()> {
    if additions
        .attachments
        .keys()
        .any(|name| !valid_attachment_name(name))
        || additions
            .attachments
            .values()
            .any(|digest| !additions.objects.contains(digest))
        || additions
            .objects
            .iter()
            .any(|digest| digest.algorithm != "blake3" || digest.validate().is_err())
    {
        eyre::bail!("invalid cache export attachment");
    }
    Ok(())
}

fn valid_attachment_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 128
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

/// Everything one closure walk reached, and the leaves still to be hashed.
#[derive(Default)]
struct Closure {
    objects: BTreeSet<PathBuf>,
    results: BTreeSet<PathBuf>,
    pending: Vec<PendingObject>,
}

/// A leaf object recorded by the walk and awaiting content verification.
struct PendingObject {
    digest: CacheDigest,
    path: PathBuf,
}

fn strict_closure(store: &Path, actions: &BTreeSet<CacheDigest>) -> Result<Closure> {
    let cas = LocalCas::new(store);
    let action_cache = tuist_cargo_cache_core::LocalActionCache::new(store);
    let mut closure = Closure::default();
    let mut directories = BTreeSet::new();
    for action in actions {
        let result = action_cache
            .find(action)?
            .ok_or_else(|| eyre::eyre!("action result is missing for {}", action.hash))?;
        closure.results.insert(action_cache.path_for(action)?);
        require_object(&cas, &mut closure, &result.action)?;
        if let Some(metadata) = &result.metadata {
            let path = require_parsed_object(&cas, &mut closure, metadata)?;
            let captured: CapturedOutput = serde_json::from_slice(&std::fs::read(path)?)
                .wrap_err("action metadata is invalid")?;
            require_object(&cas, &mut closure, &captured.stdout)?;
            require_object(&cas, &mut closure, &captured.stderr)?;
        }
        if let Some(root) = &result.output_root {
            let mut nodes = vec![root.clone()];
            while let Some(digest) = nodes.pop() {
                if !directories.insert(digest.clone()) {
                    continue;
                }
                let path = require_parsed_object(&cas, &mut closure, &digest)?;
                let directory: CacheDirectory = serde_json::from_slice(&std::fs::read(path)?)
                    .wrap_err("output directory is invalid")?;
                for file in directory.files {
                    require_object(&cas, &mut closure, &file.digest)?;
                }
                for child in directory.directories {
                    nodes.push(child.digest);
                }
            }
        }
    }
    Ok(closure)
}

/// Verify every recorded leaf's contents, spread across the machine.
///
/// Callers must run this before publishing anything the walk reached: it is
/// the step that proves the bytes match their content-addressed names, and
/// both the exporter and the importer depend on that proof. A closure of a
/// few thousand compiler outputs is several gigabytes read once, and the
/// hash, not the read, is what saturates a core.
fn verify_pending(pending: &mut [PendingObject]) -> Result<()> {
    if pending.is_empty() {
        return Ok(());
    }
    // Longest first. Handing out a half-gigabyte rlib last would leave one
    // worker hashing it alone after the others have finished, and the lengths
    // cost nothing: the walk already checked each one against its digest.
    pending.sort_by(|left, right| {
        right
            .digest
            .size
            .cmp(&left.digest.size)
            .then_with(|| left.path.cmp(&right.path))
    });
    let workers = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .min(pending.len());
    let next = AtomicUsize::new(0);
    // Report the lowest failing path rather than whichever worker happened to
    // lose the race, so a corrupt closure names the same object every run.
    let failure: Mutex<Option<(PathBuf, eyre::Report)>> = Mutex::new(None);
    let pending: &[PendingObject] = pending;
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some(entry) = pending.get(index) else {
                        break;
                    };
                    let error = match entry.digest.matches_file(&entry.path) {
                        Ok(true) => continue,
                        Ok(false) => eyre::eyre!(
                            "local CAS blob failed digest verification: {}",
                            entry.path.display()
                        ),
                        Err(error) => {
                            error.wrap_err(format!("failed to verify {}", entry.path.display()))
                        }
                    };
                    let mut failure = failure.lock().unwrap_or_else(|error| error.into_inner());
                    if failure.as_ref().is_none_or(|(path, _)| entry.path < *path) {
                        *failure = Some((entry.path.clone(), error));
                    }
                }
            });
        }
    });
    match failure
        .into_inner()
        .unwrap_or_else(|error| error.into_inner())
    {
        Some((_, error)) => Err(error),
        None => Ok(()),
    }
}

#[derive(Deserialize)]
struct CapturedOutput {
    stdout: CacheDigest,
    stderr: CacheDigest,
}

fn merge_imported_manifest(destination: &Path, mut imported: TaskActionManifest) -> Result<()> {
    let identity = imported.task.clone();
    let destination_path = task_manifest_path(destination, &identity);
    let lock_path = task_manifest_lock_path(destination, &identity);
    std::fs::create_dir_all(lock_path.parent().expect("task manifest lock has a parent"))?;
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;
    if let Ok(bytes) = std::fs::read(&destination_path)
        && let Ok(existing) = serde_json::from_slice::<TaskActionManifest>(&bytes)
        && existing.task == identity
        && existing.validate()
    {
        let existing_predictions: BTreeMap<_, _> = existing
            .predictions
            .iter()
            .cloned()
            .map(|prediction| (prediction.invocation.clone(), prediction))
            .collect();
        // The bundle determines recency, but a checkout's current value wins
        // when both manifests predict the same invocation.
        let updates = imported
            .predictions
            .into_iter()
            .map(|prediction| {
                existing_predictions
                    .get(&prediction.invocation)
                    .cloned()
                    .unwrap_or(prediction)
            })
            .collect();
        imported.predictions =
            merge_task_action_predictions(existing.predictions, updates, &BTreeSet::new())?;
    }
    write_atomic(&destination_path, &serde_json::to_vec(&imported)?)
}

/// Record a leaf object, deferring its content hash to `verify_pending`.
///
/// Presence and declared length are settled here, while the walk can still say
/// cheaply which object is wrong. The contents are left for the parallel pass
/// because leaves are where the bytes are: compiler outputs, captured streams,
/// and attachments, none of which steer the walk.
fn require_object(cas: &LocalCas, closure: &mut Closure, digest: &CacheDigest) -> Result<()> {
    let expected = cas.path_for(digest)?;
    if !closure.objects.insert(expected.clone()) {
        return Ok(());
    }
    let metadata = match std::fs::metadata(&expected) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            eyre::bail!("cache object is missing for {}", digest.hash)
        }
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", expected.display()));
        }
    };
    if metadata.len() != digest.size {
        eyre::bail!(
            "local CAS blob failed digest verification: {}",
            expected.display()
        );
    }
    closure.pending.push(PendingObject {
        digest: digest.clone(),
        path: expected,
    });
    Ok(())
}

/// Verify an object the walk is about to deserialize, and return its path.
///
/// Action metadata and directory nodes decide what the walk visits next, so a
/// forged one steers the walk itself and has to be trusted before `serde_json`
/// sees it. They are canonical JSON and small, so hashing them in line costs
/// little next to the leaves they point at.
fn require_parsed_object(
    cas: &LocalCas,
    closure: &mut Closure,
    digest: &CacheDigest,
) -> Result<PathBuf> {
    let path = cas
        .find(digest)?
        .ok_or_else(|| eyre::eyre!("cache object is missing for {}", digest.hash))?;
    closure.objects.insert(path.clone());
    Ok(path)
}

fn task_manifest_path(store: &Path, identity: &str) -> PathBuf {
    store
        .join("task-manifests/v1")
        .join(format!("{identity}.json"))
}

fn task_manifest_lock_path(store: &Path, identity: &str) -> PathBuf {
    store
        .join("task-manifests/v1/locks")
        .join(format!("{identity}.lock"))
}

fn append_file(builder: &mut tar::Builder<std::fs::File>, root: &Path, path: &Path) -> Result<()> {
    let name = path.strip_prefix(root)?;
    builder.append_path_with_name(path, name)?;
    Ok(())
}

fn append_bytes(
    builder: &mut tar::Builder<std::fs::File>,
    name: &Path,
    bytes: &[u8],
) -> Result<()> {
    let mut header = tar::Header::new_gnu();
    header.set_size(bytes.len() as u64);
    header.set_mode(0o644);
    header.set_cksum();
    builder.append_data(&mut header, name, bytes)?;
    Ok(())
}

/// Unpack a tar export into an empty staging directory.
fn unpack_archive(archive: &Path, staging: &Path) -> Result<()> {
    let file = std::fs::File::open(archive)
        .wrap_err_with(|| format!("failed to open {}", archive.display()))?;
    let mut bundle = tar::Archive::new(file);
    let mut seen = BTreeSet::new();
    for entry in bundle.entries()? {
        let mut entry = entry?;
        let entry_type = entry.header().entry_type();
        if !entry_type.is_file() && !entry_type.is_gnu_sparse() {
            eyre::bail!("cache export contains a non-file entry");
        }
        let path = entry.path()?.into_owned();
        validate_archive_path(&path)?;
        if !seen.insert(path.clone()) {
            eyre::bail!("cache export contains duplicate entry {}", path.display());
        }
        let destination = staging.join(&path);
        std::fs::create_dir_all(destination.parent().expect("entry has a parent"))?;
        // `unpack` understands GNU sparse maps. A plain stream copy expands
        // holes into physical zeroes, which is both slower and much larger for
        // Rust artifacts containing sparse sections.
        entry.unpack(&destination)?;
    }
    Ok(())
}

/// Check a directory bundle against the policy a tar bundle is held to.
///
/// A tar carries its own entry types, so the importer can refuse a symlink or
/// a device node by reading the header. A directory has to be walked for the
/// same answer, and `DirEntry::metadata` does not follow symlinks, so anything
/// that is not a plain file or a directory is rejected here rather than
/// followed out of the bundle.
fn validate_directory_bundle(root: &Path) -> Result<()> {
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(&directory)
            .wrap_err_with(|| format!("failed to read {}", directory.display()))?
        {
            let entry = entry?;
            let metadata = entry.metadata()?;
            let path = entry.path();
            if metadata.is_dir() {
                pending.push(path);
                continue;
            }
            if !metadata.is_file() {
                eyre::bail!("cache export contains a non-file entry");
            }
            validate_archive_path(path.strip_prefix(root)?)?;
            reject_linked_file(&metadata, &path)?;
        }
    }
    Ok(())
}

/// Refuse a bundle file that shares its inode with a name outside the bundle.
///
/// Import adopts objects by moving them into the CAS. A second hard link would
/// survive that move and keep write access to a blob the store then treats as
/// verified and immutable, which is a way to change a verified object after it
/// has been checked.
#[cfg(unix)]
fn reject_linked_file(metadata: &std::fs::Metadata, path: &Path) -> Result<()> {
    use std::os::unix::fs::MetadataExt as _;

    if metadata.nlink() > 1 {
        eyre::bail!("cache export contains a hard link at {}", path.display());
    }
    Ok(())
}

/// Windows reports a link count only through `MetadataExt::number_of_links`,
/// which is unstable, so this check cannot be made there without reaching for
/// the platform API directly. The gap is narrow -- it needs an attacker who
/// can already write into the job's filesystem before the import runs -- but
/// it is a gap, and a Windows directory bundle does not get this protection.
#[cfg(not(unix))]
fn reject_linked_file(_metadata: &std::fs::Metadata, _path: &Path) -> Result<()> {
    Ok(())
}

fn validate_archive_path(path: &Path) -> Result<()> {
    if path.as_os_str().is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        eyre::bail!("cache export contains unsafe path {}", path.display());
    }
    // Compare components rather than a spelling. A tar entry always writes its
    // path with forward slashes, but a directory bundle is walked with the
    // platform's separator, so on Windows a prefix match against "cas/v1/"
    // would reject every file in the bundle.
    let parts = path
        .components()
        .map(|component| component.as_os_str().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    let expected = match parts.as_slice() {
        [name] => name == EXPORT_MANIFEST,
        [root, version, _rest @ ..] => {
            parts.len() > 2 && (root == "cas" || root == "action-results") && version == "v1"
        }
        [] => false,
    };
    if !expected {
        eyre::bail!("cache export contains unexpected path {}", path.display());
    }
    Ok(())
}

/// One checkout's claim on the actions a build identity recorded.
///
/// The target directory is not read back by anything yet; it is recorded
/// because it is the other half of what the shim mapped, and a record that
/// names only half of it would have to be rewritten to answer where the
/// artifacts went.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct CheckoutRecord {
    version: u8,
    workspace_root: PathBuf,
    target_dir: PathBuf,
    updated_secs: u64,
}

/// Summarize what the store currently holds.
pub fn stats(store: &Path) -> Result<StoreStats> {
    let objects = walk_files(&store.join(CAS_DIR))?;
    let results = walk_files(&store.join(ACTION_RESULTS_DIR))?;
    let checkouts = scan_checkouts(store)?;
    Ok(StoreStats {
        objects: objects.len() as u64,
        object_bytes: objects.iter().map(|entry| entry.size).sum(),
        action_results: results.len() as u64,
        action_result_bytes: results.iter().map(|entry| entry.size).sum(),
        live_checkouts: checkouts.live_records,
        stale_checkouts: checkouts.stale_records.len() as u64,
    })
}

/// Size the target tree a checkout record names, if it names one.
///
/// A build with no target directory of its own -- one driven by make or CMake,
/// which writes wherever it was told -- records the checkout in that field
/// rather than inventing a directory. Walking it would report the whole source
/// tree, `.git` included, as though it were build output.
fn checkout_target_bytes(sizes: &mut BTreeMap<PathBuf, u64>, record: &CheckoutRecord) -> u64 {
    if record.target_dir == record.workspace_root {
        return 0;
    }
    cached_tree_bytes(sizes, &record.target_dir)
}

/// Attribute cache and target bytes to each recorded workspace.
///
/// Shared objects are counted for every workspace that can reach them. That
/// makes each row answer "how much keeps this workspace warm" without
/// pretending shared storage can be divided exactly between projects.
pub fn projects(store: &Path) -> Result<Vec<ProjectUsage>> {
    project_usage(store, true)
}

/// The reusable cache bytes of each live workspace, as [`projects`] counts
/// them.
///
/// Sizing target directories is most of what [`projects`] costs on a machine
/// with many checkouts, and an estimate of cache sharing never looks at them.
pub fn live_project_cache_bytes(store: &Path) -> Result<Vec<u64>> {
    Ok(project_usage(store, false)?
        .into_iter()
        .filter(|project| project.live)
        .map(|project| project.action_bytes)
        .collect())
}

fn project_usage(store: &Path, size_targets: bool) -> Result<Vec<ProjectUsage>> {
    let mut projects: BTreeMap<PathBuf, (BTreeSet<String>, bool, u64)> = BTreeMap::new();
    let mut target_sizes = BTreeMap::new();
    let root = store.join(CHECKOUTS_DIR);
    for identity_entry in read_dir_or_empty(&root)? {
        let identity = identity_entry.file_name().to_string_lossy().into_owned();
        if !is_task_identity(&identity) || !identity_entry.file_type()?.is_dir() {
            continue;
        }
        for entry in walk_files(&identity_entry.path())? {
            let Some(record) = read_checkout_record(&entry.path) else {
                continue;
            };
            let project = projects.entry(record.workspace_root.clone()).or_default();
            if claim_is_live(store, &record) {
                project.0.insert(identity.clone());
                project.1 = true;
            }
            if size_targets {
                project.2 = project
                    .2
                    .max(checkout_target_bytes(&mut target_sizes, &record));
            }
        }
    }
    let live = projects
        .values()
        .flat_map(|(identities, _, _)| identities.iter().cloned())
        .collect::<BTreeSet<_>>();
    let mut reachability = Reachability::new(store);
    resolve_identities(&reachability, &live);
    let mut usages = Vec::new();
    for (workspace_root, (identities, live, target_bytes)) in projects {
        let action_bytes = reachability.bytes(&identities);
        usages.push(ProjectUsage {
            workspace_root,
            identities: identities.len() as u64,
            action_bytes,
            target_bytes,
            live,
        });
    }
    usages.sort_by(|left, right| {
        right
            .action_bytes
            .saturating_add(right.target_bytes)
            .cmp(&left.action_bytes.saturating_add(left.target_bytes))
            .then_with(|| left.workspace_root.cmp(&right.workspace_root))
    });
    Ok(usages)
}

/// Resolve every identity's recorded actions into `reachability`.
///
/// Manifests are the one large input: a busy checkout's runs to tens of
/// megabytes of JSON, and parsing hundreds of them one after another is most
/// of what sizing every workspace costs. Resolving what they reach is mostly
/// cold file reads. Both are spread over a few threads, each taking whole
/// identities from a shared counter.
fn resolve_identities(reachability: &Reachability, identities: &BTreeSet<String>) {
    const MAX_WORKERS: usize = 8;
    let identities = identities.iter().collect::<Vec<_>>();
    let workers = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .min(MAX_WORKERS)
        .min(identities.len());
    let next = AtomicUsize::new(0);
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                while let Some(identity) = identities.get(next.fetch_add(1, Ordering::Relaxed)) {
                    // One manifest this build cannot read is not worth
                    // abandoning the report over. It reaches nothing, which
                    // can only understate sharing.
                    let actions = task_manifest_actions(&reachability.store, identity)
                        .unwrap_or_else(|error| {
                            log::debug!("could not read the manifest for {identity}: {error}");
                            Vec::new()
                        });
                    reachability.record(identity, &actions);
                }
            });
        }
    });
}

/// The store paths each identity can reach, resolved once for every workspace.
///
/// Workspaces share identities, identities share most of their actions, and
/// actions share output trees. Answering each workspace from scratch reread
/// the same manifests, results, and trees, and stat-ed the same objects, once
/// per workspace, which on a machine with a couple of hundred checkouts was
/// most of the half minute `tuist_cargo_cache stats` took. Here every file is read and
/// stat-ed at most once, and a workspace's total is a union of indices already
/// in memory.
///
/// What is reachable matches [`rooted_objects`] plus the action-result records
/// themselves, and every read is as tolerant as it is there.
struct Reachability {
    store: PathBuf,
    cas: LocalCas,
    action_cache: tuist_cargo_cache_core::LocalActionCache,
    /// Every indexed path and its size, zero if it no longer exists.
    paths: Mutex<PathIndex>,
    identities: Mutex<HashMap<String, ActionPaths>>,
    actions: Mutex<HashMap<CacheDigest, Arc<[usize]>>>,
    /// Each tree blob's child directories and the paths it names directly.
    directories: Mutex<HashMap<CacheDigest, Option<DirectoryPaths>>>,
    /// The workspace number that last counted each path.
    counted: Vec<usize>,
    workspaces: usize,
}

#[derive(Default)]
struct PathIndex {
    indices: HashMap<PathBuf, usize>,
    sizes: Vec<u64>,
}

/// The paths each of an identity's actions reaches.
type ActionPaths = Arc<[Arc<[usize]>]>;

type DirectoryPaths = (Arc<[CacheDigest]>, Arc<[usize]>);

/// The caches are only guards around maps; a panicked holder leaves them
/// consistent, so poisoning is not worth failing a report over.
fn locked<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|error| error.into_inner())
}

impl Reachability {
    fn new(store: &Path) -> Self {
        Self {
            store: store.to_path_buf(),
            cas: LocalCas::new(store),
            action_cache: tuist_cargo_cache_core::LocalActionCache::new(store),
            paths: Mutex::default(),
            identities: Mutex::default(),
            actions: Mutex::default(),
            directories: Mutex::default(),
            counted: Vec::new(),
            workspaces: 0,
        }
    }

    /// Bytes reachable from any of `identities`, each path counted once.
    ///
    /// An identity that was never recorded reaches nothing.
    fn bytes(&mut self, identities: &BTreeSet<String>) -> u64 {
        let reachable = {
            let recorded = locked(&self.identities);
            identities
                .iter()
                .filter_map(|identity| recorded.get(identity).cloned())
                .collect::<Vec<_>>()
        };
        let sizes = std::mem::take(&mut locked(&self.paths).sizes);
        self.workspaces += 1;
        self.counted.resize(sizes.len(), 0);
        let mut bytes = 0_u64;
        for index in reachable
            .iter()
            .flat_map(|actions| actions.iter())
            .flat_map(|paths| paths.iter())
        {
            if self.counted[*index] != self.workspaces {
                self.counted[*index] = self.workspaces;
                bytes = bytes.saturating_add(sizes[*index]);
            }
        }
        locked(&self.paths).sizes = sizes;
        bytes
    }

    /// Resolve what one identity's recorded actions reach.
    ///
    /// Safe to call from several threads. Two threads may resolve the same
    /// action at once; they read the same files and reach the same answer.
    fn record(&self, identity: &str, actions: &[CacheDigest]) {
        let actions = actions
            .iter()
            .map(|action| self.action(action))
            .collect::<Arc<[_]>>();
        locked(&self.identities).insert(identity.to_string(), actions);
    }

    fn action(&self, action: &CacheDigest) -> Arc<[usize]> {
        if let Some(paths) = locked(&self.actions).get(action) {
            return paths.clone();
        }
        let mut paths = Vec::new();
        if let Ok(path) = self.action_cache.path_for(action) {
            paths.push(self.index(path));
        }
        if let Some(result) = read_action_result(&self.store, action) {
            self.push_digest(&mut paths, &result.action);
            if let Some(metadata) = &result.metadata {
                self.push_digest(&mut paths, metadata);
                if let Some(rustc) = read_rustc_metadata(&self.cas, metadata) {
                    self.push_digest(&mut paths, &rustc.stdout);
                    self.push_digest(&mut paths, &rustc.stderr);
                }
            }
            if let Some(output_root) = &result.output_root {
                self.push_digest(&mut paths, output_root);
                let mut pending = vec![output_root.clone()];
                let mut visited = HashSet::new();
                while let Some(digest) = pending.pop() {
                    if !visited.insert(digest.clone()) {
                        continue;
                    }
                    let Some((children, named)) = self.directory(&digest) else {
                        continue;
                    };
                    paths.extend(named.iter().copied());
                    pending.extend(children.iter().cloned());
                }
            }
        }
        paths.sort_unstable();
        paths.dedup();
        let paths = Arc::<[usize]>::from(paths);
        locked(&self.actions).insert(action.clone(), paths.clone());
        paths
    }

    /// The child directories of a tree blob and the paths it names directly.
    fn directory(&self, digest: &CacheDigest) -> Option<DirectoryPaths> {
        if let Some(entry) = locked(&self.directories).get(digest) {
            return entry.clone();
        }
        let entry = read_directory(&self.cas, digest).map(|directory| {
            let mut paths = Vec::new();
            for file in &directory.files {
                self.push_digest(&mut paths, &file.digest);
            }
            for child in &directory.directories {
                self.push_digest(&mut paths, &child.digest);
            }
            let children = directory
                .directories
                .into_iter()
                .map(|child| child.digest)
                .collect::<Arc<[_]>>();
            (children, Arc::<[usize]>::from(paths))
        });
        locked(&self.directories).insert(digest.clone(), entry.clone());
        entry
    }

    fn push_digest(&self, paths: &mut Vec<usize>, digest: &CacheDigest) {
        if let Ok(path) = self.cas.path_for(digest) {
            paths.push(self.index(path));
        }
    }

    fn index(&self, path: PathBuf) -> usize {
        if let Some(index) = locked(&self.paths).indices.get(&path) {
            return *index;
        }
        // The stat runs outside the lock. A second thread may stat the same
        // path; whichever registers first wins and both get one index.
        let size = std::fs::metadata(&path).map_or(0, |metadata| metadata.len());
        let mut paths = locked(&self.paths);
        if let Some(index) = paths.indices.get(&path) {
            return *index;
        }
        let index = paths.sizes.len();
        paths.sizes.push(size);
        paths.indices.insert(path, index);
        index
    }
}

/// Return the largest blobs and action-result records in descending order.
pub fn largest(store: &Path, limit: usize) -> Result<Vec<LargestEntry>> {
    let mut entries = Vec::new();
    for (kind, root, action_result) in [
        ("object", store.join(CAS_DIR), false),
        ("action result", store.join(ACTION_RESULTS_DIR), true),
    ] {
        entries.extend(
            walk_files(&root)?
                .into_iter()
                .filter(|entry| addressed_digest(store, &entry.path, action_result).is_some())
                .map(|entry| LargestEntry {
                    kind,
                    path: entry.path,
                    bytes: entry.size,
                }),
        );
    }
    entries.sort_by(|left, right| {
        right
            .bytes
            .cmp(&left.bytes)
            .then_with(|| left.path.cmp(&right.path))
    });
    entries.truncate(limit);
    Ok(entries)
}

/// Verify every addressable CAS object and action-result record.
pub fn verify(store: &Path) -> Result<VerifyOutcome> {
    let cas = LocalCas::new(store);
    let action_cache = tuist_cargo_cache_core::LocalActionCache::new(store);
    // Verification reports the store as it is on disk and removes nothing, so
    // no object is pending removal the way one is mid-sweep.
    let virtually_removed = HashSet::new();
    let mut outcome = VerifyOutcome::default();
    for entry in walk_files(&store.join(CAS_DIR))? {
        let Some(digest) = addressed_digest(store, &entry.path, false) else {
            continue;
        };
        outcome.checked_objects += 1;
        if !matches!(cas.find(&digest), Ok(Some(_))) {
            outcome.problems.push(entry.path);
        }
    }
    for entry in walk_files(&store.join(ACTION_RESULTS_DIR))? {
        let Some(digest) = addressed_digest(store, &entry.path, true) else {
            continue;
        };
        outcome.checked_action_results += 1;
        if !matches!(action_cache.find(&digest), Ok(Some(_)))
            || action_result_is_dangling(&cas, &entry.path, &virtually_removed)?
        {
            outcome.problems.push(entry.path);
        }
    }
    outcome.problems.sort();
    Ok(outcome)
}

/// Remove checkout claims belonging to exactly one workspace.
pub fn remove_project(store: &Path, workspace_root: &Path) -> Result<RemoveProjectOutcome> {
    let mut outcome = RemoveProjectOutcome::default();
    for entry in walk_files(&store.join(CHECKOUTS_DIR))? {
        if read_checkout_record(&entry.path)
            .is_some_and(|record| record.workspace_root == workspace_root)
        {
            std::fs::remove_file(&entry.path)?;
            outcome.removed_checkout_records += 1;
            if let Some(parent) = entry.path.parent() {
                let _ = std::fs::remove_dir(parent);
            }
        }
    }
    match std::fs::remove_file(latest_receipt_path(store, workspace_root)) {
        Ok(()) => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(outcome)
}

/// Record that `workspace_root` built `identity`.
///
/// Identities are shared by every checkout of one dependency graph, so this is
/// what later tells the collector whether anything still needs what a build
/// cached: one file per checkout under the identity it built. Writing a whole
/// file per checkout rather than merging a list into one keeps concurrent
/// builds out of each other's way -- there is nothing to merge, so there is no
/// lock and no lost update.
///
/// A build with no target directory of its own passes `workspace_root` for
/// `target_dir`, which reads as "none" rather than as a tree to measure.
pub fn record_checkout(
    store: &Path,
    identity: &str,
    workspace_root: &Path,
    target_dir: &Path,
) -> Result<()> {
    let record = CheckoutRecord {
        version: CHECKOUT_RECORD_VERSION,
        workspace_root: workspace_root.to_path_buf(),
        target_dir: target_dir.to_path_buf(),
        updated_secs: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|since| since.as_secs())
            .unwrap_or_default(),
    };
    let mut contents = serde_json::to_vec(&record)?;
    contents.push(b'\n');
    // Refreshed by every build and read back only as a last-used stamp, so a
    // power cut costs one build's worth of recency, not a wait on the disk.
    write_advisory(
        &checkout_record_path(store, identity, workspace_root),
        &contents,
    )
}

fn checkout_record_path(store: &Path, identity: &str, workspace_root: &Path) -> PathBuf {
    // The path is hashed rather than escaped: it is only ever compared against
    // the same hash of the same path, and every filesystem in play disagrees
    // about which characters a name may hold.
    let key = CacheDigest::blake3(workspace_root.to_string_lossy().as_bytes()).hash;
    store
        .join(CHECKOUTS_DIR)
        .join(identity)
        .join(format!("{key}.json"))
}

/// Evict objects until the store fits within `max_bytes`.
///
/// Objects no live checkout can reach are evicted first, so deleting a worktree
/// releases what only that worktree needed. Within each class eviction is
/// least-recently-used by access time where the filesystem records it, falling
/// back to modification time. A restore verifies the blob it serves, which
/// means it reads the whole file and the access time is real -- but only where
/// the mount records one, so the ordering is an approximation either way.
/// Evicting a live object costs a recompile, never correctness.
pub fn gc(store: &Path, max_bytes: u64) -> Result<GcOutcome> {
    gc_with_mode(store, max_bytes, false)
}

/// Describe the collection `gc` would perform without changing the store.
pub fn gc_dry_run(store: &Path, max_bytes: u64) -> Result<GcOutcome> {
    gc_with_mode(store, max_bytes, true)
}

fn gc_with_mode(store: &Path, max_bytes: u64, dry_run: bool) -> Result<GcOutcome> {
    let mut objects = walk_files(&store.join(CAS_DIR))?;
    let results = walk_files(&store.join(ACTION_RESULTS_DIR))?;
    let mut live_bytes = objects
        .iter()
        .chain(results.iter())
        .map(|entry| entry.size)
        .sum::<u64>();

    let mut outcome = GcOutcome::default();

    // Prune before deciding what is rooted, so a checkout deleted since the
    // last sweep stops protecting its artifacts during this one.
    let checkouts = scan_checkouts(store)?;
    for path in &checkouts.stale_records {
        if dry_run || matches!(remove(path)?, Removal::Removed) {
            outcome.removed_checkout_records += 1;
        }
        // The identity directory is left behind empty otherwise. It may hold
        // other checkouts, in which case this fails and that is the answer.
        if !dry_run && let Some(parent) = path.parent() {
            let _ = std::fs::remove_dir(parent);
        }
    }

    let mut virtually_removed = HashSet::new();
    if live_bytes > max_bytes {
        // Reachability costs a read per action result and per output tree, so
        // it is computed only when something is actually about to be evicted.
        // Under budget a sweep stays a directory walk and nothing more.
        let mut rooted = rooted_objects(store, &checkouts.live_identities)?;
        // A grouped CI export deliberately retains the exact actions from
        // every command in the job. Later commands can replace the current
        // task-manifest prediction for the same invocation, but the earlier
        // receipt still has to remain exportable until the post-job step runs.
        // Receipt bookkeeping is not part of the cache budget, so consult it
        // only when a sweep is already necessary and root its object closure.
        rooted.extend(rooted_action_objects(
            store,
            grouped_receipt_actions(store)?,
        ));
        // `false` sorts first, so unrooted objects go before rooted ones and
        // each class goes oldest-first. A store with no records at all roots
        // nothing and this is exactly the LRU it was before.
        objects.sort_by_cached_key(|entry| (rooted.contains(&entry.path), entry.used));
        let evicted = evict_objects(&objects, &rooted, live_bytes, max_bytes, |path| {
            if dry_run {
                virtually_removed.insert(path.to_path_buf());
                Ok(Removal::Removed)
            } else {
                remove(path)
            }
        })?;
        live_bytes = evicted.remaining_bytes;
        outcome.removed_objects += evicted.removed_objects;
        outcome.removed_bytes += evicted.removed_bytes;
    }

    // An action result whose objects are gone can only produce a miss, so drop
    // it rather than leave the index pointing at nothing. This runs whether or
    // not this call evicted anything, since another process may have, and a
    // store that is over budget on results alone still needs the sweep.
    let cas = LocalCas::new(store);
    for entry in &results {
        if action_result_is_dangling(&cas, &entry.path, &virtually_removed)? {
            match if dry_run {
                Removal::Removed
            } else {
                remove(&entry.path)?
            } {
                Removal::Removed => {
                    live_bytes = live_bytes.saturating_sub(entry.size);
                    outcome.removed_action_results += 1;
                    outcome.removed_bytes += entry.size;
                }
                Removal::Missing => live_bytes = live_bytes.saturating_sub(entry.size),
                Removal::Blocked => {}
            }
        }
    }

    let sessions = prune_sessions(store, dry_run)?;
    outcome.removed_session_streams += sessions.removed_streams;
    outcome.removed_bytes += sessions.removed_bytes;
    prune_import_staging(store, dry_run);

    outcome.remaining_bytes = live_bytes;
    Ok(outcome)
}

/// Discard import staging trees that a killed process left behind.
///
/// A finished import removes its own tree, and a failed one unwinds through
/// `TempDir`, so only a kill leaks. What leaks is the whole expanded export,
/// and it sits outside `cas/v1` and `action-results/v1`, so the sweep's own
/// accounting cannot see it and nothing else would ever reclaim it.
///
/// Age is what makes this safe to do without a lock: a concurrent import
/// holds no claim this could consult, and one that has been extracting for a
/// day has worse problems than a stale directory. Failures are logged rather
/// than returned, because losing a staging tree must not fail a sweep.
fn prune_import_staging(store: &Path, dry_run: bool) {
    if dry_run {
        return;
    }
    let root = store.join(IMPORT_STAGING_DIR);
    let Ok(entries) = read_dir_or_empty(&root) else {
        return;
    };
    for entry in entries {
        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        let abandoned = metadata
            .modified()
            .ok()
            .and_then(|modified| SystemTime::now().duration_since(modified).ok())
            .is_some_and(|age| age >= IMPORT_STAGING_RETENTION);
        if !abandoned {
            continue;
        }
        let path = entry.path();
        if !metadata.is_dir() {
            // A claim whose tree is already gone: reclaim it so claims cannot
            // pile up one per import that was killed after its tree went.
            if path
                .extension()
                .is_some_and(|extension| extension == "lock")
                && !claimed_staging_path(&path).exists()
            {
                let _ = std::fs::remove_file(&path);
            }
            continue;
        }
        // Age alone would be a guess. An import that outlives the retention
        // window -- a very large bundle on slow storage -- still holds its
        // lock, and taking its tree out from under it would fail a running
        // restore. A lock nobody holds is one the kernel released for a
        // process that is gone.
        let lock_path = import_staging_lock_path(&path);
        let Ok(mut lock) = fslock::LockFile::open(&lock_path) else {
            continue;
        };
        if !matches!(lock.try_lock(), Ok(true)) {
            continue;
        }
        if let Err(error) = std::fs::remove_dir_all(&path) {
            log::debug!(
                "could not remove abandoned import staging {}: {error}",
                path.display()
            );
            continue;
        }
        drop(lock);
        let _ = std::fs::remove_file(&lock_path);
    }
}

/// The staging tree a claim describes.
fn claimed_staging_path(lock: &Path) -> PathBuf {
    lock.with_extension("")
}

/// Where the liveness lock for one staging tree lives.
///
/// A sibling of the tree rather than a file inside it, so that removing the
/// tree does not remove the lock the remover is holding.
fn import_staging_lock_path(staging: &Path) -> PathBuf {
    let mut name = staging.as_os_str().to_os_string();
    name.push(".lock");
    PathBuf::from(name)
}

/// One import's claim on its staging tree, released when the import ends.
///
/// The lock file is removed with the claim. `TempDir` takes the tree itself,
/// and a claim left behind would otherwise outlive every tree it described:
/// the sweep walks directories, so nothing would ever collect it.
struct StagingClaim {
    lock: Option<fslock::LockFile>,
    path: PathBuf,
}

impl Drop for StagingClaim {
    fn drop(&mut self) {
        // Release before unlinking, so a sweep that already opened this file
        // sees an unlocked claim rather than waiting on one that is going away.
        drop(self.lock.take());
        let _ = std::fs::remove_file(&self.path);
    }
}

/// Claim a staging tree for the lifetime of one import.
fn lock_import_staging(staging: &Path) -> Result<StagingClaim> {
    let path = import_staging_lock_path(staging);
    let mut lock = fslock::LockFile::open(&path)
        .wrap_err_with(|| format!("failed to open {}", path.display()))?;
    lock.lock()?;
    Ok(StagingClaim {
        lock: Some(lock),
        path,
    })
}

#[derive(Debug, Default, PartialEq, Eq)]
struct SessionPrune {
    removed_streams: u64,
    removed_bytes: u64,
}

fn prune_sessions(store: &Path, dry_run: bool) -> Result<SessionPrune> {
    let mut prune = SessionPrune::default();
    let ids = events::session_ids(store);
    let surplus = ids.len().saturating_sub(MAX_SESSIONS);
    for (index, id) in ids.iter().enumerate() {
        let paths = events::session_paths(store, id);
        let metadata = match std::fs::metadata(&paths.events) {
            Ok(metadata) => metadata,
            Err(_) => continue,
        };
        let stale = metadata
            .modified()
            .ok()
            .and_then(|at| SystemTime::now().duration_since(at).ok())
            .is_some_and(|age| age > SESSION_RETENTION);
        if index >= surplus && !stale {
            continue;
        }
        if events::session_is_live(store, id) {
            continue;
        }
        if dry_run {
            prune.removed_streams += 1;
            prune.removed_bytes += metadata.len();
            continue;
        }
        if matches!(remove(&paths.events)?, Removal::Removed) {
            prune.removed_streams += 1;
            prune.removed_bytes += metadata.len();
            let _ = std::fs::remove_file(&paths.lock);
        }
    }
    if !dry_run {
        for lock in events::orphaned_locks(store) {
            let _ = std::fs::remove_file(lock);
        }
    }
    Ok(prune)
}

/// Sweep the store if `interval` has passed since the last attempt.
///
/// The stamp is written before the sweep, not after. Two builds finishing
/// together should cost one sweep between them, and a sweep that dies partway
/// should wait its turn like any other rather than retry on every build.
pub fn sweep_if_due(store: &Path, max_bytes: u64, interval: Duration) -> Result<Option<GcOutcome>> {
    if !claim_sweep(store, interval)? {
        return Ok(None);
    }
    gc(store, max_bytes).map(Some)
}

/// Stamp a due sweep before its callers perform coordinated GC.
///
/// The sweep lock serializes claims, so updating the existing marker in place
/// is enough. In particular, it does not need a temporary file and rename:
/// claiming a sweep must still work when the disk has no room for one.
pub fn claim_sweep(store: &Path, interval: Duration) -> Result<bool> {
    let lock_path = store.join(SWEEP_LOCK);
    std::fs::create_dir_all(lock_path.parent().expect("sweep lock has a parent"))?;
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;

    let stamp = store.join(SWEEP_STAMP);
    if sweep_stamp_is_fresh(&stamp, interval) {
        return Ok(false);
    }
    let stamp = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&stamp)?;
    stamp.set_modified(SystemTime::now())?;
    Ok(true)
}

/// Whether [`claim_sweep`] would stamp a sweep now.
///
/// A read of the stamp, no lock and no write: this answers a build that only
/// wants to know whether to start a collector, and may be answered yes to two
/// builds at once. The claim itself stays inside the collector, which is where
/// the lock and the stamp are, so of two collectors started together, one
/// sweeps and the other finds the stamp fresh and exits.
pub fn sweep_is_due(store: &Path, interval: Duration) -> bool {
    !sweep_stamp_is_fresh(&store.join(SWEEP_STAMP), interval)
}

fn sweep_stamp_is_fresh(stamp: &Path, interval: Duration) -> bool {
    std::fs::metadata(stamp)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|since| since < interval)
}

/// What the checkout registry says about the identities in this store.
struct CheckoutScan {
    live_identities: BTreeSet<String>,
    live_records: u64,
    stale_records: Vec<PathBuf>,
}

fn scan_checkouts(store: &Path) -> Result<CheckoutScan> {
    let root = store.join(CHECKOUTS_DIR);
    let mut scan = CheckoutScan {
        live_identities: BTreeSet::new(),
        live_records: 0,
        stale_records: Vec::new(),
    };
    let listing = match std::fs::read_dir(&root) {
        Ok(listing) => listing,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(scan),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", root.display()));
        }
    };
    for entry in listing {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        // Anything that is not a directory named for an identity was not written
        // by tuist_cargo_cache. Both halves matter: `walk_files` tolerates only a missing
        // directory, so a plain file whose name happens to look like an identity
        // would fail the whole scan -- and that scan runs inside every sweep,
        // including the automatic one after a build.
        if !is_task_identity(&name) || !entry.file_type().is_ok_and(|kind| kind.is_dir()) {
            continue;
        }
        for record in walk_files(&entry.path())? {
            match read_checkout_record(&record.path) {
                Some(checkout) if claim_is_live(store, &checkout) => {
                    scan.live_identities.insert(name.clone());
                    scan.live_records += 1;
                }
                Some(_) => scan.stale_records.push(record.path),
                // A record this build cannot read claims nothing, but it is not
                // evidence the checkout is gone either, so leave it alone.
                None => {}
            }
        }
    }
    Ok(scan)
}

fn read_checkout_record(path: &Path) -> Option<CheckoutRecord> {
    let bytes = std::fs::read(path).ok()?;
    let record = serde_json::from_slice::<CheckoutRecord>(&bytes).ok()?;
    (record.version == CHECKOUT_RECORD_VERSION).then_some(record)
}

/// Actions whose successful grouped export has not retired its receipts yet.
fn grouped_receipt_actions(store: &Path) -> Result<BTreeSet<CacheDigest>> {
    let root = store.join(BUILD_RECEIPTS_DIR).join("groups");
    Ok(walk_files(&root)?
        .into_iter()
        .filter_map(|entry| read_build_receipt(&entry.path))
        .flat_map(|receipt| receipt.predictions.into_iter())
        .map(|prediction| prediction.action)
        .collect())
}

/// Whether a recorded claim still speaks for a checkout that is using this
/// store.
fn claim_is_live(store: &Path, record: &CheckoutRecord) -> bool {
    checkout_is_live_on(store, &record.workspace_root) && !claim_has_expired(record)
}

fn claim_has_expired(record: &CheckoutRecord) -> bool {
    let Ok(now) = SystemTime::now().duration_since(UNIX_EPOCH) else {
        return false;
    };
    now.as_secs()
        .saturating_sub(record.updated_secs)
        .gt(&CHECKOUT_RETENTION.as_secs())
}

/// Whether the checkout a record names is still on disk.
///
/// Absence is believed only when the checkout is definitely absent and its
/// nearest existing ancestor is on the same filesystem as the store. Walking
/// all the way to that ancestor matters for worktree managers and temporary
/// directories, which commonly remove a checkout together with one or more of
/// its otherwise-empty parents.
///
/// A different filesystem can be a mount whose contents are temporarily
/// unavailable, so uncertainty there remains live. Errors are treated the same
/// way: being wrong in that direction only delays collection; the other way
/// round throws away a warm cache someone is still using.
pub fn checkout_is_live_on(store: &Path, workspace_root: &Path) -> bool {
    if !matches!(workspace_root.try_exists(), Ok(false)) {
        return true;
    }

    let Ok(store_metadata) = std::fs::metadata(store) else {
        return true;
    };
    for ancestor in workspace_root.ancestors().skip(1) {
        match std::fs::metadata(ancestor) {
            Ok(ancestor_metadata) => {
                return !same_filesystem(store, &store_metadata, ancestor, &ancestor_metadata);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return true,
        }
    }
    true
}

/// Whether a checkout is still on disk, corroborating absence through its
/// immediate parent.
///
/// Prefer [`checkout_is_live_on`] when an existing store or managed-target
/// root is available to distinguish deletion from an unavailable filesystem.
pub fn checkout_is_live(workspace_root: &Path) -> bool {
    let Some(parent) = workspace_root.parent() else {
        return true;
    };
    checkout_is_live_on(parent, workspace_root)
}

/// Whether two existing paths sit on the same filesystem, so a rename can
/// carry a directory from one to the other.
///
/// A path that cannot be inspected answers `false`: a move that cannot be
/// checked is not one to attempt.
pub fn same_filesystem_paths(a: &Path, b: &Path) -> bool {
    let (Ok(a_metadata), Ok(b_metadata)) = (std::fs::metadata(a), std::fs::metadata(b)) else {
        return false;
    };
    same_filesystem(a, &a_metadata, b, &b_metadata)
}

#[cfg(unix)]
fn same_filesystem(
    _a_path: &Path,
    a: &std::fs::Metadata,
    _b_path: &Path,
    b: &std::fs::Metadata,
) -> bool {
    use std::os::unix::fs::MetadataExt as _;
    a.dev() == b.dev()
}

#[cfg(windows)]
fn same_filesystem(
    a_path: &Path,
    _a: &std::fs::Metadata,
    b_path: &Path,
    _b: &std::fs::Metadata,
) -> bool {
    windows_volume_name(a_path).is_some_and(|volume| windows_volume_name(b_path) == Some(volume))
}

#[cfg(windows)]
fn windows_volume_name(path: &Path) -> Option<Vec<u16>> {
    use std::os::windows::ffi::OsStrExt as _;
    use windows_sys::Win32::Storage::FileSystem::{
        GetVolumeNameForVolumeMountPointW, GetVolumePathNameW,
    };

    let path = path
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    // Both APIs document MAX_PATH-sized output buffers for volume paths and
    // names. Failure is uncertainty, which deliberately keeps the checkout
    // live.
    let mut mount = vec![0_u16; 261];
    // SAFETY: `path` is nul-terminated and `mount` is writable for the stated
    // number of UTF-16 code units.
    if unsafe { GetVolumePathNameW(path.as_ptr(), mount.as_mut_ptr(), mount.len() as u32) } == 0 {
        return None;
    }
    let mut volume = vec![0_u16; 261];
    // SAFETY: the successful call above left `mount` nul-terminated, and
    // `volume` is writable for the stated number of UTF-16 code units.
    if unsafe {
        GetVolumeNameForVolumeMountPointW(mount.as_ptr(), volume.as_mut_ptr(), volume.len() as u32)
    } == 0
    {
        return None;
    }
    volume.truncate(volume.iter().position(|unit| *unit == 0)?);
    Some(volume)
}

#[cfg(not(any(unix, windows)))]
fn same_filesystem(
    _a_path: &Path,
    _a: &std::fs::Metadata,
    _b_path: &Path,
    _b: &std::fs::Metadata,
) -> bool {
    false
}

/// CAS paths reachable from the builds that live checkouts still depend on.
///
/// Recursing into output trees is the point: the descriptor blobs are tiny and
/// the leaf artifacts are where the bytes are, so rooting that stopped at the
/// top level would protect nothing worth protecting. Every read here is
/// tolerant -- a blob that has already been evicted, or that no longer parses,
/// simply roots less, and rooting less can only mean collecting sooner.
fn rooted_objects(store: &Path, identities: &BTreeSet<String>) -> Result<HashSet<PathBuf>> {
    let mut actions = BTreeSet::new();
    for identity in identities {
        // One manifest this build cannot read is not worth abandoning a sweep
        // over. It roots nothing, which can only mean collecting sooner.
        let manifest_actions = match task_manifest_actions(store, identity) {
            Ok(actions) => actions,
            Err(error) => {
                log::debug!("could not read the manifest for {identity}: {error}");
                continue;
            }
        };
        actions.extend(manifest_actions);
    }
    Ok(rooted_action_objects(store, actions))
}

/// Return every local CAS path needed to restore the supplied actions.
fn rooted_action_objects(
    store: &Path,
    actions: impl IntoIterator<Item = CacheDigest>,
) -> HashSet<PathBuf> {
    let cas = LocalCas::new(store);
    let mut rooted = HashSet::new();
    let mut visited = BTreeSet::new();
    for action in actions {
        let Some(result) = read_action_result(store, &action) else {
            continue;
        };
        root_digest(&cas, &mut rooted, &result.action);
        if let Some(metadata) = &result.metadata {
            root_digest(&cas, &mut rooted, metadata);
            // The metadata blob is a descriptor too: it names the captured
            // stdout and stderr, and a restore reads both. Stopping at the
            // descriptor would leave the diagnostics of every action
            // unrooted -- including the one empty blob that every silent
            // compilation shares, which is enough on its own to turn a
            // rooted hit back into a miss.
            if let Some(rustc) = read_rustc_metadata(&cas, metadata) {
                root_digest(&cas, &mut rooted, &rustc.stdout);
                root_digest(&cas, &mut rooted, &rustc.stderr);
            }
        }
        if let Some(output_root) = &result.output_root {
            root_digest(&cas, &mut rooted, output_root);
            root_tree(&cas, output_root, &mut rooted, &mut visited);
        }
    }
    rooted
}

fn read_action_result(store: &Path, action: &CacheDigest) -> Option<RemoteActionResult> {
    let path = tuist_cargo_cache_core::LocalActionCache::new(store)
        .path_for(action)
        .ok()?;
    let bytes = std::fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn root_tree(
    cas: &LocalCas,
    output_root: &CacheDigest,
    rooted: &mut HashSet<PathBuf>,
    visited: &mut BTreeSet<CacheDigest>,
) {
    let mut pending = vec![output_root.clone()];
    while let Some(digest) = pending.pop() {
        if !visited.insert(digest.clone()) {
            continue;
        }
        let Some(directory) = read_directory(cas, &digest) else {
            continue;
        };
        for file in &directory.files {
            root_digest(cas, rooted, &file.digest);
        }
        for child in &directory.directories {
            root_digest(cas, rooted, &child.digest);
            pending.push(child.digest.clone());
        }
    }
}

fn read_rustc_metadata(cas: &LocalCas, digest: &CacheDigest) -> Option<RustcMetadata> {
    let bytes = std::fs::read(cas.path_for(digest).ok()?).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn read_directory(cas: &LocalCas, digest: &CacheDigest) -> Option<CacheDirectory> {
    let bytes = std::fs::read(cas.path_for(digest).ok()?).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn root_digest(cas: &LocalCas, rooted: &mut HashSet<PathBuf>, digest: &CacheDigest) {
    if let Ok(path) = cas.path_for(digest) {
        rooted.insert(path);
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Removal {
    Removed,
    Missing,
    Blocked,
}

fn remove(path: &Path) -> Result<Removal> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(Removal::Removed),
        // A concurrent build may have evicted or replaced it already.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Removal::Missing),
        // Windows refuses to unlink a file another process holds open, which is
        // what a concurrent build reading this blob looks like. Skipping it
        // leaves the store over budget until the next sweep; failing would
        // abandon the sweep and leave it over budget for longer.
        Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied => {
            log::debug!("could not evict {}: {error}", path.display());
            Ok(Removal::Blocked)
        }
        Err(error) => Err(error).wrap_err_with(|| format!("failed to evict {}", path.display())),
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
struct ObjectEvictions {
    removed_objects: u64,
    removed_bytes: u64,
    remaining_bytes: u64,
}

/// Evict sorted objects without crossing the checkout-protection boundary
/// when an unrooted object cannot be removed.
fn evict_objects(
    objects: &[Entry],
    rooted: &HashSet<PathBuf>,
    mut live_bytes: u64,
    max_bytes: u64,
    mut remove_file: impl FnMut(&Path) -> Result<Removal>,
) -> Result<ObjectEvictions> {
    let mut outcome = ObjectEvictions::default();
    let mut blocked_unrooted = false;
    for entry in objects {
        if live_bytes <= max_bytes {
            break;
        }
        let is_rooted = rooted.contains(&entry.path);
        if is_rooted && blocked_unrooted {
            // A locked unrooted blob is temporarily part of the irreducible
            // store. Deleting a live checkout's artifacts in its place would
            // invert the protection ordering this collector promises.
            break;
        }
        match remove_file(&entry.path)? {
            Removal::Removed => {
                live_bytes = live_bytes.saturating_sub(entry.size);
                outcome.removed_objects += 1;
                outcome.removed_bytes += entry.size;
            }
            Removal::Missing => live_bytes = live_bytes.saturating_sub(entry.size),
            Removal::Blocked if !is_rooted => blocked_unrooted = true,
            Removal::Blocked => {}
        }
    }
    outcome.remaining_bytes = live_bytes;
    Ok(outcome)
}

/// Whether an action result references an object the store no longer has.
///
/// The digests checked here are exactly the ones `LocalActionCache::store`
/// requires. If the sweep checked fewer, eviction could leave an entry that
/// cannot be republished -- `store` would reject the identical result for a
/// missing blob while the index still claimed to hold it.
///
/// Presence is all that is checked, not content. Verifying would re-hash a
/// large fraction of the store on every sweep, which a chore could afford and
/// an automatic sweep cannot; it would also refresh the access time of every
/// descriptor blob while leaving the artifacts alone, biasing the very
/// ordering this module depends on. A blob that is present but corrupt now
/// keeps its result and turns into a miss on restore, and both CAS write paths
/// republish over a corrupt blob rather than trusting it.
///
/// Only the top-level objects are checked; a result whose output tree lost a
/// nested object still restores as a miss, which is safe.
fn action_result_is_dangling(
    cas: &LocalCas,
    path: &Path,
    virtually_removed: &HashSet<PathBuf>,
) -> Result<bool> {
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", path.display()));
        }
    };
    // An unparseable result is already useless; the cache rejects it on read.
    let Ok(result) = serde_json::from_slice::<RemoteActionResult>(&bytes) else {
        return Ok(false);
    };
    for digest in [
        Some(&result.action),
        result.metadata.as_ref(),
        result.output_root.as_ref(),
    ]
    .into_iter()
    .flatten()
    {
        match cas.path_for(digest) {
            Ok(path) => {
                if virtually_removed.contains(&path) || !path.exists() {
                    return Ok(true);
                }
            }
            // A digest the CAS cannot even address is not one it can hold.
            Err(_) => return Ok(true),
        }
    }
    Ok(false)
}

struct Entry {
    path: PathBuf,
    size: u64,
    used: SystemTime,
}

fn walk_files(root: &Path) -> Result<Vec<Entry>> {
    let mut entries = Vec::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let listing = match std::fs::read_dir(&directory) {
            Ok(listing) => listing,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => {
                return Err(error)
                    .wrap_err_with(|| format!("failed to read {}", directory.display()));
            }
        };
        for entry in listing {
            let entry = entry?;
            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                // A concurrent build may be publishing into the store.
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error.into()),
            };
            if metadata.is_dir() {
                pending.push(entry.path());
            } else if metadata.is_file() {
                let used = metadata
                    .accessed()
                    .or_else(|_| metadata.modified())
                    .unwrap_or(SystemTime::UNIX_EPOCH);
                entries.push(Entry {
                    path: entry.path(),
                    size: metadata.len(),
                    used,
                });
            }
        }
    }
    Ok(entries)
}

fn read_dir_or_empty(root: &Path) -> Result<Vec<std::fs::DirEntry>> {
    match std::fs::read_dir(root) {
        Ok(entries) => entries
            .collect::<std::io::Result<Vec<_>>>()
            .map_err(Into::into),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(error).wrap_err_with(|| format!("failed to read {}", root.display())),
    }
}

fn digest_from_path(path: &Path, action_result: bool) -> Option<CacheDigest> {
    let name = path.file_name()?.to_str()?;
    let name = if action_result {
        name.strip_suffix(".json")?
    } else {
        name
    };
    let (hash, size) = name.rsplit_once('-')?;
    let algorithm = path.parent()?.parent()?.file_name()?.to_str()?.to_string();
    let digest = CacheDigest {
        algorithm,
        hash: hash.to_string(),
        size: size.parse().ok()?,
    };
    digest.validate().ok()?;
    Some(digest)
}

fn addressed_digest(store: &Path, path: &Path, action_result: bool) -> Option<CacheDigest> {
    let digest = digest_from_path(path, action_result)?;
    let canonical = if action_result {
        tuist_cargo_cache_core::LocalActionCache::new(store)
            .path_for(&digest)
            .ok()?
    } else {
        LocalCas::new(store).path_for(&digest).ok()?
    };
    (canonical == path).then_some(digest)
}

fn cached_tree_bytes(cache: &mut BTreeMap<PathBuf, u64>, root: &Path) -> u64 {
    *cache
        .entry(root.to_path_buf())
        .or_insert_with(|| tree_bytes(root))
}

fn tree_bytes(root: &Path) -> u64 {
    let Ok(root_metadata) = std::fs::metadata(root) else {
        return 0;
    };
    if root_metadata.is_file() {
        return root_metadata.len();
    }
    let Ok(entries) = std::fs::read_dir(root) else {
        return 0;
    };
    let mut bytes = 0_u64;
    let mut pending = entries
        .filter_map(std::result::Result::ok)
        .map(|entry| entry.path())
        .collect::<Vec<_>>();
    while let Some(path) = pending.pop() {
        let Ok(metadata) = std::fs::symlink_metadata(&path) else {
            continue;
        };
        if metadata.is_file() {
            bytes = bytes.saturating_add(metadata.len());
        } else if metadata.is_dir()
            && let Ok(entries) = std::fs::read_dir(path)
        {
            pending.extend(
                entries
                    .filter_map(std::result::Result::ok)
                    .map(|entry| entry.path()),
            );
        }
    }
    bytes
}

#[cfg(test)]
#[path = "store_tests.rs"]
mod tests;

/// [`write_atomic`] without the sync: for records every build rewrites and
/// that a torn or missing file only makes one build older.
fn write_advisory(path: &Path, contents: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| eyre::eyre!("path has no parent: {}", path.display()))?;
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-")
        .tempfile_in(parent)?;
    use std::io::Write as _;
    temporary.write_all(contents)?;
    temporary
        .persist(path)
        .map_err(|error| error.error)
        .wrap_err_with(|| format!("failed atomic write: {}", path.display()))?;
    Ok(())
}

fn write_atomic(path: &Path, contents: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| eyre::eyre!("path has no parent: {}", path.display()))?;
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-")
        .tempfile_in(parent)?;
    use std::io::Write as _;
    temporary.write_all(contents)?;
    temporary.as_file_mut().sync_all()?;
    temporary
        .persist(path)
        .map_err(|error| error.error)
        .wrap_err_with(|| format!("failed atomic write: {}", path.display()))?;
    Ok(())
}
