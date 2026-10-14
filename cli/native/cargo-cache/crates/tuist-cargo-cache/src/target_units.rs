//! Unused build units inside managed target directories that are still in use.
//!
//! Collection removes a whole target directory once its checkout is gone or
//! has gone unused. A checkout in daily use never qualifies, yet it keeps every
//! unit it ever built: each lockfile update, feature change, or toolchain
//! update leaves the previous units behind. From Cargo 1.100 a unit owns one
//! directory, `<profile>/build/<package>/<hash>/`, holding its outputs, its
//! fingerprint, and a build script's run output, so removing that directory
//! removes the unit completely. The next build that needs it compiles it
//! again, or restores it from the cache.
//!
//! Cargo reads each unit's fingerprint hash on every build, including when the
//! unit is fresh and nothing is written, so the access time of the files in
//! `fingerprint/` is when a build last used the unit. That only holds where the
//! filesystem records access times, which [`access_times_tracked`] checks
//! before anything is removed. Linux's default `relatime` refreshes an access
//! time at most once a day, so a day of slack is added to the age limit.
//!
//! Earlier Cargo spreads a unit across `deps/`, `.fingerprint/`, and `build/`
//! by file name, so those units are not removed one at a time. Once no build
//! has used any of them for the age limit, which is what happens after the
//! toolchain moves to Cargo 1.100, that whole layout is removed at once.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

/// Names the directory unused units are moved into before they are deleted,
/// inside the profile they came from.
const REMOVAL_PREFIX: &str = ".tuist_cargo_cache-removing-";
/// `relatime` refreshes an access time once it is a day old.
const ACCESS_TIME_SLACK: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub(crate) struct UnitOutcome {
    pub removed_units: u64,
    pub removed_bytes: u64,
}

/// Whether reading a file below `directory` updates its access time.
///
/// Checked by reading a file whose access time is two days old, which
/// `strictatime` and `relatime` both refresh and `noatime` does not. Without
/// that, an access time says when the unit was built, not when it was last
/// used, and a unit that stays fresh would look unused.
pub(crate) fn access_times_tracked(directory: &Path) -> bool {
    let probe = || -> std::io::Result<bool> {
        let file = tempfile::NamedTempFile::new_in(directory)?;
        std::io::Write::write_all(&mut file.as_file(), b"access time probe")?;
        let past = SystemTime::now() - 2 * ACCESS_TIME_SLACK;
        file.as_file().set_times(
            std::fs::FileTimes::new()
                .set_accessed(past)
                .set_modified(past),
        )?;
        std::fs::File::open(file.path())?.read_to_end(&mut Vec::new())?;
        Ok(std::fs::metadata(file.path())?.accessed()? > past + ACCESS_TIME_SLACK)
    };
    probe().unwrap_or(false)
}

/// Remove the units in the target directory `view` that no build has used for
/// `max_age`.
///
/// The caller holds Cargo's locks for `view`, so no build reads a unit while
/// it goes. A dry run reports what would be removed and touches nothing.
pub(crate) fn prune(view: &Path, max_age: Duration, now: SystemTime, dry_run: bool) -> UnitOutcome {
    let mut outcome = UnitOutcome::default();
    let Some(cutoff) = now.checked_sub(max_age.saturating_add(ACCESS_TIME_SLACK)) else {
        return outcome;
    };
    for profile in profiles(view) {
        // Counted, because the caller measured the view before this pass and
        // would otherwise weigh bytes already gone against the budget.
        outcome.removed_bytes += remove_abandoned_removals(&profile, dry_run);
        let (units, doomed) = unused(&profile, cutoff);
        if doomed.is_empty() {
            continue;
        }
        let bytes = doomed
            .iter()
            .map(|path| crate::target::tree_bytes(path))
            .sum::<u64>();
        if !dry_run && let Err(error) = remove(&profile, &doomed) {
            log::warn!(
                "could not remove unused build units in {}: {error}",
                profile.display()
            );
            continue;
        }
        outcome.removed_units += units;
        outcome.removed_bytes += bytes;
    }
    outcome
}

/// The profile directories in `view`: those Cargo keeps a `.cargo-lock` in,
/// up to three levels down. That covers `<profile>`, `<triple>/<profile>`,
/// and an editor's `rust-analyzer/<triple>/<profile>`, the same depth the
/// build-lock scan in [`crate::target`] looks.
fn profiles(view: &Path) -> Vec<PathBuf> {
    let mut profiles = Vec::new();
    let mut pending = subdirectories(view)
        .into_iter()
        .map(|directory| (directory, 1))
        .collect::<Vec<_>>();
    while let Some((directory, depth)) = pending.pop() {
        if directory.join(".cargo-lock").is_file() {
            profiles.push(directory);
        } else if depth < 3 {
            pending.extend(
                subdirectories(&directory)
                    .into_iter()
                    .map(|child| (child, depth + 1)),
            );
        }
    }
    profiles
}

/// The unused units in `profile`, counted, and the paths that hold them, with
/// every pre-1.100 fingerprint ahead of the outputs it vouches for.
fn unused(profile: &Path, cutoff: SystemTime) -> (u64, Vec<PathBuf>) {
    let mut units = 0;
    let mut doomed = Vec::new();

    let fingerprints = profile.join(".fingerprint");
    let old_units = subdirectories(&fingerprints);
    let old_last_use = old_units
        .iter()
        .map(|unit| last_use(unit))
        .max()
        .or_else(|| modified(&fingerprints));
    if old_last_use.is_some_and(|used| used < cutoff) {
        units += old_units.len() as u64;
        doomed.push(fingerprints);
        let deps = profile.join("deps");
        if deps.is_dir() {
            doomed.push(deps);
        }
        doomed.extend(
            subdirectories(&profile.join("build"))
                .into_iter()
                .filter(|directory| is_old_unit(directory)),
        );
    } else if !fingerprints.exists() {
        // Every pre-1.100 build creates `.fingerprint/` beside `deps/`, and
        // it is removed first, so outputs without it are what an interrupted
        // removal left. No Cargo can use them without their fingerprints.
        let deps = profile.join("deps");
        if std::fs::read_dir(&deps).is_ok_and(|mut entries| entries.next().is_some()) {
            doomed.push(deps);
        }
        doomed.extend(
            subdirectories(&profile.join("build"))
                .into_iter()
                .filter(|directory| is_old_unit(directory)),
        );
    }

    for package in subdirectories(&profile.join("build")) {
        for unit in subdirectories(&package) {
            let fingerprint = unit.join("fingerprint");
            if fingerprint.is_dir() && last_use(&fingerprint) < cutoff {
                units += 1;
                doomed.push(unit);
            }
        }
    }
    (units, doomed)
}

/// Whether a directory in `build/` is a pre-1.100 unit, `<package>-<hash>`,
/// rather than a 1.100 package directory holding `<hash>/fingerprint/`.
fn is_old_unit(directory: &Path) -> bool {
    let has_hash_suffix = directory
        .file_name()
        .and_then(|name| name.to_str())
        .and_then(|name| name.rsplit_once('-'))
        .is_some_and(|(_, hash)| hash.len() == 16 && hash.bytes().all(|b| b.is_ascii_hexdigit()));
    has_hash_suffix
        && !subdirectories(directory)
            .iter()
            .any(|child| child.join("fingerprint").is_dir())
}

/// The latest access or modification of anything directly in `directory`, or
/// of the directory itself. A time that cannot be read counts as now, so a
/// unit is never removed on a guess.
pub(crate) fn last_use(directory: &Path) -> SystemTime {
    let mut latest = modified(directory).unwrap_or_else(SystemTime::now);
    let Ok(listing) = std::fs::read_dir(directory) else {
        return SystemTime::now();
    };
    for entry in listing.flatten() {
        let Ok(metadata) = entry.metadata() else {
            return SystemTime::now();
        };
        for time in [metadata.accessed(), metadata.modified()] {
            match time {
                Ok(time) => latest = latest.max(time),
                Err(_) => return SystemTime::now(),
            }
        }
    }
    latest
}

fn modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .ok()
}

/// Move `doomed` into one directory in `profile`, then delete it.
///
/// A unit is moved whole before any of its files go, so an interrupted
/// removal never leaves a fingerprint vouching for outputs that are gone. The
/// next collection finishes whatever an interrupted one left.
fn remove(profile: &Path, doomed: &[PathBuf]) -> std::io::Result<()> {
    let removal = profile.join(format!("{REMOVAL_PREFIX}{}", std::process::id()));
    std::fs::create_dir_all(&removal)?;
    for (index, path) in doomed.iter().enumerate() {
        std::fs::rename(path, removal.join(index.to_string()))?;
        // A 1.100 package directory with no units left is empty.
        if let Some(package) = path.parent()
            && package.parent().and_then(Path::file_name) == Some("build".as_ref())
        {
            let _ = std::fs::remove_dir(package);
        }
    }
    std::fs::remove_dir_all(&removal)
}

/// Finish deleting what an interrupted collection moved aside in `profile`.
/// Returns the bytes those leftovers held; a dry run only counts them.
fn remove_abandoned_removals(profile: &Path, dry_run: bool) -> u64 {
    let Ok(listing) = std::fs::read_dir(profile) else {
        return 0;
    };
    let mut bytes = 0;
    for entry in listing.flatten() {
        if entry
            .file_name()
            .to_string_lossy()
            .starts_with(REMOVAL_PREFIX)
        {
            let size = crate::target::tree_bytes(&entry.path());
            if dry_run || std::fs::remove_dir_all(entry.path()).is_ok() {
                bytes += size;
            }
        }
    }
    bytes
}

fn subdirectories(directory: &Path) -> Vec<PathBuf> {
    let Ok(listing) = std::fs::read_dir(directory) else {
        return Vec::new();
    };
    listing
        .flatten()
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir()))
        .map(|entry| entry.path())
        .collect()
}

#[cfg(test)]
#[path = "target_units_tests.rs"]
mod tests;
