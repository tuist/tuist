//! Cache machinery shared by every compiler adapter.
//!
//! Restoring an action result is the same problem whatever produced it: verify
//! blobs against their digests, stage them beside their destination, and rename
//! them into place or roll the whole set back. Only deciding *which* files an
//! action should produce is adapter-specific, so that part stays with each
//! adapter and everything here is driven by a plain file list.

use crate::session::{self, STAGING_ENV};
use eyre::{Result, WrapErr as _, bail};
use serde::Serialize;
use serde::de::DeserializeOwned;
use std::ffi::OsStr;
use std::io::{Read as _, Write as _};
use std::path::{Path, PathBuf};
use std::process::{ExitCode, ExitStatus};
use tuist_cargo_cache_core::{
    ActionDiagnostic, AgentRequest, AgentResponse, CacheDigest, CacheFileNode, RestoreStats,
    canonical_json,
};
use tuist_cargo_cache_rustc::PathMapping;

/// A compilation reconstructed from the cache.
pub(crate) struct CachedCompilation {
    pub(crate) action: CacheDigest,
    pub(crate) stdout: Vec<u8>,
    pub(crate) stderr: Vec<u8>,
    pub(crate) outputs: Vec<CachedOutput>,
    pub(crate) restore: RestoreStats,
}

/// One restored file and the properties it must have on disk.
pub(crate) struct CachedOutput {
    pub(crate) path: PathBuf,
    pub(crate) digest: CacheDigest,
    pub(crate) executable: bool,
    pub(crate) mode: u32,
}

/// Restored files waiting to be renamed into place.
pub(crate) struct StagedOutputs {
    /// Kept alive so the staging directory outlives the files inside it.
    pub(crate) directory: tempfile::TempDir,
    pub(crate) files: Vec<(tempfile::TempPath, PathBuf)>,
}

/// How a cached output reached its staging path.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Materialization {
    Reflink,
    Hardlink,
    Copy,
}

/// Look up every blob at once, failing if the action is missing any of them.
pub(crate) fn find_blobs(digests: &[CacheDigest]) -> Result<Vec<PathBuf>> {
    let responses = session::request_agent(&[AgentRequest::FindBlobs {
        digests: digests.to_vec(),
    }])?;
    let Some(response) = responses.into_iter().next() else {
        bail!("cache agent did not return a blob lookup response");
    };
    match response {
        AgentResponse::Blobs { paths } if paths.len() == digests.len() => paths
            .into_iter()
            .zip(digests)
            .map(|(path, digest)| match path {
                Some(path) => Ok(path),
                None => bail!("cached action is missing blob {}", digest.hash),
            })
            .collect(),
        AgentResponse::Blobs { .. } => {
            bail!("cache agent returned an incomplete blob lookup response")
        }
        AgentResponse::Blob { path: Some(path) } if digests.len() == 1 => Ok(vec![path]),
        AgentResponse::Blob { path: None } if digests.len() == 1 => {
            let digest = &digests[0];
            bail!("cached action is missing blob {}", digest.hash)
        }
        AgentResponse::Error { message } => bail!(message),
        _ => bail!("cache agent returned an unexpected blob lookup response"),
    }
}

/// Read a JSON record, requiring the exact canonical bytes its digest names.
pub(crate) fn read_canonical_blob<T>(
    path: &Path,
    digest: &CacheDigest,
    description: &str,
) -> Result<T>
where
    T: DeserializeOwned + Serialize,
{
    let bytes = read_verified_blob(path, digest, description)?;
    let value = serde_json::from_slice(&bytes)
        .wrap_err_with(|| format!("cached {description} is not valid JSON"))?;
    if canonical_json(&value)? != bytes {
        bail!("cached {description} is not canonical JSON");
    }
    Ok(value)
}

/// Read a blob and confirm it hashes to the digest that named it.
pub(crate) fn read_verified_blob(
    path: &Path,
    digest: &CacheDigest,
    description: &str,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)?.read_to_end(&mut bytes)?;
    if !digest.matches_bytes(&bytes)? {
        bail!("cached {description} failed digest verification");
    }
    Ok(bytes)
}

/// Clone a verified cache object into a staging directory beside its
/// destination.
pub(crate) fn stage_verified_cached_output(
    directory: &Path,
    index: usize,
    source: &Path,
    node: &CacheFileNode,
) -> Result<(tempfile::TempPath, Materialization)> {
    stage_verified_cached_output_with(directory, index, source, node, |source, destination| {
        reflink_copy::reflink(source, destination)
    })
}

/// [`stage_verified_cached_output`] with the clone spelled out, so a test can
/// exercise what happens on a filesystem that has no clone support without
/// needing one.
pub(crate) fn stage_verified_cached_output_with(
    directory: &Path,
    index: usize,
    source: &Path,
    node: &CacheFileNode,
    clone: impl FnOnce(&Path, &Path) -> std::io::Result<()>,
) -> Result<(tempfile::TempPath, Materialization)> {
    let temporary = directory.join(format!("output-{index}"));
    let materialization = materialize_cached_output(source, &temporary, node, clone)
        .wrap_err_with(|| format!("failed to materialize cached output {}", node.name))?;
    let temporary = tempfile::TempPath::try_from_path(temporary)?;
    // A hard link *is* the store's object, so its mode is the object's mode
    // and cannot be adjusted for this one destination. It is deliberately left
    // read-only: a compiler that would write over a restored output finds it
    // unwritable and says so, instead of rewriting the bytes every other
    // checkout linked to. `clear_linked_outputs` unlinks it before tuist_cargo_cache runs a
    // real compiler, which is how a rebuild through tuist_cargo_cache still writes here.
    if materialization != Materialization::Hardlink {
        make_owner_writable(&temporary)?;
    }
    // Deliberately not fsynced. These are build artifacts in a target
    // directory, and cargo does not sync its own outputs either, so syncing
    // here buys no durability the build relies on -- it only costs one fsync
    // per restored file, which on a large workspace is most of the restore.
    // `source` is a session-verified CAS path returned by `FindBlobs`. Hashing
    // the result again would read every output a second time and, for a
    // reflink, eagerly fault the shared data blocks that cloning was intended
    // to leave deferred. A reflink is a CoW snapshot and the copy fallback
    // reports the number of bytes it wrote, so checking the staged length is
    // sufficient after the agent's content verification.
    if std::fs::metadata(&temporary)?.len() != node.digest.size {
        bail!(
            "materialized cached output has the wrong size: {}",
            node.name
        );
    }
    // A cache hit stands in for work Cargo decided was stale. Reflinks and
    // some copy implementations preserve the CAS blob's older mtime, which
    // can leave this output older than the dependency that triggered the
    // invocation and make Cargo repeat it forever. A real compiler would have
    // produced the file now, so give the restored output the same ordering.
    //
    // A hard link has no timestamp of its own, so this moves the store
    // object's. That is the ordering every link of it wants -- an output is
    // only restored because something intends to use it now -- but it does
    // cost this session's remembered identity for that blob, which the agent
    // re-establishes by reading it again if some later action asks for the
    // same bytes. Output blobs are asked for about once per build, so the
    // re-read is rare and a copy of every restored byte is not.
    set_modified_now(&temporary)?;
    // Last, because this is the step that can take away the access the ones
    // above needed. A recorded mode carries no promise of read permission --
    // nothing rejects `0o200` -- and a staged file that cannot be opened is
    // one nothing else here could have finished with.
    if materialization != Materialization::Hardlink {
        apply_file_mode(&temporary, node.mode, node.executable)?;
    }
    Ok((temporary, materialization))
}

/// Put the store's bytes at `destination`: share them where the filesystem
/// can, copy them where it cannot.
///
/// A reflink comes first wherever it works. The restored file is then an
/// independent inode that merely shares data blocks, so it carries its own
/// mode and timestamps and a writer breaks the sharing rather than the store.
///
/// A hard link shares the object itself, which is why it is second and why the
/// object is made read-only before a link to it exists. It is not a nicety on
/// a filesystem with no clone support: ext4 is what most Linux CI and most
/// Linux developer machines run, and there the alternative is copying every
/// restored byte -- on a warm build of a mid-size workspace, gigabytes of
/// them.
fn materialize_cached_output(
    source: &Path,
    destination: &Path,
    node: &CacheFileNode,
    clone: impl FnOnce(&Path, &Path) -> std::io::Result<()>,
) -> Result<Materialization> {
    if clone(source, destination).is_ok() {
        return Ok(Materialization::Reflink);
    }
    // A failed clone may still have created the destination, and a hard link
    // will not replace an existing name. The staging path is this process's
    // own, so removing it takes nothing from anybody.
    let _ = std::fs::remove_file(destination);
    if session::restore_hardlink_requested() && hard_link_cached_output(source, destination, node) {
        return Ok(Materialization::Hardlink);
    }
    let written = std::fs::copy(source, destination)?;
    if written != node.digest.size {
        bail!(
            "materialized cached output has the wrong size: {}",
            node.name
        );
    }
    Ok(Materialization::Copy)
}

/// Link the store's object into place, or report that this output cannot have
/// one. Every failure here is answered by copying, so none of them is an
/// error.
#[cfg(unix)]
fn hard_link_cached_output(source: &Path, destination: &Path, node: &CacheFileNode) -> bool {
    use std::os::unix::fs::MetadataExt as _;
    use std::os::unix::fs::PermissionsExt as _;
    let wanted = linkable_mode(node);
    if !readable_by_owner(wanted) {
        return false;
    }
    // Inspected and relabelled through one open handle, so the object this
    // decides about is the object it changes. Reading a path's mode and then
    // setting the mode of that path are two lookups of a name, and a name can
    // come to mean a different file between them -- the store republishes a
    // blob it found torn by renaming a new one over it. The permissions would
    // then land on bytes nothing here ever checked, which is how a rule about
    // what may be relabelled stops being a rule.
    let Ok(file) = std::fs::File::open(source) else {
        return false;
    };
    // Held for the rest of this function, and the reason the mode is read
    // after it rather than before.
    //
    // "Only ever take permissions away" is not a property a process can
    // establish on its own, because it compares against a mode it read
    // earlier. Two restores of one object can each read the same starting
    // mode, each find its own target narrower than that, and apply them in
    // an order where the second undoes the first: an output already linked
    // and verified as owner-private is handed back the readership the other
    // one wanted. Both followed the rule against the value they had; the
    // value was stale.
    //
    // Reading under the lock makes the comparison mean what it says, since
    // nothing else relabels an object without holding this. The lock is
    // never waited on: two restores wanting the same object at the same
    // instant is rare, and copying is a fine answer for the loser.
    if !take_exclusive_lock(&file) {
        return false;
    }
    let Ok(metadata) = file.metadata() else {
        return false;
    };
    let current = metadata.permissions().mode() & 0o7777;
    // A link carries no mode of its own, so the object's mode is the mode of
    // every path linked to it, and this restore cannot be the only one holding
    // an opinion about it. Matching already is the ordinary case and the one
    // that keeps this cheap: the same bytes restored into a second target
    // directory want the mode the first one gave them.
    //
    // Otherwise the object is relabelled, under one rule: a relabel may only
    // take readership away, and may never touch whether the object runs.
    // Restores of the same digest race each other, so the mode has to be safe
    // under whichever order they land in, and the way to get that is to let it
    // move in one direction only.
    //
    // Readership tightens safely in any order: the worst outcome is an output
    // less readable than its record asked for, and the owner running the build
    // can still read it. Widening it is not safe -- it would publish another
    // checkout's owner-private artifact to every local user who can reach that
    // directory.
    //
    // The executable bit is neither. It is not a degree of access that can be
    // given up harmlessly: taking it from a shared object stops every binary
    // already linked to it from running at all, and a restore of these bytes
    // as a non-executable output has no business deciding that. So it is not
    // relabelled in either direction, and an output whose executability
    // differs from the object's gets a private copy.
    if current & 0o111 != wanted & 0o111 {
        return false;
    }
    if current != wanted {
        if wanted & !current != 0 {
            return false;
        }
        if file
            .set_permissions(std::fs::Permissions::from_mode(wanted))
            .is_err()
        {
            return false;
        }
    }
    if std::fs::hard_link(source, destination).is_err() {
        return false;
    }
    // The link was made by name, so confirm it reached the object just
    // inspected rather than one that replaced it in flight. A link to the
    // wrong object is not wrong in its content -- a blob is its digest -- but
    // its mode was never checked against this output, so it is unlinked and
    // the caller copies instead.
    let linked = std::fs::metadata(destination);
    match linked {
        Ok(linked)
            if linked.ino() == metadata.ino() && linked.permissions().mode() & 0o7777 == wanted =>
        {
            true
        }
        _ => {
            let _ = std::fs::remove_file(destination);
            false
        }
    }
}

#[cfg(windows)]
fn hard_link_cached_output(_source: &Path, _destination: &Path, _node: &CacheFileNode) -> bool {
    // Windows hard links exist, but a read-only file there cannot be deleted
    // until the attribute is cleared, which is exactly the protection the
    // shared object relies on. Copying keeps the store unshared and the
    // target directory ordinary.
    false
}

/// The mode a store object must carry before anything links to it: the
/// readership the compiler gave this output, executable where the output was,
/// and writable by nobody.
///
/// Derived from the recorded mode rather than fixed at `0o444`, because an
/// output a compiler restricted to its owner -- what a `0o077` umask
/// produces -- must not become world-readable by being restored through a
/// link into a directory other local users can traverse.
#[cfg(unix)]
fn linkable_mode(node: &CacheFileNode) -> u32 {
    (node.mode & 0o444) | if node.executable { 0o111 } else { 0 }
}

/// Take the advisory lock that serializes relabelling one store object, or
/// report that another restore holds it.
///
/// Advisory rather than mandatory, which is enough: the only code that changes
/// a published object's mode is the caller of this, so every writer
/// participates. Readers of the bytes do not take it and are not delayed by
/// it.
#[cfg(unix)]
fn take_exclusive_lock(file: &std::fs::File) -> bool {
    use std::os::unix::io::AsRawFd as _;
    // SAFETY: `file` owns this descriptor for the whole call, and `flock`
    // only reads it. The lock is released when the descriptor closes.
    unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) == 0 }
}

/// Whether a mode leaves the object readable by the user who owns the store.
///
/// A recorded mode with no read bits is valid -- nothing rejects `0o200` --
/// and linking under one would set the store's own copy of those bytes to a
/// mode that cannot be opened, which outlives this restore and takes the
/// cache entry with it. Such an output gets a private copy.
#[cfg(unix)]
fn readable_by_owner(mode: u32) -> bool {
    mode & 0o400 != 0
}

/// Give a file the modification time a compiler writing it now would.
pub(crate) fn set_modified_now(path: &Path) -> Result<()> {
    set_modified(path, std::time::SystemTime::now())
}

/// Stamp a file with a modification time.
///
/// Opened without write access, because anything downstream of a restore may
/// be looking at a hard link to the store's object, which is read-only on
/// purpose. A Unix owner may set times through a read-only handle. Windows
/// refuses write access to a read-only file but grants the attribute-only
/// access that setting times needs.
pub(crate) fn set_modified(path: &Path, modified: std::time::SystemTime) -> Result<()> {
    let times = std::fs::FileTimes::new().set_modified(modified);
    #[cfg(unix)]
    let file = std::fs::OpenOptions::new().read(true).open(path)?;
    #[cfg(windows)]
    let file = {
        use std::os::windows::fs::OpenOptionsExt as _;
        std::fs::OpenOptions::new()
            .access_mode(windows_sys::Win32::Storage::FileSystem::FILE_WRITE_ATTRIBUTES)
            .open(path)?
    };
    file.set_times(times)?;
    Ok(())
}

/// Unlink outputs a previous restore left that a compiler could not write.
///
/// A hard-linked restore shares the store's object, so it is read-only, and
/// rustc refuses such a path outright: "output file ... is not writeable".
/// That refusal is the point -- it is what stops a rebuild from rewriting the
/// bytes every other checkout linked to -- but the compiler about to run here
/// is going to replace these files anyway. Removing the link first leaves it
/// the ordinary create it expects, and leaves every other link untouched.
///
/// Best effort by design: a path that cannot be removed is one the compiler
/// will report on in its own words, and a restore that never linked anything
/// leaves nothing here to find.
pub(crate) fn clear_linked_outputs<'a>(paths: impl IntoIterator<Item = &'a Path>) {
    for path in paths {
        let Ok(metadata) = std::fs::symlink_metadata(path) else {
            continue;
        };
        if !metadata.is_file() || owner_can_write(&metadata) {
            continue;
        }
        let _ = std::fs::remove_file(path);
    }
}

#[cfg(unix)]
fn owner_can_write(metadata: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    metadata.permissions().mode() & 0o200 != 0
}

#[cfg(windows)]
fn owner_can_write(metadata: &std::fs::Metadata) -> bool {
    !metadata.permissions().readonly()
}

/// Rename every staged output into place, rolling the whole set back if any one
/// of them fails.
pub(crate) fn persist_outputs(staged: StagedOutputs) -> Result<()> {
    let StagedOutputs {
        directory: _directory,
        files,
    } = staged;
    let destinations = files
        .iter()
        .map(|(_, destination)| destination.clone())
        .collect::<Vec<_>>();
    for (temporary, destination) in files {
        let persisted = temporary
            .persist(&destination)
            .map_err(|error| error.error)
            .wrap_err_with(|| format!("failed to atomically restore {}", destination.display()));
        if let Err(error) = persisted {
            for destination in &destinations {
                match std::fs::remove_file(destination) {
                    Ok(()) => {}
                    Err(remove_error) if remove_error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(remove_error) => session::report_shim_warning(&format!(
                        "failed to roll back {}: {remove_error}",
                        destination.display()
                    )),
                }
            }
            return Err(error);
        }
    }
    Ok(())
}

/// Replay a cached compilation's diagnostics so a hit looks like a compile.
pub(crate) fn replay_bytes(stdout_bytes: &[u8], stderr_bytes: &[u8]) -> Result<()> {
    let mut stdout = std::io::stdout().lock();
    stdout.write_all(stdout_bytes)?;
    stdout.flush()?;
    let mut stderr = std::io::stderr().lock();
    stderr.write_all(stderr_bytes)?;
    stderr.flush()?;
    Ok(())
}

/// A directory to assemble blobs in before publishing them.
pub(crate) fn staging_directory() -> Result<tempfile::TempDir> {
    let root = match std::env::var_os(STAGING_ENV).filter(|root| !root.is_empty()) {
        Some(root) => PathBuf::from(root),
        None => crate::config::Config::load()?
            .store_dir()
            .join("standalone-staging"),
    };
    std::fs::create_dir_all(&root)?;
    Ok(tempfile::tempdir_in(root)?)
}

/// Resolve a compiler to an absolute path, so its identity does not depend on
/// how `PATH` happened to be spelled.
pub(crate) fn resolve_executable(executable: &OsStr) -> Result<PathBuf> {
    let executable = PathBuf::from(executable);
    if executable.is_absolute() {
        return Ok(executable);
    }
    which::which(&executable).wrap_err_with(|| {
        format!(
            "failed to resolve compiler executable {}",
            executable.display()
        )
    })
}

/// Tell the session a cached result was used.
pub(crate) fn record_action_hit(action: &CacheDigest, restore: RestoreStats, crate_name: &str) {
    record_action_hit_with_diagnostic(action, restore, crate_name, None);
}

pub(crate) fn record_action_hit_with_diagnostic(
    action: &CacheDigest,
    restore: RestoreStats,
    crate_name: &str,
    diagnostic: Option<ActionDiagnostic>,
) {
    let mut requests = Vec::new();
    if let Some(diagnostic) = diagnostic
        && let Some(request) =
            session::action_diagnostic_request("hit", Some(crate_name), diagnostic)
    {
        requests.push(request);
    }
    requests.extend(session::unit_outcome_requests("hit", Some(crate_name)));
    requests.push(AgentRequest::RecordActionHit {
        action: action.clone(),
        restore,
        crate_name: Some(crate_name.to_string()),
    });
    let responses = session::request_agent(&requests);
    match responses.map(|mut responses| responses.pop()) {
        Ok(Some(AgentResponse::ActionHitRecorded)) => {}
        Ok(Some(AgentResponse::Error { message })) => {
            session::report_shim_warning(&format!("hit was not recorded: {message}"));
        }
        Ok(_) => session::report_shim_warning("hit was not recorded"),
        Err(error) => {
            session::report_shim_warning(&format!("hit was not recorded: {error:#}"));
        }
    }
}

/// Identify the action before the details, so the session's warning deduplication
/// cannot merge different compilations that disagree in the same way.
pub(crate) fn verification_warning(
    adapter: &str,
    unit: &str,
    action: &CacheDigest,
    divergence: &str,
) -> String {
    format!(
        "shadow verification diverged from cached output: {adapter} action {} ({}): {divergence}",
        action.hash,
        unit.escape_default()
    )
}

/// Describe the first differing byte without emitting terminal controls or an
/// unbounded compiler diagnostic. Offsets are zero-based; lines are one-based.
pub(crate) fn stream_divergence(name: &str, cached: &[u8], compiled: &[u8]) -> Option<String> {
    if cached == compiled {
        return None;
    }
    let offset = cached
        .iter()
        .zip(compiled)
        .position(|(a, b)| a != b)
        .unwrap_or(cached.len().min(compiled.len()));
    let line = cached[..offset].iter().filter(|&&b| b == b'\n').count() + 1;
    let excerpt = |bytes: &[u8]| {
        let start = offset.saturating_sub(24);
        let end = bytes.len().min(offset.saturating_add(48));
        format!(
            "{}{}{}",
            if start > 0 { "..." } else { "" },
            bytes[start..end].escape_ascii(),
            if end < bytes.len() { "..." } else { "" }
        )
    };
    Some(format!(
        "{name} differs at byte {offset} (line {line}): cached=\"{}\", compiled=\"{}\"",
        excerpt(cached),
        excerpt(compiled)
    ))
}

/// Tell the session whether a shadow compilation agreed with the cache.
pub(crate) fn record_verification(matched: bool, restore: RestoreStats) {
    let responses =
        session::request_agent(&[AgentRequest::RecordActionVerification { matched, restore }]);
    match responses.map(|responses| responses.into_iter().next()) {
        Ok(Some(AgentResponse::ActionVerificationRecorded)) => {}
        Ok(Some(AgentResponse::Error { message })) => {
            session::report_shim_warning(&format!("verification was not recorded: {message}"));
        }
        Ok(_) => session::report_shim_warning("verification was not recorded"),
        Err(error) => {
            session::report_shim_warning(&format!("verification was not recorded: {error:#}"));
        }
    }
}

#[cfg(unix)]
pub(crate) fn file_mode(metadata: &std::fs::Metadata) -> u32 {
    use std::os::unix::fs::PermissionsExt as _;
    metadata.permissions().mode() & 0o644
}

#[cfg(windows)]
pub(crate) fn file_mode(_metadata: &std::fs::Metadata) -> u32 {
    0
}

#[cfg(unix)]
pub(crate) fn validate_file_mode(node: &CacheFileNode, executable: bool) -> Result<()> {
    if node.executable != executable
        || node.mode & !0o777 != 0
        || node.mode & 0o111 != 0
        || node.mode & 0o022 != 0
    {
        bail!("cached output has an unsafe file mode: {}", node.name);
    }
    Ok(())
}

#[cfg(windows)]
pub(crate) fn validate_file_mode(node: &CacheFileNode, executable: bool) -> Result<()> {
    if node.executable != executable || node.mode != 0 {
        bail!("cached output has an unsafe file mode: {}", node.name);
    }
    Ok(())
}

#[cfg(unix)]
pub(crate) fn apply_file_mode(temporary: &Path, mode: u32, executable: bool) -> Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    let executable_mode = if executable { 0o111 } else { 0 };
    std::fs::set_permissions(
        temporary,
        std::fs::Permissions::from_mode(mode | executable_mode),
    )?;
    Ok(())
}

#[cfg(windows)]
pub(crate) fn apply_file_mode(_temporary: &Path, _mode: u32, _executable: bool) -> Result<()> {
    Ok(())
}

#[cfg(unix)]
pub(crate) fn executable_mode_matches(metadata: &std::fs::Metadata, executable: bool) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    (metadata.permissions().mode() & 0o111 != 0) == executable
}

#[cfg(windows)]
pub(crate) fn executable_mode_matches(_metadata: &std::fs::Metadata, _executable: bool) -> bool {
    true
}

#[cfg(unix)]
pub(crate) fn make_owner_writable(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_mode(permissions.mode() | 0o200);
    std::fs::set_permissions(path, permissions)?;
    Ok(())
}

#[cfg(windows)]
pub(crate) fn make_owner_writable(path: &Path) -> Result<()> {
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_readonly(false);
    std::fs::set_permissions(path, permissions)?;
    Ok(())
}

/// Rewrite this machine's paths in a cached text output into the placeholders
/// the action key already uses.
///
/// Two outputs of a compilation are text that names where the compilation ran:
/// the dep-info file, whose rules are keyed by absolute output paths, and the
/// compiler's stderr, which carries an artifact notification per emitted file
/// when cargo asks for one. Both are the same compilation wherever it runs, but
/// neither is byte-identical across target directories, so storing them
/// verbatim means a restore hands the next checkout paths belonging to the one
/// that published them.
///
/// Only these two are rewritten. Compiled artifacts are opaque bytes that do
/// not carry the target directory, and rewriting inside them would be a
/// corruption rather than a translation.
pub(crate) fn normalize_output_text(bytes: &[u8], mappings: &[PathMapping]) -> Vec<u8> {
    let mut normalized = bytes.to_vec();
    for (root, placeholder) in root_spellings(mappings) {
        normalized = replace_bytes(&normalized, root.as_bytes(), placeholder.as_bytes());
    }
    normalized
}

/// Rewrite placeholders in a cached text output back into this machine's paths.
pub(crate) fn denormalize_output_text(bytes: &[u8], mappings: &[PathMapping]) -> Vec<u8> {
    let mut text = bytes.to_vec();
    for (root, placeholder) in root_spellings(mappings) {
        text = replace_bytes(&text, placeholder.as_bytes(), root.as_bytes());
    }
    text
}

/// Every spelling a root can take in these outputs, paired with the
/// placeholder that stands for it.
///
/// rustc writes a path with the platform separator in some places and forward
/// slashes in others -- the reason [`carries`] searches both -- and stderr is
/// JSON, where a Windows separator arrives doubled. A spelling missed here is
/// a path from the publishing checkout left in place, so each is looked for,
/// and each gets its own placeholder because a restore has to know which one
/// to write back.
///
/// Deepest root first, so a target directory inside a workspace wins over the
/// workspace, and within a root the doubled spelling before the single one.
fn root_spellings(mappings: &[PathMapping]) -> Vec<(String, String)> {
    let mut spellings = Vec::new();
    for mapping in PathMapping::ordered(mappings) {
        let Some(root) = mapping.root.to_str() else {
            continue;
        };
        // A root arrives however its environment variable was written, and
        // `CARGO_TARGET_DIR=/work/target/` is as valid as the same path
        // without. Trailing separators are dropped so the boundary check sees
        // the separator before a child rather than the child's first letter,
        // which would otherwise reject every path under such a root and leave
        // it in the publishing checkout's spelling. A Windows drive root like
        // `C:\` trims to `C:`, which its own separator then follows.
        let root = root.trim_end_matches(['/', '\\']);
        if root.is_empty() {
            continue;
        }
        // The literal spelling first, so a platform whose separator needs no
        // escaping keeps the plain placeholder rather than an escaped one that
        // means the same thing.
        for (spelling, suffix) in [
            (root.to_string(), ""),
            (root.replace('\\', "\\\\"), ":escaped"),
            (root.replace('\\', "/"), ":slash"),
        ] {
            if spellings.iter().any(|(existing, _)| existing == &spelling) {
                continue;
            }
            spellings.push((spelling, format!("${{{}{suffix}}}", mapping.placeholder)));
        }
    }
    spellings
}

/// Whether a root matched at `end` stops there rather than running into a
/// longer name.
///
/// `/work/target` is not a prefix of `/work/target-backup` in any sense that
/// matters, but a plain substring search cannot tell them apart, and rewriting
/// the second would hand a restore a directory that never existed.
/// [`normalize_mapped_path`] gets this from comparing components; here the
/// following byte has to say it.
fn ends_at_boundary(haystack: &[u8], end: usize) -> bool {
    match haystack.get(end) {
        None => true,
        Some(byte) => !(byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.')),
    }
}

fn replace_bytes(haystack: &[u8], needle: &[u8], replacement: &[u8]) -> Vec<u8> {
    if needle.is_empty() || haystack.len() < needle.len() {
        return haystack.to_vec();
    }
    let mut out = Vec::with_capacity(haystack.len());
    let mut index = 0;
    while index <= haystack.len() - needle.len() {
        if &haystack[index..index + needle.len()] == needle
            && ends_at_boundary(haystack, index + needle.len())
        {
            out.extend_from_slice(replacement);
            index += needle.len();
        } else {
            out.push(haystack[index]);
            index += 1;
        }
    }
    out.extend_from_slice(&haystack[index..]);
    out
}

/// Reproduce a compiler's exit status as this process's own.
///
/// A shim that captured the compiler's output has to hand the status back
/// itself, and a compiler killed by a signal reports no exit code at all --
/// reporting 1 there would turn a crash into an ordinary failure.
#[cfg(unix)]
pub(crate) fn exit_code(status: ExitStatus) -> ExitCode {
    use std::os::unix::process::ExitStatusExt as _;
    ExitCode::from(
        status
            .code()
            .unwrap_or_else(|| 128 + status.signal().unwrap_or(1)) as u8,
    )
}

#[cfg(windows)]
pub(crate) fn exit_code(status: ExitStatus) -> ExitCode {
    // ExitProcess skips Rust destructors, including the invocation timer.
    crate::phase_timing::finish();
    // SAFETY: this process is only a compiler wrapper and must preserve the
    // compiler's full Windows status code, which stable ExitCode cannot hold.
    unsafe { windows_sys::Win32::System::Threading::ExitProcess(status.code().unwrap_or(1) as u32) }
}

#[cfg(test)]
mod verification_tests {
    use super::*;

    #[test]
    fn stream_comparison_handles_eof_and_reports_the_first_differing_line() {
        assert_eq!(stream_divergence("stderr", b"same", b"same"), None);
        let difference = stream_divergence("stderr", b"same\nold", b"same\nnew").unwrap();
        assert!(difference.contains("byte 5 (line 2)"), "{difference}");
        assert!(difference.contains(r"same\nold"), "{difference}");
        for (cached, compiled) in [
            (b"".as_slice(), b"extra".as_slice()),
            (b"extra".as_slice(), b"".as_slice()),
        ] {
            let difference = stream_divergence("stdout", cached, compiled).unwrap();
            assert!(difference.contains("byte 0 (line 1)"), "{difference}");
        }
    }

    #[test]
    fn excerpts_are_bounded_and_escape_binary_and_terminal_bytes() {
        let cached = vec![b'a'; 10_000];
        let mut compiled = cached.clone();
        compiled.extend_from_slice(b"\x1b\0\xff\n");
        let difference = stream_divergence("stderr", &cached, &compiled).unwrap();
        assert!(difference.contains("byte 10000"), "{difference}");
        assert!(difference.contains(r"\x1b\x00\xff\n"), "{difference}");
        assert!(!difference.contains(['\n', '\0', '\x1b']));
        assert!(difference.len() < 512, "{difference}");
    }

    #[test]
    fn verification_unit_names_escape_terminal_controls() {
        let warning = verification_warning(
            "cc",
            "cc:bad\x1b[2J\n\0.c",
            &CacheDigest::blake3(b"action"),
            "standard error differs",
        );
        assert!(!warning.chars().any(char::is_control), "{warning:?}");
        assert!(warning.contains(r"cc:bad\u{1b}[2J\n\u{0}.c"), "{warning}");
        assert!(warning.ends_with("standard error differs"));
    }

    #[test]
    fn different_actions_of_one_unit_keep_distinct_warning_identities() {
        let first = verification_warning(
            "rustc",
            "example",
            &CacheDigest::blake3(b"lib"),
            "standard error differs",
        );
        let second = verification_warning(
            "rustc",
            "example",
            &CacheDigest::blake3(b"test"),
            "standard error differs",
        );
        assert_ne!(
            first, second,
            "session deduplication must preserve both units"
        );
        assert!(first.contains("rustc action"));
        assert!(first.contains("(example)"));
    }
}

#[cfg(all(test, unix))]
mod materialization_tests {
    use super::*;
    use std::os::unix::fs::MetadataExt as _;
    use std::os::unix::fs::PermissionsExt as _;

    /// A filesystem that cannot clone, so the fallback chain is what runs.
    fn no_clone(_: &Path, _: &Path) -> std::io::Result<()> {
        Err(std::io::ErrorKind::Unsupported.into())
    }

    fn blob(directory: &Path, name: &str, contents: &[u8], mode: u32) -> PathBuf {
        let path = directory.join(name);
        std::fs::write(&path, contents).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(mode)).unwrap();
        path
    }

    fn node(contents: &[u8], executable: bool) -> CacheFileNode {
        // `mode` is what the adapter recorded for the output; callers that
        // care override it.
        CacheFileNode {
            digest: CacheDigest::blake3(contents),
            executable,
            mode: 0o644,
            name: "libdemo.rlib".into(),
        }
    }

    #[test]
    fn a_filesystem_without_clones_links_the_object_instead_of_copying_it() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"rlib", 0o644);
        let before = std::fs::metadata(&source).unwrap();

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"rlib", false),
            no_clone,
        )
        .unwrap();

        assert_eq!(materialization, Materialization::Hardlink);
        let after = std::fs::metadata(&staged).unwrap();
        assert_eq!(after.ino(), before.ino(), "the link shares the object");
        // Read-only on purpose: a writer here would be writing into the store.
        assert_eq!(after.permissions().mode() & 0o777, 0o444);
        assert_eq!(
            std::fs::metadata(&source).unwrap().permissions().mode() & 0o777,
            0o444,
            "the object itself is what was made unwritable"
        );
        // Restored outputs still have to look freshly produced, or Cargo keeps
        // the unit stale forever. A link has no timestamp but the object's.
        assert!(after.modified().unwrap() > before.modified().unwrap());
    }

    #[test]
    fn an_executable_output_keeps_its_executable_bit_through_a_link() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"binary", 0o755);

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"binary", true),
            no_clone,
        )
        .unwrap();

        assert_eq!(materialization, Materialization::Hardlink);
        assert_eq!(
            std::fs::metadata(&staged).unwrap().permissions().mode() & 0o777,
            0o555
        );
    }

    #[test]
    fn an_object_that_would_have_to_gain_permissions_is_copied() {
        let root = tempfile::tempdir().unwrap();
        // What a blob fetched from a remote looks like: the right bytes under
        // whatever mode the download happened to have. Linking would have to
        // add the executable bit to an object other checkouts may hold.
        let source = blob(root.path(), "blob", b"binary", 0o644);
        let before = std::fs::metadata(&source).unwrap();

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"binary", true),
            no_clone,
        )
        .unwrap();

        assert_eq!(materialization, Materialization::Copy);
        assert_ne!(std::fs::metadata(&staged).unwrap().ino(), before.ino());
        assert_eq!(
            std::fs::metadata(&source).unwrap().permissions().mode() & 0o777,
            0o644,
            "an object nothing may widen keeps the mode it had"
        );
    }

    #[test]
    fn a_non_executable_output_never_takes_the_executable_bit_off_a_shared_object() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"program", 0o555);
        // A binary in somebody else's target directory is already running off
        // this object.
        let theirs = root.path().join("their-binary");
        std::fs::hard_link(&source, &theirs).unwrap();

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"program", false),
            no_clone,
        )
        .unwrap();

        // Readership can be given up harmlessly; the right to run cannot.
        assert_eq!(materialization, Materialization::Copy);
        assert_eq!(
            std::fs::metadata(&staged).unwrap().permissions().mode() & 0o777,
            0o644
        );
        assert_eq!(
            std::fs::metadata(&theirs).unwrap().permissions().mode() & 0o111,
            0o111,
            "their binary still runs"
        );
    }

    /// Set in the child that plays the other restore, to the object it locks.
    const HOLD_RELABEL_LOCK_ENV: &str = "TUIST_CARGO_CACHE_TEST_HOLD_RELABEL_LOCK";

    #[test]
    fn an_object_another_restore_is_relabelling_is_copied_rather_than_waited_on() {
        use std::io::BufRead as _;
        if let Some(source) = std::env::var_os(HOLD_RELABEL_LOCK_ENV) {
            let held = std::fs::File::open(source).unwrap();
            assert!(take_exclusive_lock(&held));
            // On stderr, which the harness leaves alone: its stdout puts
            // `test <name> ... ` in front of whatever a serial run prints.
            eprintln!("locked");
            // Held until the parent kills this process, or goes away itself
            // and closes the pipe.
            let _ = std::io::stdin().read_line(&mut String::new());
            return;
        }

        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"contended", 0o644);
        // Stand in for the other restore: hold the lock this one would need to
        // read a mode it can trust.
        //
        // From another process, as the other restore would be. A descriptor
        // this process held would be copied into every child that another
        // test forks while it is open, and the lock stays with that copy until
        // the child execs, so dropping it here would not reliably free it.
        let mut held = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "an_object_another_restore_is_relabelling_is_copied_rather_than_waited_on",
                "--nocapture",
            ])
            .env(HOLD_RELABEL_LOCK_ENV, &source)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        let stderr = std::io::BufReader::new(held.stderr.take().unwrap());
        assert!(
            stderr
                .lines()
                .any(|line| line.is_ok_and(|line| line == "locked")),
            "the other restore never took the lock"
        );

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"contended", false),
            no_clone,
        )
        .unwrap();

        assert_eq!(materialization, Materialization::Copy);
        assert_eq!(
            std::fs::metadata(&source).unwrap().permissions().mode() & 0o777,
            0o644,
            "the object is left to whoever holds the lock"
        );
        assert_eq!(std::fs::read(&staged).unwrap(), b"contended");
        // Reaped, so its descriptors are closed and the lock is free.
        held.kill().unwrap();
        held.wait().unwrap();

        // With the lock free, the same restore links as usual.
        let (_, materialization) = stage_verified_cached_output_with(
            root.path(),
            1,
            &source,
            &node(b"contended", false),
            no_clone,
        )
        .unwrap();
        assert_eq!(materialization, Materialization::Hardlink);
    }

    #[test]
    fn an_output_whose_recorded_mode_cannot_be_read_is_copied() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"write-only", 0o644);
        let mut unreadable = node(b"write-only", false);
        // Nothing rejects a recorded mode with no read bits. Linking under one
        // would leave the store's own copy of these bytes unopenable.
        unreadable.mode = 0o200;

        let (_staged, materialization) =
            stage_verified_cached_output_with(root.path(), 0, &source, &unreadable, no_clone)
                .unwrap();

        assert_eq!(materialization, Materialization::Copy);
        assert_eq!(
            std::fs::metadata(&source).unwrap().permissions().mode() & 0o777,
            0o644,
            "the store's object stays readable for every later lookup"
        );
    }

    #[test]
    fn a_clone_is_preferred_over_a_link_and_stays_a_private_writable_copy() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"rlib", 0o644);

        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"rlib", false),
            |source, destination| std::fs::copy(source, destination).map(|_| ()),
        )
        .unwrap();

        assert_eq!(materialization, Materialization::Reflink);
        assert_eq!(
            std::fs::metadata(&staged).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }

    #[test]
    fn an_owner_private_output_keeps_its_readership_through_a_link() {
        let root = tempfile::tempdir().unwrap();
        // What a compiler running under a 0o077 umask leaves behind.
        let source = blob(root.path(), "blob", b"private", 0o600);
        let mut private = node(b"private", false);
        private.mode = 0o600;

        let (staged, materialization) =
            stage_verified_cached_output_with(root.path(), 0, &source, &private, no_clone).unwrap();

        assert_eq!(materialization, Materialization::Hardlink);
        assert_eq!(
            std::fs::metadata(&staged).unwrap().permissions().mode() & 0o777,
            0o400,
            "a link must not publish bytes the compiler kept to its owner"
        );
    }

    #[test]
    fn relabelling_a_shared_object_may_only_take_permissions_away() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"shared", 0o444);
        // Somebody else's target directory is already holding this object.
        let theirs = root.path().join("their-output");
        std::fs::hard_link(&source, &theirs).unwrap();
        let mut private = node(b"shared", false);
        private.mode = 0o600;

        let (staged, materialization) =
            stage_verified_cached_output_with(root.path(), 0, &source, &private, no_clone).unwrap();

        // Two restores of one digest can read the link count in the same
        // instant, so the rule has to hold whichever order they land in.
        // Tightening does: their link ends up less readable than it was,
        // never more, and its owner can still read it.
        assert_eq!(materialization, Materialization::Hardlink);
        assert_eq!(
            std::fs::metadata(&staged).unwrap().permissions().mode() & 0o777,
            0o400
        );
        assert_eq!(
            std::fs::metadata(&theirs).unwrap().permissions().mode() & 0o777,
            0o400
        );
    }

    #[test]
    fn an_output_already_in_place_can_be_marked_restored_while_read_only() {
        let root = tempfile::tempdir().unwrap();
        let source = blob(root.path(), "blob", b"rlib", 0o644);
        let (staged, materialization) = stage_verified_cached_output_with(
            root.path(),
            0,
            &source,
            &node(b"rlib", false),
            no_clone,
        )
        .unwrap();
        assert_eq!(materialization, Materialization::Hardlink);
        let before = std::fs::metadata(&staged).unwrap().modified().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(10));

        // The next hit finds these bytes already here and only has to make
        // them look freshly produced. A read-only link must not defeat that.
        set_modified_now(&staged).expect("a linked output can be marked restored");

        assert!(std::fs::metadata(&staged).unwrap().modified().unwrap() > before);
    }

    #[test]
    fn linked_outputs_are_unlinked_before_a_compiler_writes_where_they_were() {
        let root = tempfile::tempdir().unwrap();
        let linked = blob(root.path(), "restored.rlib", b"restored", 0o444);
        let written = blob(root.path(), "compiled.rlib", b"compiled", 0o644);
        let missing = root.path().join("never-restored.rlib");

        clear_linked_outputs([linked.as_path(), written.as_path(), missing.as_path()]);

        assert!(!linked.exists(), "a read-only restore is removed");
        assert!(written.exists(), "an ordinary output is left alone");
    }
}
