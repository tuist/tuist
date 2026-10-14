//! Portable Cargo scheduler state carried beside an exported action closure.

use crate::config::Config;
use eyre::{Context as _, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{File, FileTimes};
use std::path::{Component, Path, PathBuf};
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::UNIX_EPOCH;
use tuist_cargo_cache_core::{CacheDigest, LocalCas};
use tuist_cargo_cache_store::{ExportAdditions, WorkspaceTarget};

pub(crate) const ATTACHMENT: &str = "cargo-workspace-state-v1";
const VERSION: u8 = 1;

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Bundle {
    version: u8,
    workspaces: Vec<WorkspaceState>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct WorkspaceState {
    workspace_root: PathBuf,
    signature: CacheDigest,
    inline_archive: CacheDigest,
    inline_files: Vec<FileMetadata>,
    references: Vec<FileReference>,
    symlinks: Vec<Symlink>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileReference {
    path: PathBuf,
    source: FileSource,
    mode: u32,
    modified_secs: u64,
    modified_nanos: u32,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileMetadata {
    path: PathBuf,
    mode: u32,
    modified_secs: u64,
    modified_nanos: u32,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
enum FileSource {
    Cas(CacheDigest),
    CargoCache,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Symlink {
    path: PathBuf,
    target: PathBuf,
    directory: bool,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct RestoreOutcome {
    pub(crate) files: u64,
    pub(crate) referenced_bytes: u64,
}

/// Capture every recorded Cargo target as a manifest plus an inline metadata tar.
pub(crate) fn capture(store: &Path, targets: &[WorkspaceTarget]) -> Result<ExportAdditions> {
    let executable = std::env::current_exe()?;
    let executable_digest = CacheDigest::blake3_file(&executable)?;
    let cas = LocalCas::new(store);
    let mut objects = BTreeSet::new();
    let mut workspaces = Vec::new();
    for target in targets {
        if !target.target_dir.is_dir() || !target.workspace_root.is_dir() {
            continue;
        }
        workspaces.push(capture_workspace(
            &cas,
            target,
            &executable_digest,
            &mut objects,
        )?);
    }
    if workspaces.is_empty() {
        return Ok(ExportAdditions::default());
    }
    let bytes = serde_json::to_vec(&Bundle {
        version: VERSION,
        workspaces,
    })?;
    let digest = CacheDigest::blake3(&bytes);
    cas.store_bytes(&digest, &bytes)?;
    objects.insert(digest.clone());
    Ok(ExportAdditions {
        attachments: BTreeMap::from([(ATTACHMENT.to_owned(), digest)]),
        objects,
    })
}

fn capture_workspace(
    cas: &LocalCas,
    target: &WorkspaceTarget,
    executable_digest: &CacheDigest,
    objects: &mut BTreeSet<CacheDigest>,
) -> Result<WorkspaceState> {
    let temporary = tempfile::NamedTempFile::new_in(cas.root())?;
    let mut archive = tar::Builder::new(temporary.reopen()?);
    let mut references = Vec::new();
    let mut inline_files = Vec::new();
    let mut symlinks = Vec::new();
    for path in tree_entries(&target.target_dir)? {
        let relative = path.strip_prefix(&target.target_dir)?.to_path_buf();
        validate_relative_path(&relative)?;
        let metadata = std::fs::symlink_metadata(&path)?;
        let kind = metadata.file_type();
        if kind.is_dir() {
            archive.append_dir(&relative, &path)?;
        } else if kind.is_symlink() {
            let link = std::fs::read_link(&path)?;
            validate_link(&relative, &link)?;
            symlinks.push(Symlink {
                path: relative,
                target: link,
                directory: path.metadata().is_ok_and(|metadata| metadata.is_dir()),
            });
        } else if kind.is_file() {
            let digest = CacheDigest::blake3_file(&path)?;
            let source = if digest == *executable_digest {
                Some(FileSource::CargoCache)
            } else if cas.path_for(&digest)?.is_file() {
                objects.insert(digest.clone());
                Some(FileSource::Cas(digest))
            } else {
                None
            };
            if let Some(source) = source {
                let (modified_secs, modified_nanos) = modified_parts(&metadata);
                references.push(FileReference {
                    path: relative,
                    source,
                    mode: file_mode(&metadata),
                    modified_secs,
                    modified_nanos,
                });
            } else {
                archive.append_path_with_name(&path, &relative)?;
                let (modified_secs, modified_nanos) = modified_parts(&metadata);
                inline_files.push(FileMetadata {
                    path: relative,
                    mode: file_mode(&metadata),
                    modified_secs,
                    modified_nanos,
                });
            }
        }
    }
    archive.finish()?;
    drop(archive);
    let inline_archive = CacheDigest::blake3_file(temporary.path())?;
    cas.store_file(&inline_archive, temporary.path())?;
    objects.insert(inline_archive.clone());
    Ok(WorkspaceState {
        workspace_root: target.workspace_root.clone(),
        signature: workspace_signature(&target.workspace_root)?,
        inline_archive,
        inline_files,
        references,
        symlinks,
    })
}

/// Restore the state matching the current Cargo workspace into an empty target.
pub(crate) fn restore(
    config: &Config,
    store: &Path,
    attachment: &CacheDigest,
    workspace_root: &Path,
    target_dir: &Path,
    target_requested: bool,
) -> Result<Option<RestoreOutcome>> {
    let cas = LocalCas::new(store);
    let bundle_path = cas
        .find(attachment)?
        .ok_or_else(|| eyre::eyre!("workspace-state attachment is missing"))?;
    let bundle: Bundle = serde_json::from_slice(&std::fs::read(bundle_path)?)?;
    if bundle.version != VERSION || bundle.workspaces.is_empty() {
        bail!("unsupported or invalid Cargo workspace-state attachment");
    }
    let signature = workspace_signature(workspace_root)?;
    let Some(state) = bundle
        .workspaces
        .iter()
        .find(|state| state.workspace_root == workspace_root)
        .or_else(|| {
            let mut matches = bundle
                .workspaces
                .iter()
                .filter(|state| state.signature == signature);
            let first = matches.next()?;
            matches.next().is_none().then_some(first)
        })
    else {
        return Ok(None);
    };
    validate_state(state)?;
    let destination = crate::target::place(config, workspace_root, target_dir, target_requested)
        .unwrap_or_else(|| target_dir.to_path_buf());
    if destination.exists() && std::fs::read_dir(&destination)?.next().is_some() {
        log::debug!(
            "leaving the non-empty target directory {} alone",
            destination.display()
        );
        return Ok(None);
    }
    let parent = destination
        .parent()
        .ok_or_else(|| eyre::eyre!("target directory has no parent"))?;
    std::fs::create_dir_all(parent)?;
    let staging = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-workspace-state-")
        .tempdir_in(parent)?;
    let staged_target = staging.path().join("target");
    std::fs::create_dir(&staged_target)?;
    unpack_inline(&cas, &state.inline_archive, &staged_target)?;
    for metadata in &state.inline_files {
        set_file_metadata(
            &staged_target.join(&metadata.path),
            metadata.mode,
            metadata.modified_secs,
            metadata.modified_nanos,
        )?;
    }
    let executable = std::env::current_exe()?;
    let bytes = materialize_references(&cas, &executable, &staged_target, &state.references)?;
    restore_symlinks(&staged_target, &state.symlinks)?;
    if destination.exists() {
        std::fs::remove_dir(&destination).wrap_err_with(|| {
            format!(
                "could not replace empty target directory {}",
                destination.display()
            )
        })?;
    }
    std::fs::rename(&staged_target, &destination)?;
    crate::target::touch_managed(config, workspace_root, target_dir);
    Ok(Some(RestoreOutcome {
        files: state.references.len() as u64,
        referenced_bytes: bytes,
    }))
}

fn unpack_inline(cas: &LocalCas, digest: &CacheDigest, destination: &Path) -> Result<()> {
    let path = cas
        .find(digest)?
        .ok_or_else(|| eyre::eyre!("workspace-state inline archive is missing"))?;
    let mut archive = tar::Archive::new(File::open(path)?);
    for entry in archive.entries()? {
        let mut entry = entry?;
        let path = entry.path()?.into_owned();
        validate_relative_path(&path)?;
        let kind = entry.header().entry_type();
        if !kind.is_file() && !kind.is_dir() && !kind.is_gnu_sparse() {
            bail!("workspace-state archive contains a non-file entry");
        }
        if !entry.unpack_in(destination)? {
            bail!("workspace-state archive contains an unsafe path");
        }
    }
    Ok(())
}

fn materialize_references(
    cas: &LocalCas,
    executable: &Path,
    destination: &Path,
    references: &[FileReference],
) -> Result<u64> {
    let sources = references
        .iter()
        .map(|reference| {
            let source = match &reference.source {
                FileSource::Cas(digest) => cas.path_for(digest)?,
                FileSource::CargoCache => executable.to_path_buf(),
            };
            let size = std::fs::metadata(&source)?.len();
            Ok((reference, source, size))
        })
        .collect::<Result<Vec<_>>>()?;
    let workers = std::thread::available_parallelism()
        .map(usize::from)
        .unwrap_or(1)
        .min(sources.len().max(1));
    let next = AtomicUsize::new(0);
    let error = Mutex::new(None);
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some((reference, source, _)) = sources.get(index) else {
                        break;
                    };
                    if error.lock().unwrap().is_some() {
                        break;
                    }
                    let result = restore_reference(destination, reference, source);
                    if let Err(found) = result {
                        *error.lock().unwrap() = Some(found);
                        break;
                    }
                }
            });
        }
    });
    if let Some(error) = error.into_inner().unwrap() {
        return Err(error);
    }
    Ok(sources.iter().map(|(_, _, size)| size).sum())
}

fn restore_reference(root: &Path, reference: &FileReference, source: &Path) -> Result<()> {
    let destination = root.join(&reference.path);
    let copied = reflink_copy::reflink_or_copy(source, &destination)?;
    let _ = copied;
    set_file_metadata(
        &destination,
        reference.mode,
        reference.modified_secs,
        reference.modified_nanos,
    )
}

fn restore_symlinks(root: &Path, links: &[Symlink]) -> Result<()> {
    for link in links {
        let destination = root.join(&link.path);
        create_symlink(&link.target, &destination, link.directory)?;
    }
    Ok(())
}

fn validate_state(state: &WorkspaceState) -> Result<()> {
    state.signature.validate()?;
    state.inline_archive.validate()?;
    for metadata in &state.inline_files {
        validate_relative_path(&metadata.path)?;
    }
    for reference in &state.references {
        validate_relative_path(&reference.path)?;
        if let FileSource::Cas(digest) = &reference.source {
            digest.validate()?;
        }
    }
    for link in &state.symlinks {
        validate_relative_path(&link.path)?;
        validate_link(&link.path, &link.target)?;
    }
    Ok(())
}

fn tree_entries(root: &Path) -> Result<Vec<PathBuf>> {
    let mut found = Vec::new();
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let mut entries = std::fs::read_dir(&directory)?.collect::<std::io::Result<Vec<_>>>()?;
        entries.sort_by_key(std::fs::DirEntry::file_name);
        for entry in entries {
            let path = entry.path();
            if entry.file_type()?.is_dir() {
                pending.push(path.clone());
            }
            found.push(path);
        }
    }
    found.sort();
    Ok(found)
}

fn workspace_signature(root: &Path) -> Result<CacheDigest> {
    let mut bytes = b"cargo-workspace-state-v1\0".to_vec();
    for name in ["Cargo.toml", "Cargo.lock"] {
        let path = root.join(name);
        if path.is_file() {
            bytes.extend_from_slice(name.as_bytes());
            bytes.push(0);
            bytes.extend_from_slice(&std::fs::read(path)?);
            bytes.push(0);
        }
    }
    Ok(CacheDigest::blake3(&bytes))
}

fn validate_relative_path(path: &Path) -> Result<()> {
    if path.as_os_str().is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, Component::Normal(_)))
    {
        bail!("workspace state contains unsafe path {}", path.display());
    }
    Ok(())
}

fn validate_link(path: &Path, target: &Path) -> Result<()> {
    if target.is_absolute() {
        bail!("workspace state contains unsafe link {}", path.display());
    }
    let mut depth = path
        .parent()
        .map_or(0, |parent| parent.components().count());
    for component in target.components() {
        match component {
            Component::Normal(_) => depth += 1,
            Component::CurDir => {}
            Component::ParentDir if depth > 0 => depth -= 1,
            _ => bail!("workspace state contains unsafe link {}", path.display()),
        }
    }
    Ok(())
}

fn modified_parts(metadata: &std::fs::Metadata) -> (u64, u32) {
    metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| (duration.as_secs(), duration.subsec_nanos()))
        .unwrap_or_default()
}

#[cfg(unix)]
fn file_mode(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::MetadataExt as _;
    metadata.mode()
}

#[cfg(not(unix))]
fn file_mode(metadata: &std::fs::Metadata) -> u32 {
    u32::from(metadata.permissions().readonly())
}

fn set_file_metadata(path: &Path, mode: u32, secs: u64, nanos: u32) -> Result<()> {
    if nanos >= 1_000_000_000 {
        bail!("workspace state contains an invalid timestamp");
    }
    let modified = UNIX_EPOCH
        .checked_add(std::time::Duration::new(secs, nanos))
        .ok_or_else(|| eyre::eyre!("workspace state contains an out-of-range timestamp"))?;
    #[cfg(unix)]
    File::options()
        .read(true)
        .open(path)?
        .set_times(FileTimes::new().set_modified(modified))
        .wrap_err_with(|| format!("could not restore the timestamp of {}", path.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
            .wrap_err_with(|| format!("could not restore the mode of {}", path.display()))?;
    }
    #[cfg(not(unix))]
    {
        let mut permissions = std::fs::metadata(path)?.permissions();
        permissions.set_readonly(false);
        std::fs::set_permissions(path, permissions.clone())?;
        File::options()
            .write(true)
            .open(path)?
            .set_times(FileTimes::new().set_modified(modified))
            .wrap_err_with(|| format!("could not restore the timestamp of {}", path.display()))?;
        permissions.set_readonly(mode == 1);
        std::fs::set_permissions(path, permissions)
            .wrap_err_with(|| format!("could not restore the permissions of {}", path.display()))?;
    }
    Ok(())
}

#[cfg(unix)]
fn create_symlink(target: &Path, destination: &Path, _directory: bool) -> Result<()> {
    std::os::unix::fs::symlink(target, destination)?;
    Ok(())
}

#[cfg(windows)]
fn create_symlink(target: &Path, destination: &Path, directory: bool) -> Result<()> {
    if directory {
        std::os::windows::fs::symlink_dir(target, destination)?;
    } else {
        std::os::windows::fs::symlink_file(target, destination)?;
    }
    Ok(())
}
