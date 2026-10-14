//! A stable `OUT_DIR` for compilations that read build-script output.
//!
//! Cargo hands rustc an `OUT_DIR` under the checkout's target directory, and a
//! crate that includes generated sources reads the value through `env!`. That
//! puts the checkout's path into the artifact whenever the crate keeps the
//! value, and into the action key either way, so the crate compiles again in
//! every new checkout even though its generated sources are byte for byte the
//! same.
//!
//! Nothing available to the shim can prove an artifact ignores the path, so
//! the key must not pretend it does. What the shim can do is give every
//! checkout the *same* path: the generated tree is copied under the cache into
//! a directory named for a digest of its contents, and rustc is run with that
//! directory as `OUT_DIR`. Two checkouts whose build scripts produced the same
//! bytes then hand rustc the same string, and whatever the crate derives from
//! it -- a constant, a length, a hash -- agrees by construction. A tree that
//! differs, because the script wrote the checkout's path into it, gets a
//! different digest and a different key, which is the miss it deserves.
//!
//! The copy is only made for a crate whose own sources mention `OUT_DIR`. The
//! test is deliberately cheap and one-sided: a crate that mentions it without
//! reading it costs one copy and nothing else, since the key never sees an
//! environment value the compilation did not read; a crate that reads it
//! through a source the scan cannot see keeps today's checkout-specific key,
//! which is sound.

use eyre::{Context, Result};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};
use tuist_cargo_cache_core::CacheDigest;

/// Where the session tells the shim to keep stable trees.
pub(crate) const ROOT_ENV: &str = "TUIST_CARGO_CACHE_OUT_DIR_ROOT";

/// The cache-relative home of stable trees.
pub(crate) const ROOT: &str = "out-dirs/v1";

/// The placeholder a stable tree normalizes to in keys and predictions. Named
/// for the variable rather than the digest, so a prediction recorded in one
/// checkout resolves against another checkout's tree, whose digest is what the
/// key then compares.
pub(crate) const PLACEHOLDER: &str = "out_dir";

/// How often a use is stamped. The marker is what collection ages, and a
/// crate compiled in an edit loop would otherwise rewrite it every build.
const USE_STAMP_INTERVAL: Duration = Duration::from_secs(60 * 60);

/// Files scanned for a mention before the scan gives up and leaves the key
/// checkout-specific.
const SCAN_FILE_LIMIT: usize = 10_000;

/// Marks a tree still being copied into place.
const STAGING_PREFIX: &str = ".tmp-";

/// How long a staging directory may exist before a sweep assumes the process
/// copying into it died.
const STAGING_MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);

/// Serializes taking a lease on a tree with collecting it, so a collector that
/// found no lease held cannot lose to a compilation that takes one a moment
/// later. Held only for the moment of the check, never across the compile.
const REGISTRAR: &str = ".registrar.lock";

struct Lease {
    path: PathBuf,
    lock: fslock::LockFile,
}

/// Leases held by this process, keyed by tree's lease directory. The shim is
/// one compilation, and rustc reads the tree until it exits. Keyed so
/// a second request for the same tree finds the lease already held rather
/// than blocking on its own lock, which is what a second file lock on a path
/// this process already holds would do.
static LEASES: Mutex<std::collections::BTreeMap<PathBuf, Lease>> =
    Mutex::new(std::collections::BTreeMap::new());

/// The `OUT_DIR` Cargo gave this process, once it has been replaced, so a
/// compilation that ends up bypassing the cache can be handed back the tree
/// the shim is not going to keep a lease on.
static ORIGINAL: Mutex<Option<std::ffi::OsString>> = Mutex::new(None);

/// Give this compilation a stable `OUT_DIR`, when it has one to read.
///
/// On success the process environment carries the stable path, which is what
/// every later step reads: the key, the remapping, the compiler itself. A
/// problem copying the tree is reported and leaves the checkout's own value in
/// place, which is the behavior without this at all.
pub(crate) fn stabilize_for(source: &Path) -> Option<PathBuf> {
    if !crate::session::share_out_dir_requested() {
        return None;
    }
    let real = PathBuf::from(std::env::var_os("OUT_DIR")?);
    if !real.is_absolute() || !real.is_dir() {
        return None;
    }
    let root = PathBuf::from(std::env::var_os(ROOT_ENV)?);
    if !root.is_absolute() || real.starts_with(&root) {
        return None;
    }
    let sources = source.parent()?;
    if !sources_mention_out_dir(sources) {
        return None;
    }
    match stabilize(&real, &root) {
        Ok(Some(stable)) => {
            // Single-threaded here, ahead of any thread the shim starts, and
            // rustc inherits what is set by the time it is spawned.
            *ORIGINAL.lock().unwrap() = Some(real.into_os_string());
            unsafe { std::env::set_var("OUT_DIR", &stable) };
            Some(stable)
        }
        Ok(None) => None,
        Err(error) => {
            crate::session::report_shim_warning(&format!(
                "OUT_DIR was not made stable for this compilation: {error:#}"
            ));
            None
        }
    }
}

/// Hand a compilation that bypasses the cache the `OUT_DIR` Cargo gave it.
///
/// A bypassed compilation may replace this process with rustc, and a lease
/// lives only as long as the process holding it, so the compiler must not be
/// left reading a tree nothing protects. Cargo's own tree is the checkout's
/// and needs no lease. The leases go with the value: nothing this process
/// will run reads the stable tree any more.
pub(crate) fn restore() {
    let Some(original) = ORIGINAL.lock().unwrap().take() else {
        return;
    };
    unsafe { std::env::set_var("OUT_DIR", original) };
    LEASES.lock().unwrap().clear();
}

/// Whether any Rust source below `directory` mentions `OUT_DIR`.
///
/// Hidden directories, `target`, and `node_modules` are skipped: none of them
/// hold a crate's own sources, and a workspace root package would otherwise
/// walk the whole checkout.
pub(crate) fn sources_mention_out_dir(directory: &Path) -> bool {
    let mut pending = vec![directory.to_path_buf()];
    let mut scanned = 0;
    while let Some(directory) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            let Ok(kind) = entry.file_type() else {
                continue;
            };
            if kind.is_dir() {
                if !name.starts_with('.') && name != "target" && name != "node_modules" {
                    pending.push(entry.path());
                }
            } else if kind.is_file() && name.ends_with(".rs") {
                scanned += 1;
                if scanned > SCAN_FILE_LIMIT {
                    return false;
                }
                if std::fs::read(entry.path())
                    .is_ok_and(|contents| memchr::memmem::find(&contents, b"OUT_DIR").is_some())
                {
                    return true;
                }
            }
        }
    }
    false
}

/// Copy `real` under `root` into a directory named for its contents, and
/// return that directory. `None` when the tree has something a copy could not
/// reproduce faithfully, such as a symlink.
pub(crate) fn stabilize(real: &Path, root: &Path) -> Result<Option<PathBuf>> {
    let mut manifest = Vec::new();
    let mut files = Vec::new();
    let mut directories = Vec::new();
    if !describe_tree(
        real,
        Path::new(""),
        &mut manifest,
        &mut files,
        &mut directories,
    )? {
        return Ok(None);
    }
    let digest = CacheDigest::blake3(&manifest).hash;
    let stable = root.join(&digest);
    // The lease comes first, so a collector that finds the tree unused has
    // already removed it or cannot: whichever way, what is looked at next is
    // a tree this process is guaranteed to keep until it exits.
    lease(root, &digest)?;
    // One publisher per tree at a time, and nobody reuses a tree until its
    // publication is complete: the existence check and the copy sit under
    // the same lock, so a second process either finds the finished,
    // protected tree or waits for it.
    let published = (|| -> Result<()> {
        let mut publishing = fslock::LockFile::open(&publish_lock_path(root, &digest))?;
        publishing.lock()?;
        if !stable.is_dir() {
            materialize(real, root, &stable, &manifest, &files, &directories)?;
        }
        Ok(())
    })();
    if let Err(error) = published {
        // Nothing was published, so nothing needs the lease; a lease left
        // behind here would name a tree that never existed.
        release(root, &digest);
        return Err(error);
    }
    stamp_use(root, &digest);
    Ok(Some(stable))
}

fn publish_lock_path(root: &Path, digest: &str) -> PathBuf {
    root.join(format!("{digest}.publish.lock"))
}

/// Give up this process's lease on a tree and take its file with it.
fn release(root: &Path, digest: &str) {
    let leases = leases_dir(root, digest);
    if let Some(lease) = LEASES.lock().unwrap().remove(&leases) {
        drop(lease.lock);
        let _ = std::fs::remove_file(&lease.path);
        let _ = std::fs::remove_dir(&leases);
    }
}

fn leases_dir(root: &Path, digest: &str) -> PathBuf {
    root.join(format!("{digest}.leases"))
}

fn registrar(root: &Path) -> Result<fslock::LockFile> {
    std::fs::create_dir_all(root)?;
    let mut lock = fslock::LockFile::open(&root.join(REGISTRAR))?;
    lock.lock()?;
    Ok(lock)
}

/// Keep a tree from being collected while this process compiles against it.
///
/// One lock file per process, held until it exits, so a collector can tell a
/// live compilation from the debris of one that died: a lease it can take is
/// nobody's.
fn lease(root: &Path, digest: &str) -> Result<()> {
    let leases = leases_dir(root, digest);
    let mut held = LEASES.lock().unwrap();
    if held.contains_key(&leases) {
        return Ok(());
    }
    let _registrar = registrar(root)?;
    std::fs::create_dir_all(&leases)?;
    // A PID alone repeats across namespaces; an existing lease must never
    // make a compiler wait while holding the registrar.
    let path = leases.join(format!(
        "{}-{}.lease",
        std::process::id(),
        crate::util::random_string(12)
    ));
    std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)?;
    let mut lock = fslock::LockFile::open(&path)?;
    if !lock.try_lock()? {
        eyre::bail!("the OUT_DIR lease {} is already held", path.display());
    }
    held.insert(leases, Lease { path, lock });
    Ok(())
}

/// Whether a compilation holds a lease on the tree. Called under the
/// registrar, so the answer holds until it is released. Lease files nobody
/// holds are removed along the way when `prune` is set.
fn leased(root: &Path, digest: &str, prune: bool) -> std::io::Result<bool> {
    let leases = leases_dir(root, digest);
    let entries = match std::fs::read_dir(&leases) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };
    for entry in entries {
        let entry = entry?;
        let mut lock = fslock::LockFile::open(&entry.path())?;
        if !lock.try_lock()? {
            return Ok(true);
        }
        drop(lock);
        if prune {
            let _ = std::fs::remove_file(entry.path());
        }
    }
    Ok(false)
}

/// Describe a tree in an order and form that two copies of the same bytes
/// share: relative paths with `/` separators, the executable bit, and each
/// file's content digest. Returns `false` for a tree that cannot be copied.
fn describe_tree(
    root: &Path,
    relative: &Path,
    manifest: &mut Vec<u8>,
    files: &mut Vec<(PathBuf, bool)>,
    directories: &mut Vec<PathBuf>,
) -> Result<bool> {
    let directory = root.join(relative);
    let mut entries = std::fs::read_dir(&directory)
        .wrap_err_with(|| format!("failed to read {}", directory.display()))?
        .collect::<std::io::Result<Vec<_>>>()?;
    entries.sort_by_key(std::fs::DirEntry::file_name);
    for entry in entries {
        let name = entry.file_name();
        let Some(name) = name.to_str() else {
            return Ok(false);
        };
        // A backslash is a legal byte in a Unix file name and the separator
        // on Windows; a name carrying one would spell the same as a nested
        // path. Such a tree keeps Cargo's `OUT_DIR`, as does one with a
        // newline, the record separator, in a name.
        if name.contains('\\') || name.contains('\n') {
            return Ok(false);
        }
        let path = relative.join(name);
        let spelled = path.to_string_lossy().replace('\\', "/");
        let metadata = std::fs::symlink_metadata(entry.path())?;
        if metadata.file_type().is_symlink() {
            return Ok(false);
        } else if metadata.is_dir() {
            manifest.extend_from_slice(b"d ");
            manifest.extend_from_slice(format!("{}:", spelled.len()).as_bytes());
            manifest.extend_from_slice(spelled.as_bytes());
            manifest.push(b'\n');
            directories.push(path.clone());
            if !describe_tree(root, &path, manifest, files, directories)? {
                return Ok(false);
            }
        } else if metadata.is_file() {
            let executable = is_executable(&metadata);
            let digest = CacheDigest::blake3_file(&entry.path())?;
            manifest.extend_from_slice(if executable { b"x " } else { b"f " });
            manifest.extend_from_slice(digest.hash.as_bytes());
            manifest.push(b' ');
            // Length-prefixed, so no spelling of one name can read as another
            // name plus a separator.
            manifest.extend_from_slice(format!("{}:", spelled.len()).as_bytes());
            manifest.extend_from_slice(spelled.as_bytes());
            manifest.push(b'\n');
            files.push((path, executable));
        } else {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Copy the tree into place through a staging directory renamed at the end,
/// so a reader never sees a partial tree under the final name. Two shims
/// copying the same tree at once both finish; whichever renames second finds
/// the name taken and discards its own copy.
fn materialize(
    real: &Path,
    root: &Path,
    stable: &Path,
    manifest: &[u8],
    files: &[(PathBuf, bool)],
    directories: &[PathBuf],
) -> Result<()> {
    std::fs::create_dir_all(root)?;
    let name = stable
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let staging = root.join(format!("{STAGING_PREFIX}{name}-{}", std::process::id()));
    let _ = remove_tree(&staging);
    std::fs::create_dir(&staging)?;
    let copied = (|| -> Result<()> {
        for directory in directories {
            std::fs::create_dir_all(staging.join(directory))?;
        }
        for (file, executable) in files {
            let source = real.join(file);
            let destination = staging.join(file);
            reflink_copy::reflink_or_copy(&source, &destination)
                .wrap_err_with(|| format!("failed to copy {}", source.display()))?;
            // Cargo compares every file in a unit's dep-info with the time it
            // started the unit, and this copy is made after that, while rustc
            // runs. Keeping the build script's time keeps the next build from
            // taking the copy for a changed input and compiling the unit again.
            // Through a read-only handle, since a build script may have made
            // the file read-only and the copy keeps its mode.
            let modified = std::fs::metadata(&source)?.modified()?;
            crate::materialize::set_modified(&destination, modified)?;
            // Read-only: the tree is shared by every checkout whose generated
            // sources match, and a write through one compilation would leave
            // it disagreeing with its own name. A compilation that writes into
            // `OUT_DIR` fails loudly here rather than corrupting the others.
            make_read_only(&destination, *executable)?;
        }
        // The directories too, or a file could be unlinked and replaced
        // through its writable parent. Deepest last, so the walk above them
        // could still create them.
        for directory in directories.iter().rev() {
            make_directory_read_only(&staging.join(directory))?;
        }
        Ok(())
    })();
    if let Err(error) = copied {
        let _ = remove_tree(&staging);
        return Err(error);
    }
    // The copy is what carries the name, so it is the copy that is checked
    // against it. Cargo runs the build script to completion before rustc, so
    // the source tree does not move under the shim in practice; if something
    // does move it, the digest would name bytes nobody copied, and the copy
    // is discarded rather than published under that name.
    let mut copied_manifest = Vec::new();
    let described = describe_tree(
        &staging,
        Path::new(""),
        &mut copied_manifest,
        &mut Vec::new(),
        &mut Vec::new(),
    );
    if !matches!(described, Ok(true)) || copied_manifest != manifest {
        let _ = remove_tree(&staging);
        eyre::bail!("the build-script output changed while it was being copied");
    }
    match std::fs::rename(&staging, stable) {
        // The top directory last, and after the move: macOS will not rename
        // a directory it cannot write, since the move rewrites its parent
        // entry.
        // A tree that could not be protected is not left standing: the next
        // process would take it for a finished one.
        Ok(()) => match make_directory_read_only(stable) {
            Ok(()) => Ok(()),
            Err(error) => {
                let _ = remove_tree(stable);
                Err(error).wrap_err_with(|| format!("failed to protect {}", stable.display()))
            }
        },
        Err(_) if stable.is_dir() => {
            let _ = remove_tree(&staging);
            Ok(())
        }
        Err(error) => {
            let _ = remove_tree(&staging);
            Err(error).wrap_err_with(|| format!("failed to place {}", stable.display()))
        }
    }
}

#[cfg(unix)]
fn is_executable(metadata: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    metadata.permissions().mode() & 0o111 != 0
}

#[cfg(not(unix))]
fn is_executable(_: &std::fs::Metadata) -> bool {
    false
}

#[cfg(unix)]
fn make_read_only(path: &Path, executable: bool) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    let mode = if executable { 0o555 } else { 0o444 };
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn make_read_only(path: &Path, _executable: bool) -> std::io::Result<()> {
    let mut permissions = std::fs::metadata(path)?.permissions();
    permissions.set_readonly(true);
    std::fs::set_permissions(path, permissions)
}

#[cfg(unix)]
fn make_directory_read_only(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o555))
}

/// Windows has no directory permission that stops entries being replaced,
/// only the file attribute, which the files already carry.
#[cfg(not(unix))]
fn make_directory_read_only(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

fn marker_path(root: &Path, digest: &str) -> PathBuf {
    root.join(format!("{digest}.used"))
}

/// Note that a tree was used, at most once an hour.
fn stamp_use(root: &Path, digest: &str) {
    let marker = marker_path(root, digest);
    let fresh = std::fs::metadata(&marker)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|since| since < USE_STAMP_INTERVAL);
    if !fresh {
        // The time is set rather than left to the write: Windows does not
        // move a file's time for a write of nothing.
        let _ =
            std::fs::File::create(&marker).and_then(|file| file.set_modified(SystemTime::now()));
    }
}

/// What a collection of stable trees removed and left.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct PruneOutcome {
    pub removed_directories: u64,
    pub removed_bytes: u64,
    pub remaining_directories: u64,
    pub remaining_bytes: u64,
}

/// Remove trees nothing has used for `max_age`, the least recently used of
/// the rest until they fit `max_bytes`, and staging directories left by a
/// copy that never finished.
///
/// A removed tree costs at most a rebuild: the next compilation that needs it
/// finds the path in its dep-info missing, Cargo runs rustc again, and the
/// shim copies the tree back before looking the compilation up. Nothing is
/// keyed to the tree's presence, only to its contents.
pub(crate) fn collect(
    root: &Path,
    max_bytes: Option<u64>,
    max_age: Option<Duration>,
    dry_run: bool,
) -> Result<PruneOutcome> {
    let mut outcome = PruneOutcome::default();
    let entries = match std::fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(outcome),
        Err(error) => {
            return Err(error).wrap_err_with(|| format!("failed to read {}", root.display()));
        }
    };
    let now = SystemTime::now();
    // Trees by age, oldest first, so what the budget evicts is what was used
    // least recently.
    let mut trees: Vec<(String, PathBuf, u64, Option<Duration>)> = Vec::new();
    let mut lease_dirs = Vec::new();
    for entry in entries {
        // An entry that cannot be read is still on the disk. It is kept and
        // counted, not skipped, so a budget sized from this walk sees it.
        let Ok(entry) = entry else {
            outcome.remaining_directories += 1;
            continue;
        };
        let name = entry.file_name().to_string_lossy().into_owned();
        let path = entry.path();
        let is_dir = match entry.file_type() {
            Ok(kind) => kind.is_dir(),
            Err(_) => {
                outcome.remaining_directories += 1;
                outcome.remaining_bytes = outcome.remaining_bytes.saturating_add(tree_bytes(&path));
                continue;
            }
        };
        if !is_dir {
            continue;
        }
        if name.starts_with(STAGING_PREFIX) {
            let abandoned = age_of(&path, now).is_some_and(|age| age > STAGING_MAX_AGE);
            if abandoned && !dry_run {
                let _ = remove_tree(&path);
            }
            continue;
        }
        if let Some(digest) = name.strip_suffix(".leases") {
            if is_digest_name(digest) {
                lease_dirs.push(digest.to_owned());
            }
            continue;
        }
        if !is_digest_name(&name) {
            continue;
        }
        let age = age_of(&marker_path(root, &name), now).or_else(|| age_of(&path, now));
        trees.push((name, path, 0, age));
    }
    trees.sort_by_key(|tree| std::cmp::Reverse(tree.3));
    let mut remaining_bytes = 0_u64;
    for tree in &mut trees {
        tree.2 = tree_bytes(&tree.1);
        remaining_bytes = remaining_bytes.saturating_add(tree.2);
    }
    let mut kept = trees.len() as u64;
    for (name, path, bytes, age) in &trees {
        let expired = max_age.is_some_and(|max_age| age.is_some_and(|age| age > max_age));
        let over_budget = max_bytes.is_some_and(|max_bytes| remaining_bytes > max_bytes);
        if !expired && !over_budget {
            continue;
        }
        // Under the registrar from the lease check to the removal, so a
        // compilation cannot take a lease on a tree halfway gone: it waits,
        // finds the tree missing, and copies it again. A tree whose leases
        // cannot be read is treated as leased. A dry run asks the same
        // question, so what it projects is what a sweep would do.
        let _registrar = registrar(root)?;
        if leased(root, name, !dry_run).unwrap_or(true) {
            continue;
        }
        if !dry_run {
            let _ = std::fs::remove_file(marker_path(root, name));
            if let Err(error) = remove_tree(path) {
                log::warn!(
                    "could not remove the generated source tree {}: {error}",
                    path.display()
                );
                continue;
            }
            let _ = std::fs::remove_dir_all(leases_dir(root, name));
            let _ = std::fs::remove_file(publish_lock_path(root, name));
        }
        kept -= 1;
        remaining_bytes = remaining_bytes.saturating_sub(*bytes);
        outcome.removed_directories += 1;
        outcome.removed_bytes = outcome.removed_bytes.saturating_add(*bytes);
    }
    outcome.remaining_directories += kept;
    outcome.remaining_bytes = outcome.remaining_bytes.saturating_add(remaining_bytes);
    // Leases of a tree that was never published, or is gone: a copy that
    // failed after its lease was taken, or a process that died between the
    // two. Nobody holds them, so nobody is waiting on the tree.
    if !dry_run {
        for digest in lease_dirs {
            if root.join(&digest).is_dir() {
                continue;
            }
            let _registrar = registrar(root)?;
            if !leased(root, &digest, true).unwrap_or(true) {
                let _ = std::fs::remove_dir_all(leases_dir(root, &digest));
                let _ = std::fs::remove_file(publish_lock_path(root, &digest));
            }
        }
    }
    Ok(outcome)
}

/// Bytes and count of stable trees, for reports and budgets.
///
/// `None` when the root cannot be listed: no walk can measure what it cannot
/// read, and a caller sizing a budget must know it is missing a number rather
/// than be handed a zero.
pub(crate) fn stats(root: &Path) -> Option<PruneOutcome> {
    collect(root, None, None, true).ok()
}

fn is_digest_name(name: &str) -> bool {
    name.len() == 64 && name.bytes().all(|byte| byte.is_ascii_hexdigit())
}

fn age_of(path: &Path, now: SystemTime) -> Option<Duration> {
    let modified = std::fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()?;
    now.duration_since(modified).ok()
}

/// Remove a tree that was made read-only. Unlinking needs a writable parent
/// on Unix, so the directories are opened up first; Windows refuses to delete
/// a read-only file, so the attribute comes off the files first there.
fn remove_tree(path: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        if !path.is_dir() {
            return std::fs::remove_dir_all(path);
        }
        let mut pending = vec![path.to_path_buf()];
        while let Some(directory) = pending.pop() {
            std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o755))?;
            for entry in std::fs::read_dir(&directory)?.flatten() {
                if entry.file_type()?.is_dir() {
                    pending.push(entry.path());
                }
            }
        }
    }
    #[cfg(not(unix))]
    {
        let mut pending = vec![path.to_path_buf()];
        while let Some(directory) = pending.pop() {
            for entry in std::fs::read_dir(&directory)?.flatten() {
                let kind = entry.file_type()?;
                if kind.is_dir() {
                    pending.push(entry.path());
                } else {
                    let mut permissions = entry.metadata()?.permissions();
                    permissions.set_readonly(false);
                    std::fs::set_permissions(entry.path(), permissions)?;
                }
            }
        }
    }
    std::fs::remove_dir_all(path)
}

fn tree_bytes(directory: &Path) -> u64 {
    let mut total = 0;
    let mut pending = vec![directory.to_path_buf()];
    while let Some(directory) = pending.pop() {
        let Ok(entries) = std::fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let Ok(metadata) = entry.metadata() else {
                continue;
            };
            if metadata.is_dir() {
                pending.push(entry.path());
            } else {
                total += metadata.len();
            }
        }
    }
    total
}

/// Let go of every lease this process holds under `root`, as the exit of the
/// compilations that took them would. Only tests need this: a shim is one
/// compilation, and its leases end with it.
#[cfg(test)]
fn release_all_under(root: &Path) {
    LEASES
        .lock()
        .unwrap()
        .retain(|path, _| !path.starts_with(root));
}

#[cfg(test)]
#[path = "out_dir_tests.rs"]
mod tests;
