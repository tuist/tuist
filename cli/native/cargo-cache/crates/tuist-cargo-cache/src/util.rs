use eyre::{Context, Result};
use std::collections::BTreeMap;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tuist_cargo_cache_core::FileSnapshot;

/// Capture clock-independent snapshots for compiler inputs known up front.
///
/// A source file is snapshotted by its metadata change token, which catches a
/// rewrite that keeps the length and restores the mtime. An artifact another
/// compilation in this build produced is snapshotted by content instead: a
/// dependent Cargo pipelines behind a crate's metadata reads the `.rmeta`
/// while that crate's rustc is still running, and rustc hardlinks the file
/// into its incremental session directory when it finishes, which changes the
/// token without changing a byte. Nothing rewrites an artifact in place while
/// Cargo holds the build directory, so bytes, length, and file object are the
/// comparison that describes what the dependent actually read. The `source`
/// is always a source, whatever its extension is spelled like.
#[cfg(unix)]
pub(crate) fn snapshot_compiler_inputs<'a>(
    paths: impl IntoIterator<Item = &'a Path>,
    source: Option<&Path>,
) -> std::io::Result<BTreeMap<PathBuf, FileSnapshot>> {
    let digests = crate::session::file_digest_cache();
    paths
        .into_iter()
        .map(|path| {
            let snapshot = if source != Some(path) && is_compiler_artifact(path) {
                FileSnapshot::capture_content_with_cache(path, digests)
            } else {
                FileSnapshot::capture_with_cache(path, digests)
            };
            let snapshot = snapshot.map_err(|error| {
                std::io::Error::new(
                    error.kind(),
                    format!(
                        "failed to capture compiler input snapshot for {}: {error}",
                        path.display()
                    ),
                )
            })?;
            let snapshot = snapshot.ok_or_else(|| {
                std::io::Error::new(
                    std::io::ErrorKind::Unsupported,
                    format!(
                        "filesystem supplied no snapshot for compiler input {}",
                        path.display()
                    ),
                )
            })?;
            Ok((path.to_path_buf(), snapshot))
        })
        .collect()
}

/// Whether a compiler input is an artifact this build produced rather than a
/// source: Rust metadata, an rlib, or a proc-macro or dynamic library.
#[cfg(unix)]
fn is_compiler_artifact(path: &Path) -> bool {
    matches!(
        path.extension().and_then(|extension| extension.to_str()),
        Some("rmeta" | "rlib" | "so" | "dylib" | "dll")
    )
}

#[cfg(not(unix))]
pub(crate) fn snapshot_compiler_inputs<'a>(
    _paths: impl IntoIterator<Item = &'a Path>,
    _source: Option<&Path>,
) -> std::io::Result<BTreeMap<PathBuf, FileSnapshot>> {
    Ok(BTreeMap::new())
}

/// Find the workspace root above `start`.
///
/// The outermost directory holding a `Cargo.lock` is preferred, since that is
/// the one Cargo resolves against; a directory holding only a `Cargo.toml`
/// stands in when there is no lockfile yet.
pub fn workspace_root(start: &Path) -> std::path::PathBuf {
    let mut lockfile = None;
    let mut manifest = None;
    for directory in start.ancestors() {
        if directory.join("Cargo.lock").is_file() {
            lockfile = Some(directory.to_path_buf());
        }
        if directory.join("Cargo.toml").is_file() {
            manifest = Some(directory.to_path_buf());
        }
        // Delta checkouts are independent source trees nested below the
        // original repository's `.delta/worktrees` directory. Do not let a
        // lockfile in that enclosing repository replace the checkout's own
        // workspace root. Ordinary VCS markers are not boundaries here: a
        // Cargo workspace may legitimately contain a nested repository.
        if is_delta_worktree_root(directory) {
            break;
        }
    }
    lockfile.or(manifest).unwrap_or_else(|| start.to_path_buf())
}

/// Whether `directory` is the root of a supported VCS or managed checkout.
///
/// Marker existence, rather than file type, covers linked/shared checkouts
/// whose metadata marker may be a file or symbolic link. Delta worktrees have
/// no marker of their own, so their managed location establishes the boundary.
pub fn is_checkout_root(directory: &Path) -> bool {
    [".git", ".jj", ".hg", ".sl"]
        .iter()
        .any(|marker| directory.join(marker).exists())
        || is_delta_worktree_root(directory)
}

fn is_delta_worktree_root(directory: &Path) -> bool {
    directory
        .parent()
        .is_some_and(|parent| parent.file_name() == Some(std::ffi::OsStr::new("worktrees")))
        && directory
            .parent()
            .and_then(Path::parent)
            .is_some_and(|parent| parent.file_name() == Some(std::ffi::OsStr::new(".delta")))
}

/// Write `contents` to `path` so readers never observe a partial file.
pub fn write_atomic(path: &Path, contents: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| eyre::eyre!("path has no parent: {}", path.display()))?;
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-")
        .tempfile_in(parent)?;
    temporary.write_all(contents)?;
    temporary.as_file_mut().sync_all()?;
    temporary
        .persist(path)
        .map_err(|error| error.error)
        .wrap_err_with(|| format!("failed atomic write: {}", path.display()))?;
    Ok(())
}

/// Replace `path` atomically without waiting for the bytes to reach disk.
///
/// For records a build rewrites every time it runs and reads back only as a
/// shortcut: a checkout's last-used stamp, a crate's churn record, the
/// file-digest ledger. Losing the newest one to a power cut costs the next
/// build a rehash or a record one build older, and every reader here treats
/// a torn file as no file. `sync_all` is what makes [`write_atomic`] cost a
/// disk round trip per call, and a build pays for several of these.
pub fn write_advisory(path: &Path, contents: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .ok_or_else(|| eyre::eyre!("path has no parent: {}", path.display()))?;
    std::fs::create_dir_all(parent)
        .wrap_err_with(|| format!("failed to create {}", parent.display()))?;
    let mut temporary = tempfile::Builder::new()
        .prefix(".tuist_cargo_cache-")
        .tempfile_in(parent)?;
    temporary.write_all(contents)?;
    temporary
        .persist(path)
        .map_err(|error| error.error)
        .wrap_err_with(|| format!("failed atomic write: {}", path.display()))?;
    Ok(())
}

/// Format a duration for humans, widening units as the duration grows.
///
/// A measurement below a minute keeps the precision that makes it worth
/// reading; past that, [`format_clock`] takes over, because a build that took
/// "813.00s" is a number to convert rather than a time to read. Nothing is
/// reported as `0ns`: a duration that never happened is "0s".
///
/// The handover to the clock is placed where the seconds rendering stops
/// fitting, not at the minute itself: `{:.2?}` rounds, so 59.996s would read
/// "60.00s" -- a minute spelled in the unit this function exists to grow out
/// of, sitting in the same output as "1m 5s". The clock takes that value and
/// reads it as "1m".
pub fn format_duration(duration: Duration) -> String {
    /// The largest duration `{:.2?}` still renders as seconds under a minute.
    const PRECISE_MAX: Duration = Duration::from_nanos(59_995_000_000);

    if duration.is_zero() {
        "0s".into()
    } else if duration < Duration::from_millis(1) {
        format!("{duration:.0?}")
    } else if duration < Duration::from_secs(1) {
        format!("{duration:.1?}")
    } else if duration < PRECISE_MAX {
        format!("{duration:.2?}")
    } else {
        format_clock(duration)
    }
}

/// A duration the way a person would say it: "6h 14m", "13m 33s", "45s".
///
/// The two largest units that are actually present, each whole. Two units
/// carry all the precision a wall-clock reading needs, and a zero unit in
/// between must not spend one of the slots: "1d 0h" would hide real minutes
/// behind it and understate the span it exists to state.
///
/// Seconds are rounded rather than dropped, so this meets the precise rendering
/// in [`format_duration`] without a gap: the last value that reads "59.99s" is
/// followed by "1m", not by a second reading of "59s".
pub fn format_clock(duration: Duration) -> String {
    let mut rest = duration
        .as_secs()
        .saturating_add(u64::from(duration.subsec_millis() >= 500));
    if rest == 0 {
        return "0s".into();
    }
    let mut parts = Vec::new();
    for (size, suffix) in [(86_400, "d"), (3_600, "h"), (60, "m"), (1, "s")] {
        let amount = rest / size;
        rest %= size;
        if amount > 0 {
            parts.push(format!("{amount}{suffix}"));
            if parts.len() == 2 {
                break;
            }
        }
    }
    parts.join(" ")
}

/// Format a long span the way a retention policy is written.
///
/// [`format_duration`] measures what a build spent and would render a month as
/// `30d`. A policy is written out in one unit, so this says "30 days".
///
/// The largest unit that divides evenly, never one that would round: this
/// describes when files get deleted, and calling 36 hours "1 day" would
/// understate that by a third.
pub fn format_span(duration: Duration) -> String {
    const MINUTE: u64 = 60;
    const HOUR: u64 = 60 * MINUTE;
    const DAY: u64 = 24 * HOUR;

    let seconds = duration.as_secs();
    let (amount, unit) = [(DAY, "day"), (HOUR, "hour"), (MINUTE, "minute")]
        .into_iter()
        .find(|(size, _)| seconds >= *size && seconds.is_multiple_of(*size))
        .map_or((seconds, "second"), |(size, unit)| (seconds / size, unit));
    if amount == 1 {
        format!("1 {unit}")
    } else {
        format!("{amount} {unit}s")
    }
}

/// Parse a duration written as a bare number of seconds or with a unit suffix.
pub fn parse_duration(value: &str) -> Result<Duration> {
    let value = value.trim();
    let (digits, multiplier) = if let Some(digits) = value.strip_suffix("ms") {
        (digits, 1)
    } else if let Some(digits) = value.strip_suffix('s') {
        (digits, 1_000)
    } else if let Some(digits) = value.strip_suffix('m') {
        (digits, 60 * 1_000)
    } else if let Some(digits) = value.strip_suffix('h') {
        (digits, 60 * 60 * 1_000)
    } else if let Some(digits) = value.strip_suffix('d') {
        (digits, 24 * 60 * 60 * 1_000)
    } else {
        (value, 1_000)
    };
    let amount: u64 = digits
        .trim()
        .parse()
        .wrap_err_with(|| format!("invalid duration: {value}"))?;
    Ok(Duration::from_millis(amount.saturating_mul(multiplier)))
}

pub fn duration_ns(duration: Duration) -> u64 {
    duration.as_nanos().try_into().unwrap_or(u64::MAX)
}

/// The size of the filesystem holding `path`, or the nearest existing ancestor.
///
/// Budgets scale with the disk, so this answers "how big is the disk tuist_cargo_cache is
/// about to fill". The nearest existing ancestor is what gets measured because
/// the cache directory usually does not exist yet the first time this is asked.
/// `None` means the question could not be answered, and every caller has a
/// fixed budget to fall back on: guessing a disk size would be worse than
/// admitting the probe failed.
pub fn disk_total_bytes(path: &Path) -> Option<u64> {
    disk_space(path).map(|space| space.total)
}

/// How big the filesystem holding `path` is, and how much of it is free.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DiskSpace {
    pub total: u64,
    /// What an unprivileged process may still write: the blocks a filesystem
    /// reserves for root are not space a build can use.
    pub available: u64,
}

/// [`disk_total_bytes`] and the free space beside it, from one probe of the
/// nearest existing ancestor.
pub(crate) fn disk_space(path: &Path) -> Option<DiskSpace> {
    let existing = path.ancestors().find(|ancestor| ancestor.exists())?;
    disk_space_at(existing)
}

/// Whether `a` and `b`, or their nearest existing ancestors, are on the same
/// filesystem. `false` when either cannot be examined.
pub(crate) fn same_disk(a: &Path, b: &Path) -> bool {
    let existing = |path: &Path| {
        path.ancestors()
            .find(|ancestor| ancestor.exists())
            .map(Path::to_path_buf)
    };
    let (Some(a), Some(b)) = (existing(a), existing(b)) else {
        return false;
    };
    same_disk_at(&a, &b)
}

#[cfg(unix)]
fn same_disk_at(a: &Path, b: &Path) -> bool {
    use std::os::unix::fs::MetadataExt as _;

    match (std::fs::metadata(a), std::fs::metadata(b)) {
        (Ok(a), Ok(b)) => a.dev() == b.dev(),
        _ => false,
    }
}

/// By drive or share: a volume mounted into a folder shares the drive letter
/// of its parent and reads as the same disk, which only costs a warning.
#[cfg(windows)]
fn same_disk_at(a: &Path, b: &Path) -> bool {
    let prefix = |path: &Path| {
        std::fs::canonicalize(path)
            .ok()
            .and_then(|path| match path.components().next() {
                Some(std::path::Component::Prefix(prefix)) => {
                    Some(prefix.as_os_str().to_ascii_lowercase())
                }
                _ => None,
            })
    };
    matches!((prefix(a), prefix(b)), (Some(a), Some(b)) if a == b)
}

/// Apple's `statvfs` counts blocks in a 32-bit field, which wraps somewhere
/// above 16TiB and would answer with a smaller disk than the one it measured --
/// quietly sizing a budget from a fraction of a large volume. `statfs` is the
/// native call there and counts in 64 bits.
#[cfg(all(unix, target_vendor = "apple"))]
fn disk_space_at(path: &Path) -> Option<DiskSpace> {
    use std::os::unix::ffi::OsStrExt as _;

    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    // SAFETY: `path` is a valid NUL-terminated C string that outlives the call,
    // and `statfs` only writes into the buffer it is given.
    let stats = unsafe {
        let mut stats = std::mem::zeroed::<libc::statfs>();
        if libc::statfs(path.as_ptr(), &mut stats) != 0 {
            return None;
        }
        stats
    };
    let block_size = u64::from(stats.f_bsize);
    // A zero product falls back rather than claiming an empty disk.
    let total = block_size
        .checked_mul(stats.f_blocks)
        .filter(|total| *total > 0)?;
    Some(DiskSpace {
        total,
        available: block_size.saturating_mul(stats.f_bavail),
    })
}

#[cfg(all(unix, not(target_vendor = "apple")))]
fn disk_space_at(path: &Path) -> Option<DiskSpace> {
    use std::os::unix::ffi::OsStrExt as _;

    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).ok()?;
    // SAFETY: `path` is a valid NUL-terminated C string that outlives the call,
    // and `statvfs` only writes into the buffer it is given.
    let stats = unsafe {
        let mut stats = std::mem::zeroed::<libc::statvfs>();
        if libc::statvfs(path.as_ptr(), &mut stats) != 0 {
            return None;
        }
        stats
    };
    // `f_frsize` is the fundamental block size `f_blocks` and `f_bavail` count
    // in. It is reported as 0 by some filesystems, which would silently answer
    // "0 bytes", so a zero product falls back rather than claiming an empty disk.
    //
    // The fields are already `u64` on 64-bit glibc, where these conversions do
    // nothing, but they narrow on 32-bit targets -- the conversions are what let
    // one body compile everywhere CI builds it.
    #[allow(clippy::useless_conversion)]
    let block_size = u64::try_from(stats.f_frsize).ok()?;
    #[allow(clippy::useless_conversion)]
    let blocks = u64::try_from(stats.f_blocks).ok()?;
    #[allow(clippy::useless_conversion)]
    let available = u64::try_from(stats.f_bavail).ok()?;
    let total = block_size.checked_mul(blocks).filter(|total| *total > 0)?;
    Some(DiskSpace {
        total,
        available: block_size.saturating_mul(available),
    })
}

#[cfg(windows)]
fn disk_space_at(path: &Path) -> Option<DiskSpace> {
    use std::os::windows::ffi::OsStrExt as _;
    use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

    let mut wide: Vec<u16> = path.as_os_str().encode_wide().collect();
    wide.push(0);
    let mut available = 0_u64;
    let mut total = 0_u64;
    // SAFETY: `wide` is NUL-terminated and outlives the call, and the out
    // parameters are either null (ignored by the API) or a valid `u64`.
    let ok = unsafe {
        GetDiskFreeSpaceExW(
            wide.as_ptr(),
            &mut available,
            &mut total,
            std::ptr::null_mut(),
        )
    };
    if ok == 0 || total == 0 {
        None
    } else {
        Some(DiskSpace { total, available })
    }
}

/// Physical memory installed in this machine, when it can be measured.
#[cfg(target_vendor = "apple")]
pub fn memory_total_bytes() -> Option<u64> {
    let mut mib = [libc::CTL_HW, libc::HW_MEMSIZE];
    let mut total = 0_u64;
    let mut length = size_of::<u64>();
    // SAFETY: the MIB names a u64 sysctl, `total` is a valid u64 out buffer of
    // exactly `length` bytes, and no new value is being set.
    let ok = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            mib.len() as libc::c_uint,
            (&raw mut total).cast(),
            &raw mut length,
            std::ptr::null_mut(),
            0,
        )
    };
    (ok == 0).then_some(total).filter(|total| *total > 0)
}

/// Memory this process may actually use, when it can be measured.
///
/// The container's limit, where there is one, rather than the host's RAM. A
/// build inside a 4GiB container on a 128GiB machine is budgeted by the 4GiB,
/// because the other 124GiB are not its to spend and reaching for them is an
/// out-of-memory kill rather than a slow build.
#[cfg(target_os = "linux")]
pub fn memory_total_bytes() -> Option<u64> {
    // SAFETY: `sysinfo` only writes into the zeroed struct it is given.
    let info = unsafe {
        let mut info = std::mem::zeroed::<libc::sysinfo>();
        if libc::sysinfo(&mut info) != 0 {
            return None;
        }
        info
    };
    // `mem_unit` narrows from u32 and `totalram` is u64 on 64-bit glibc but
    // u32 on 32-bit targets; the conversions let one body compile everywhere.
    #[allow(clippy::useless_conversion)]
    let unit = u64::from(info.mem_unit);
    #[allow(clippy::useless_conversion)]
    let total = u64::try_from(info.totalram).ok()?;
    let physical = total.checked_mul(unit).filter(|total| *total > 0)?;
    Some(match crate::cgroup::memory().limit {
        Some(limit) => physical.min(limit),
        None => physical,
    })
}

/// The parsing half, separated so it can be tested without a cgroup mount.
#[cfg(any(target_os = "linux", test))]
pub(crate) fn parse_cgroup_stat(contents: &str, field: &str) -> Option<u64> {
    contents.lines().find_map(|line| {
        let (name, value) = line.split_once(' ')?;
        (name == field).then(|| value.trim().parse().ok())?
    })
}

/// The parsing half, separated so it can be tested without a cgroup mount.
#[cfg(any(target_os = "linux", test))]
pub(crate) fn read_cgroup_text(contents: &str) -> Option<u64> {
    let value = contents.trim();
    if value == "max" {
        return None;
    }
    // cgroup v1 spells "unlimited" as a page-aligned number near i64::MAX
    // rather than in words. The largest machines built hold tens of
    // tebibytes, so anything past a pebibyte is that idiom rather than a
    // budget worth dividing into permits.
    const NO_LIMIT: u64 = 1 << 50;
    value
        .parse::<u64>()
        .ok()
        .filter(|bytes| *bytes > 0 && *bytes < NO_LIMIT)
}

/// Physical memory installed in this machine, when it can be measured.
#[cfg(windows)]
pub fn memory_total_bytes() -> Option<u64> {
    use windows_sys::Win32::System::SystemInformation::{GlobalMemoryStatusEx, MEMORYSTATUSEX};

    // SAFETY: the struct is a valid out parameter with its length declared,
    // which is all the API requires.
    let status = unsafe {
        let mut status = std::mem::zeroed::<MEMORYSTATUSEX>();
        status.dwLength = size_of::<MEMORYSTATUSEX>() as u32;
        if GlobalMemoryStatusEx(&mut status) == 0 {
            return None;
        }
        status
    };
    Some(status.ullTotalPhys).filter(|total| *total > 0)
}

/// Fallback for hosts with no supported probe.
#[cfg(not(any(target_vendor = "apple", target_os = "linux", windows)))]
pub fn memory_total_bytes() -> Option<u64> {
    None
}

/// Memory the machine could hand a new process right now, when measurable.
///
/// "Available" deliberately counts reclaimable memory rather than free pages
/// alone: a machine whose RAM is full of page cache is not out of memory, and
/// treating it as such would defer compilations that were going to run fine.
#[cfg(target_os = "linux")]
pub fn memory_available_bytes() -> Option<u64> {
    // `MemAvailable` is the kernel's own estimate of exactly this question,
    // accounting for reclaimable caches; summing fields by hand would just
    // reimplement it worse. It describes the host, though -- `/proc/meminfo`
    // is not namespaced -- so a container's own headroom bounds it below.
    let meminfo = std::fs::read_to_string("/proc/meminfo").ok()?;
    let line = meminfo
        .lines()
        .find_map(|line| line.strip_prefix("MemAvailable:"))?;
    let kibibytes = line
        .trim()
        .trim_end_matches("kB")
        .trim()
        .parse::<u64>()
        .ok()?;
    let host = kibibytes.checked_mul(1024)?;
    let available = crate::cgroup::memory()
        .headroom
        .map_or(host, |free| host.min(free));
    // Zero is a real answer here -- a cgroup at its limit has nothing left --
    // and the caller has to be able to tell it from "cannot measure".
    Some(available)
}

/// Memory the machine could hand a new process right now, when measurable.
//
// libc deprecates its Mach bindings in favor of the `mach2` crate, but these
// four symbols are stable kernel ABI and not worth a dependency that exists
// to re-export them.
#[allow(deprecated)]
#[cfg(target_vendor = "apple")]
pub fn memory_available_bytes() -> Option<u64> {
    let mut count = libc::HOST_VM_INFO64_COUNT;
    // SAFETY: the buffer is a zeroed `vm_statistics64` and `count` declares
    // its size in `integer_t` units, which is what the call requires.
    let stats = unsafe {
        let mut stats = std::mem::zeroed::<libc::vm_statistics64>();
        if libc::host_statistics64(
            libc::mach_host_self(),
            libc::HOST_VM_INFO64,
            (&raw mut stats).cast(),
            &mut count,
        ) != libc::KERN_SUCCESS
        {
            return None;
        }
        stats
    };
    // Free plus what the kernel can take back without swapping: inactive pages
    // and purgeable memory. Speculative pages are already inside `free_count`.
    // SAFETY: reading a kernel-exported integer.
    let page_size = unsafe { libc::vm_page_size } as u64;
    let pages = u64::from(stats.free_count)
        .checked_add(u64::from(stats.inactive_count))?
        .checked_add(u64::from(stats.purgeable_count))?;
    pages.checked_mul(page_size)
}

/// Fallback for hosts with no supported probe.
#[cfg(not(any(target_vendor = "apple", target_os = "linux")))]
pub fn memory_available_bytes() -> Option<u64> {
    None
}

/// Whether a reflink from inside `source_dir` can land inside
/// `destination_dir`.
///
/// Answered by doing one, not by guessing from the platform: reflink support
/// is a property of the mounted filesystem, and it takes both ends -- a store
/// on btrfs cannot reflink into a target directory on ext4, so probing one
/// side alone proves nothing about the copy that actually happens. The
/// destination is anchored at its nearest existing ancestor rather than
/// created, because the real directory may be one cargo has not made yet and
/// making it here would change what target placement later sees. Any failure
/// answers no: every caller is deciding whether to promise sharing, and a
/// promise needs more than a maybe.
pub fn reflinks_work(source_dir: &Path, destination_dir: &Path) -> bool {
    fn probe(source_dir: &Path, destination_dir: &Path) -> Option<()> {
        std::fs::create_dir_all(source_dir).ok()?;
        let anchor = destination_dir
            .ancestors()
            .find(|ancestor| ancestor.exists())?;
        let source_temp = tempfile::tempdir_in(source_dir).ok()?;
        let destination_temp = tempfile::tempdir_in(anchor).ok()?;
        let source = source_temp.path().join("source");
        std::fs::write(&source, b"tuist_cargo_cache reflink probe").ok()?;
        reflink_copy::reflink(&source, destination_temp.path().join("destination")).ok()
    }
    probe(source_dir, destination_dir).is_some()
}

/// Generate an unpredictable alphanumeric string.
///
/// Only the Windows named-pipe endpoint needs this, but it is compiled
/// everywhere so that every platform's CI type-checks it.
pub fn random_string(length: usize) -> String {
    use rand::RngExt as _;
    use rand::distr::Alphanumeric;

    rand::rng()
        .sample_iter(&Alphanumeric)
        .take(length)
        .map(char::from)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn compiler_input_snapshot_fails_closed() {
        let directory = tempfile::tempdir().unwrap();
        let missing = directory.path().join("missing-input");
        let error = snapshot_compiler_inputs([missing.as_path()], None).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("failed to capture compiler input snapshot")
        );
    }

    #[test]
    fn cgroup_usage_discounts_the_page_cache() {
        // The shape of a real `memory.stat`: the field wanted is neither
        // first nor last, and a prefix of its name must not match it.
        let stat = "anon 1000\nfile 8000\nkernel 12\ninactive_file 7000\nslab 40\n";
        assert_eq!(parse_cgroup_stat(stat, "inactive_file"), Some(7000));
        assert_eq!(parse_cgroup_stat(stat, "anon"), Some(1000));
        // `file` must not be answered by `inactive_file`.
        assert_eq!(parse_cgroup_stat(stat, "file"), Some(8000));
        assert_eq!(parse_cgroup_stat(stat, "absent"), None);
        assert_eq!(parse_cgroup_stat("malformed\n", "anon"), None);
    }

    #[test]
    fn cgroup_limits_are_read_and_no_limit_is_recognized() {
        assert_eq!(
            read_cgroup_text("4294967296\n"),
            Some(4 * 1024 * 1024 * 1024)
        );
        // cgroup v2 spells "unlimited" in words.
        assert_eq!(read_cgroup_text("max\n"), None);
        // cgroup v1 spells it as a number nothing real could reach. Budgeting
        // permits out of it would be the same as having no limit, but with
        // arithmetic in between.
        assert_eq!(read_cgroup_text("9223372036854771712"), None);
        assert_eq!(read_cgroup_text("0"), None);
        assert_eq!(read_cgroup_text("not a number"), None);
        assert_eq!(read_cgroup_text(""), None);
    }

    #[test]
    fn writes_files_atomically() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("nested").join("report.json");
        write_atomic(&path, b"{}\n").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"{}\n");

        write_atomic(&path, b"[]\n").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"[]\n");
    }

    #[test]
    fn random_strings_have_the_requested_length_and_differ() {
        let first = random_string(12);
        assert_eq!(first.chars().count(), 12);
        assert!(first.chars().all(|character| character.is_alphanumeric()));
        assert_ne!(first, random_string(12));
        assert!(random_string(0).is_empty());
    }

    #[test]
    fn measures_the_disk_holding_a_path() {
        let directory = tempfile::tempdir().unwrap();
        let total = disk_total_bytes(directory.path()).expect("the test disk has a size");
        assert!(total > 0);
        // The directory need not exist: budgets are resolved before the cache
        // directory is created.
        let missing = directory.path().join("not").join("created").join("yet");
        assert_eq!(disk_total_bytes(&missing), Some(total));
    }

    #[test]
    fn the_reflink_probe_anchors_a_destination_nobody_created_yet() {
        let directory = tempfile::tempdir().unwrap();
        let store = directory.path().join("cache");
        // The target directory does not exist before the first build; the
        // probe must answer for the filesystem it will be created on, without
        // creating it.
        let unmade = directory.path().join("checkout").join("target");
        assert_eq!(
            reflinks_work(&store, &unmade),
            reflinks_work(&store, directory.path()),
            "a missing destination answers as its filesystem, not as a failure"
        );
        assert!(!unmade.exists(), "the probe must not create the directory");
    }

    #[test]
    fn durations_read_as_precision_below_a_minute_and_as_a_clock_above_one() {
        // Below a minute the fraction is the point of the measurement.
        assert_eq!(format_duration(Duration::from_micros(400)), "400\u{b5}s");
        assert_eq!(format_duration(Duration::from_millis(1_234)), "1.23s");
        assert_eq!(format_duration(Duration::from_millis(59_994)), "59.99s");
        // At a minute it becomes a time somebody reads rather than converts.
        assert_eq!(format_duration(Duration::from_secs(60)), "1m");
        assert_eq!(format_duration(Duration::from_secs(813)), "13m 33s");
        assert_eq!(
            format_duration(Duration::from_secs(6 * 3_600 + 840)),
            "6h 14m"
        );
        // A duration that never happened is not "0ns".
        assert_eq!(format_duration(Duration::ZERO), "0s");
    }

    #[test]
    fn a_minute_is_never_rendered_as_sixty_seconds() {
        // `{:.2?}` rounds, so every value in this range would read "60.00s"
        // beside the "1m 5s" of a build one tick longer.
        for (duration, expected) in [
            (Duration::from_nanos(59_994_999_999), "59.99s"),
            (Duration::from_nanos(59_995_000_000), "1m"),
            (Duration::from_nanos(59_999_999_999), "1m"),
            (Duration::from_secs(60), "1m"),
        ] {
            assert_eq!(format_duration(duration), expected, "for {duration:?}");
        }
    }

    #[test]
    fn clock_readings_keep_the_two_units_that_are_present() {
        assert_eq!(format_clock(Duration::from_secs(45)), "45s");
        assert_eq!(format_clock(Duration::from_secs(61)), "1m 1s");
        assert_eq!(format_clock(Duration::from_secs(6 * 3_600)), "6h");
        // A zero unit in the middle must not spend a slot and hide the minutes.
        assert_eq!(format_clock(Duration::from_secs(86_400 + 300)), "1d 5m");
        assert_eq!(format_clock(Duration::from_secs(86_400 + 3_660)), "1d 1h");
        // Seconds are rounded, so this picks up where the precise rendering in
        // format_duration leaves off instead of repeating a second of it.
        assert_eq!(format_clock(Duration::from_millis(45_900)), "46s");
        assert_eq!(format_clock(Duration::from_millis(45_400)), "45s");
        assert_eq!(format_clock(Duration::from_millis(900)), "1s");
        assert_eq!(format_clock(Duration::from_millis(400)), "0s");
        // The rounding carries into the larger unit rather than showing "1m 60s".
        assert_eq!(format_clock(Duration::from_millis(119_600)), "2m");
    }

    #[test]
    fn formats_spans_in_the_units_a_policy_is_written_in() {
        assert_eq!(format_span(Duration::from_secs(30 * 86_400)), "30 days");
        assert_eq!(format_span(Duration::from_secs(86_400)), "1 day");
        // A policy of 36 hours is not "1 day": this text says when files go.
        assert_eq!(format_span(Duration::from_secs(36 * 3_600)), "36 hours");
        assert_eq!(format_span(Duration::from_secs(90 * 60)), "90 minutes");
        assert_eq!(format_span(Duration::from_secs(45)), "45 seconds");
        assert_eq!(format_span(Duration::from_secs(7_200)), "2 hours");
        assert_eq!(format_span(Duration::from_secs(60)), "1 minute");
        assert_eq!(format_span(Duration::from_secs(90)), "90 seconds");
        assert_eq!(format_span(Duration::from_secs(5)), "5 seconds");
    }

    #[test]
    fn parses_durations_with_and_without_units() {
        assert_eq!(parse_duration("30").unwrap(), Duration::from_secs(30));
        assert_eq!(parse_duration("30s").unwrap(), Duration::from_secs(30));
        assert_eq!(parse_duration("250ms").unwrap(), Duration::from_millis(250));
        assert_eq!(parse_duration("10m").unwrap(), Duration::from_secs(600));
        assert_eq!(parse_duration("2h").unwrap(), Duration::from_secs(7_200));
        assert!(parse_duration("soon").is_err());
    }
}
