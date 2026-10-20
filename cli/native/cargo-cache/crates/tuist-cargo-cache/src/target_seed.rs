//! Registry build units copied into a profile a checkout has not built yet.
//!
//! A new checkout's first build asks the cache for every unit, which means
//! Cargo starts the tuist_cargo_cache shim once per unit, and each one keys its inputs and
//! restores its outputs. From Cargo 1.100 a unit is one directory,
//! `<profile>/build/<package>/<hash>/`, holding its outputs, its fingerprint,
//! and a build script's run output. A registry or git package's unit hash and
//! fingerprint are the same in every checkout on a machine, so its directory
//! copied from another checkout's target directory is fresh in Cargo's eyes,
//! and Cargo skips the unit without starting rustc or the shim.
//!
//! The copy keeps what Cargo's freshness check depends on:
//!
//! - Only registry and git packages are copied. A path package's fingerprint
//!   trusts the modification times of its sources, so a unit copied from a
//!   checkout with different sources could pass as fresh.
//! - Modification times are copied, because Cargo rebuilds a unit whose
//!   dependency's outputs are newer than its own.
//! - Files are copied, which is a reflink where the filesystem supports one.
//!   Only read-only files are hard-linked: those are cache objects nothing
//!   writes in place. Fingerprints, build-script output, and `OUT_DIR` contents
//!   are rewritten in place by later builds, and sharing them would let one
//!   checkout's build change another's.
//! - Each unit is copied beside its final name and renamed into place, so an
//!   interrupted copy never leaves a fingerprint without its outputs.
//!
//! A unit copied from the other checkout that this build does not use is
//! removed later by [`crate::target_units`] like any other unused unit.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};
use std::time::Duration;

/// Where each unit is copied before it is renamed into place.
const STAGING_SUFFIX: &str = ".tuist_cargo_cache-seeding-";
/// How long before the most recent read in a donor's profile a unit may have
/// been read and still count as used by that profile's latest build.
/// `relatime` refreshes access times daily.
const RECENT_USE: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct SeedOutcome {
    pub units: u64,
    /// The checkout the units came from, when any did.
    pub donor: Option<PathBuf>,
}

/// A target directory units may be copied from.
#[derive(Debug, Clone)]
pub(crate) struct Donor {
    pub directory: PathBuf,
    pub workspace_root: PathBuf,
    /// When a build last claimed the directory, in seconds since the epoch.
    /// Donors are tried most recent first.
    pub updated_secs: u64,
}

impl Donor {
    /// Every path that reaches the donor's files. Cargo writes through the
    /// checkout's `target` link, so paths it records spell the target
    /// directory as `<checkout>/target` rather than the managed directory,
    /// and the checkout itself may be named by a build script too.
    fn spellings(&self) -> [&Path; 2] {
        [self.directory.as_path(), self.workspace_root.as_path()]
    }

    /// `path`, inside the donor's managed directory, and the same place
    /// spelled through the checkout's `target` link.
    fn respellings(&self, path: &Path) -> Vec<PathBuf> {
        let mut spellings = vec![path.to_path_buf()];
        if let Ok(inside) = path.strip_prefix(&self.directory) {
            spellings.push(self.workspace_root.join("target").join(inside));
        }
        spellings
    }
}

/// Whether `cargo -V` output names Cargo 1.100 or later, the first release
/// that keeps each unit in a directory of its own.
pub(crate) fn keeps_units_in_directories(version: &str) -> bool {
    let Some(number) = version.split_whitespace().nth(1) else {
        return false;
    };
    let mut parts = number.split(['.', '-']);
    match (
        parts.next().and_then(|part| part.parse::<u64>().ok()),
        parts.next().and_then(|part| part.parse::<u64>().ok()),
    ) {
        (Some(major), Some(minor)) => major > 1 || (major == 1 && minor >= 100),
        _ => false,
    }
}

/// The profile directories, relative to the target directory, a Cargo
/// command writes: the host profile, and the same profile below each
/// `--target` it names.
pub(crate) fn profile_directories(arguments: &[String]) -> Vec<PathBuf> {
    let profile = match crate::managed_linker::cargo_profile(arguments).as_str() {
        "dev" | "test" => "debug".to_owned(),
        "bench" => "release".to_owned(),
        other => other.to_owned(),
    };
    let mut directories = vec![PathBuf::from(&profile)];
    for target in crate::managed_linker::cargo_targets(arguments) {
        // A target given as a JSON file builds under the file's stem.
        if let Some(stem) = Path::new(target.trim()).file_stem() {
            directories.push(Path::new(stem).join(&profile));
        }
    }
    directories
}

/// The registry and git packages in a lockfile: those with a `source`, less
/// any name a path package also uses.
pub(crate) fn registry_packages(lockfile: &str) -> BTreeSet<String> {
    let Ok(lock) = lockfile.parse::<toml::Table>() else {
        return BTreeSet::new();
    };
    let packages = lock
        .get("package")
        .and_then(toml::Value::as_array)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let mut registry = BTreeSet::new();
    let mut path = BTreeSet::new();
    for package in packages {
        let Some(name) = package.get("name").and_then(toml::Value::as_str) else {
            continue;
        };
        if package.get("source").is_some() {
            registry.insert(name.to_owned());
        } else {
            path.insert(name.to_owned());
        }
    }
    &registry - &path
}

/// Copy `packages`' units into each profile directory, relative to `lane`
/// in `view`, that has no `build/` directory yet. `lane` is empty for a
/// build's own profiles, or the directory a check lane or the editor writes
/// below the managed target, whose units come from the same directory in each
/// donor. `profiles` starts with the host profile; the same profile below any
/// target triple a donor has built is seeded too, since a target chosen by
/// Cargo configuration or `host-tuple` never appears as a directory name in
/// the arguments. Each directory comes from the first donor, most recent
/// first, that has usable units for it.
pub(crate) fn seed(
    view: &Path,
    lane: &Path,
    profiles: &[PathBuf],
    packages: &BTreeSet<String>,
    donors: &[Donor],
) -> SeedOutcome {
    let mut outcome = SeedOutcome::default();
    let Some(host) = profiles.first() else {
        return outcome;
    };
    if packages.is_empty() {
        return outcome;
    }
    let view = view.join(lane);
    let mut settled = BTreeSet::new();
    for donor in donors {
        let donor_lane = donor.directory.join(lane);
        let mut candidates = profiles.to_vec();
        candidates.extend(
            subdirectories(&donor_lane)
                .into_iter()
                .filter_map(|triple| Some(Path::new(triple.file_name()?).join(host)))
                .filter(|candidate| candidate != host),
        );
        for profile in candidates {
            if settled.contains(&profile) {
                continue;
            }
            let destination = view.join(&profile);
            if destination.join("build").exists() {
                settled.insert(profile);
                continue;
            }
            let source = donor_lane.join(&profile);
            if !has_units(&source.join("build")) {
                continue;
            }
            match seed_profile(donor, &source, &destination, packages) {
                Ok(Copied::Units(0) | Copied::Busy) => {}
                Ok(Copied::Units(units)) => {
                    outcome.units += units;
                    outcome
                        .donor
                        .get_or_insert_with(|| donor.workspace_root.clone());
                    settled.insert(profile);
                }
                Ok(Copied::Built) => {
                    settled.insert(profile);
                }
                Err(error) => log::debug!(
                    "could not copy build units from {}: {error}",
                    source.display()
                ),
            }
        }
    }
    outcome
}

/// What seeding one profile directory from one donor came to.
enum Copied {
    /// Units copied; none means the donor had nothing usable, and the next
    /// donor is worth trying.
    Units(u64),
    /// A build holds one of the two profiles.
    Busy,
    /// A build in this checkout started the profile first.
    Built,
}

/// Whether `build` holds any Cargo 1.100 unit, `<package>/<hash>/fingerprint`.
fn has_units(build: &Path) -> bool {
    subdirectories(build).iter().any(|package| {
        subdirectories(package)
            .iter()
            .any(|unit| unit.join("fingerprint").is_dir())
    })
}

/// Copy one profile's units, holding both profiles' Cargo locks so neither
/// checkout builds meanwhile.
fn seed_profile(
    donor: &Donor,
    source: &Path,
    destination: &Path,
    packages: &BTreeSet<String>,
) -> std::io::Result<Copied> {
    let Some(_source_lock) = try_lock(&source.join(".cargo-lock"))? else {
        return Ok(Copied::Busy);
    };
    std::fs::create_dir_all(destination)?;
    let Some(_destination_lock) = try_lock(&destination.join(".cargo-lock"))? else {
        return Ok(Copied::Busy);
    };
    // A build that got the lock first may have started this profile.
    if destination.join("build").exists() {
        return Ok(Copied::Built);
    }
    remove_abandoned_staging(destination);
    // Only the units this profile's latest build read, when access times say
    // which those are: the ones read within a day of its most recent read. A
    // build of another profile or project in the donor does not move this.
    // Without access times every unit of the package is copied, and the ones
    // this checkout does not use are collected later.
    let used_since = if crate::target_units::access_times_tracked(source) {
        subdirectories(&source.join("build"))
            .iter()
            .flat_map(|package| subdirectories(package))
            .map(|unit| unit.join("fingerprint"))
            .filter(|fingerprint| fingerprint.is_dir())
            .map(|fingerprint| crate::target_units::last_use(&fingerprint))
            .max()
            .and_then(|latest| latest.checked_sub(RECENT_USE))
    } else {
        None
    };
    let mut units = 0;
    for package in subdirectories(&source.join("build")) {
        let Some(name) = package.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if !packages.contains(name) {
            continue;
        }
        for unit in subdirectories(&package) {
            let fingerprint = unit.join("fingerprint");
            if !fingerprint.is_dir()
                || used_since
                    .is_some_and(|since| crate::target_units::last_use(&fingerprint) < since)
            {
                continue;
            }
            let Some(hash) = unit.file_name() else {
                continue;
            };
            match copy_unit(&unit, destination, name, hash, donor) {
                Ok(()) => units += 1,
                Err(error) => log::debug!("did not copy {}: {error}", unit.display()),
            }
        }
    }
    // Build-script launchers in the copied units exec the tuist_cargo_cache binary pinned
    // beside the profile, so a script Cargo later reruns needs it here too.
    let shims = source.join(".tuist_cargo_cache-build-script-shims");
    if units > 0 && shims.is_dir() {
        let staging = destination.join(format!(
            ".tuist_cargo_cache-build-script-shims{STAGING_SUFFIX}{}",
            std::process::id()
        ));
        let shims_destination = destination.join(".tuist_cargo_cache-build-script-shims");
        let links = Links {
            source: &shims,
            destination: &shims_destination,
            donor,
        };
        match copy_tree(&shims, &staging, &links)
            .and_then(|()| std::fs::rename(&staging, &shims_destination))
        {
            Ok(()) => {}
            Err(error) => {
                let _ = std::fs::remove_dir_all(&staging);
                log::debug!("did not copy the build-script shims: {error}");
            }
        }
    }
    Ok(Copied::Units(units))
}

fn try_lock(path: &Path) -> std::io::Result<Option<fslock::LockFile>> {
    let mut lock = fslock::LockFile::open(path)?;
    Ok(lock.try_lock()?.then_some(lock))
}

/// Copy `unit` to `build/<package>/<hash>` in `profile` by way of a staging
/// directory beside the profile's `build/`. Nothing is created under `build/`
/// until the unit is complete, since a `build/` directory is what tells the
/// next donor this profile has been built.
fn copy_unit(
    unit: &Path,
    profile: &Path,
    package: &str,
    hash: &std::ffi::OsStr,
    donor: &Donor,
) -> std::io::Result<()> {
    if let Some(path) = foreign_path_in_output(unit, donor) {
        return Err(std::io::Error::other(format!(
            "its build-script output names {path}"
        )));
    }
    let final_path = profile.join("build").join(package).join(hash);
    let staging = profile.join(format!(
        ".{package}-{}{STAGING_SUFFIX}{}",
        hash.to_string_lossy(),
        std::process::id()
    ));
    let links = Links {
        source: unit,
        destination: &final_path,
        donor,
    };
    let copied = copy_tree(unit, &staging, &links).and_then(|()| {
        std::fs::create_dir_all(profile.join("build").join(package))?;
        std::fs::rename(&staging, &final_path)
    });
    if copied.is_err() {
        let _ = std::fs::remove_dir_all(&staging);
    }
    copied
}

/// A path into the donor's target directory in a build script's recorded
/// output, other than its own `OUT_DIR`.
///
/// Cargo rewrites the `OUT_DIR` it recorded in `run/root-output` to the new
/// one when it replays `run/stdout`, so `cargo:rustc-link-search` into the
/// script's own output follows the copy. Any other path into the donor would
/// keep pointing there, and the copied unit would depend on another checkout.
fn foreign_path_in_output(unit: &Path, donor: &Donor) -> Option<String> {
    let stdout = std::fs::read(unit.join("run/stdout")).ok()?;
    let stdout = String::from_utf8_lossy(&stdout);
    let out_dir = std::fs::read_to_string(unit.join("run/root-output")).unwrap_or_default();
    let remaining = if out_dir.trim().is_empty() {
        stdout.into_owned()
    } else {
        stdout.replace(out_dir.trim(), "")
    };
    let spellings = donor
        .spellings()
        .into_iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    // Tools such as CMake write a path with forward slashes on Windows, so the
    // stdout check looks for that spelling too.
    let remaining_slashes = remaining.replace('\\', "/");
    spellings
        .iter()
        .find(|path| {
            remaining.contains(path.as_str())
                || remaining_slashes.contains(path.replace('\\', "/").as_str())
        })
        .cloned()
        .or_else(|| donor_path_in_files(&unit.join("out"), &spellings))
}

/// The most bytes read from one unit's output files while looking for a donor
/// path. A unit that holds more than this is left unseeded, since seeding must
/// stay quick and nothing can say the rest is clean.
const SCAN_BUDGET: u64 = 64 * 1024 * 1024;

/// How much of a file is read at a time.
const SCAN_CHUNK: usize = 64 * 1024;

/// A donor path named by a file a build script left in its `OUT_DIR`.
///
/// Cargo rewrites `OUT_DIR` only in the stdout it replays, so a file such as
/// CMake's cache that records `OUT_DIR/build` keeps naming the donor, and the
/// script fails in the checkout that received the copy. Files are read in
/// chunks, so a large one is checked without being held in memory. Links are
/// not followed. A file or directory that cannot be read, or output past the
/// scan budget, keeps the unit out, since nothing can say it is clean.
fn donor_path_in_files(directory: &Path, spellings: &[String]) -> Option<String> {
    // A path may be written with either separator, so look for both.
    let mut needles: Vec<String> = Vec::new();
    for spelling in spellings {
        for needle in [spelling.clone(), spelling.replace('\\', "/")] {
            if !needles.contains(&needle) {
                needles.push(needle);
            }
        }
    }
    let mut budget = SCAN_BUDGET;
    scan_directory(directory, &needles, &mut budget)
}

fn scan_directory(directory: &Path, needles: &[String], budget: &mut u64) -> Option<String> {
    let unreadable = || Some(format!("{} (unreadable)", directory.display()));
    let entries = match std::fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return None,
        Err(_) => return unreadable(),
    };
    for entry in entries {
        let Ok(entry) = entry else {
            return unreadable();
        };
        let Ok(kind) = entry.file_type() else {
            return unreadable();
        };
        if kind.is_dir() {
            if let Some(found) = scan_directory(&entry.path(), needles, budget) {
                return Some(found);
            }
        } else if kind.is_file()
            && let Some(found) = scan_file(&entry.path(), needles, budget)
        {
            return Some(found);
        }
    }
    None
}

fn scan_file(path: &Path, needles: &[String], budget: &mut u64) -> Option<String> {
    use std::io::Read;
    let unreadable = || Some(format!("{} (unreadable)", path.display()));
    let Ok(mut file) = std::fs::File::open(path) else {
        return unreadable();
    };
    let longest = needles.iter().map(String::len).max().unwrap_or(0);
    let mut window: Vec<u8> = Vec::new();
    let mut chunk = vec![0u8; SCAN_CHUNK];
    loop {
        let read = match file.read(&mut chunk) {
            Ok(0) => return None,
            Ok(read) => read,
            Err(_) => return unreadable(),
        };
        let Some(left) = budget.checked_sub(read as u64) else {
            return Some(format!("{} (past the scan budget)", path.display()));
        };
        *budget = left;
        window.extend_from_slice(&chunk[..read]);
        let text = String::from_utf8_lossy(&window);
        if let Some(found) = needles.iter().find(|needle| text.contains(needle.as_str())) {
            return Some(found.clone());
        }
        // Keep the tail, so a path split across two chunks is still found.
        let keep = longest.saturating_sub(1).min(window.len());
        window.drain(..window.len() - keep);
    }
}

/// Finish removing staging directories an interrupted seeding left.
fn remove_abandoned_staging(profile: &Path) {
    let Ok(listing) = std::fs::read_dir(profile) else {
        return;
    };
    for entry in listing.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') && name.contains(STAGING_SUFFIX) {
            let _ = std::fs::remove_dir_all(entry.path());
        }
    }
}

/// Where symbolic links in a copied tree may point.
struct Links<'a> {
    /// The tree being copied.
    source: &'a Path,
    /// Where the copy will finally live.
    destination: &'a Path,
    donor: &'a Donor,
}

/// Copy a directory tree, keeping every file's modification time and leaving
/// the source's access times as they were.
fn copy_tree(source: &Path, destination: &Path, links: &Links) -> std::io::Result<()> {
    std::fs::create_dir(destination)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let from = entry.path();
        let to = destination.join(entry.file_name());
        let kind = entry.file_type()?;
        if kind.is_dir() {
            copy_tree(&from, &to, links)?;
        } else if kind.is_file() {
            copy_file(&from, &to, &entry.metadata()?)?;
        } else if kind.is_symlink() {
            copy_symlink(&from, &to, links)?;
        } else {
            return Err(std::io::Error::other(format!(
                "{} is neither a file, a directory, nor a link",
                from.display()
            )));
        }
    }
    Ok(())
}

/// Recreate a symbolic link, such as one a build script left in `OUT_DIR`.
///
/// A target with `..` in it is never copied: where `..` lands depends on
/// every link along the way, in this checkout as well as the donor, and no
/// reading of the name alone can say both agree. Without it the answer is
/// plain. A relative link can only lead deeper into the unit, whose shape the
/// copy reproduces, so it is kept. An absolute link into the unit points into
/// the copy instead. One to anywhere else in the donor checkout, including its
/// target directory through either spelling, would let this checkout read or
/// write the other's files, so the unit is not copied. Any other absolute
/// link is kept.
#[cfg(unix)]
fn copy_symlink(from: &Path, to: &Path, links: &Links) -> std::io::Result<()> {
    let target = std::fs::read_link(from)?;
    if target
        .components()
        .any(|component| component == std::path::Component::ParentDir)
    {
        return Err(std::io::Error::other(format!(
            "{} links through `..`",
            from.display()
        )));
    }
    if target.is_relative() {
        return std::os::unix::fs::symlink(target, to);
    }
    let inside = links
        .donor
        .respellings(links.source)
        .into_iter()
        .find_map(|source| target.strip_prefix(source).ok().map(Path::to_path_buf));
    let target = if let Some(inside) = inside {
        links.destination.join(inside)
    } else if links
        .donor
        .spellings()
        .iter()
        .any(|spelling| target.starts_with(spelling))
    {
        return Err(std::io::Error::other(format!(
            "{} links into the other checkout's target directory",
            from.display()
        )));
    } else {
        target
    };
    std::os::unix::fs::symlink(target, to)
}

/// Windows needs privileges to create a symbolic link, so a unit holding one
/// is left for the build to produce.
#[cfg(not(unix))]
fn copy_symlink(from: &Path, _to: &Path, _links: &Links) -> std::io::Result<()> {
    Err(std::io::Error::other(format!(
        "{} is a symbolic link",
        from.display()
    )))
}

fn copy_file(from: &Path, to: &Path, metadata: &std::fs::Metadata) -> std::io::Result<()> {
    if metadata.permissions().readonly() && std::fs::hard_link(from, to).is_ok() {
        return Ok(());
    }
    std::fs::copy(from, to)?;
    let mut times = std::fs::FileTimes::new().set_modified(metadata.modified()?);
    if let Ok(accessed) = metadata.accessed() {
        // The copy read the source. Putting its access time back keeps this
        // copy from counting as a build using the donor's unit.
        let _ = std::fs::File::open(from)
            .and_then(|file| file.set_times(std::fs::FileTimes::new().set_accessed(accessed)));
        times = times.set_accessed(accessed);
    }
    // `copy` carries the mode, so a copied read-only file needs a handle that
    // does not ask for write access; an owner may set times through one on
    // Unix. Windows needs write access to change a file's times.
    let file = if metadata.permissions().readonly() {
        std::fs::File::open(to)?
    } else {
        std::fs::OpenOptions::new().write(true).open(to)?
    };
    file.set_times(times)
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
#[path = "target_seed_tests.rs"]
mod tests;
