//! The file-digest ledger a checkout carries from one session to the next.
//!
//! Within a session the cache agent remembers the digest of every file a shim
//! hashed, keyed by the strongest stable identity its filesystem supplies, so
//! a dependency rlib is read once however many crates link it. The
//! agent exits with the build, and without this file the next session would
//! start from nothing: the crate being edited would read every one of its
//! unchanged dependencies again before it could look anything up, a gigabyte
//! of rlibs for a large binary. Persisting the ledger beside the checkout's
//! other private state makes that first lookup as cheap as the second.
//!
//! Every entry is still checked against the disk before it answers, so a
//! stale file here costs one hash and nothing else; the ledger is a shortcut,
//! never a dependency, and every failure in this module degrades to an empty
//! one.

use eyre::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use tuist_cargo_cache_core::{CacheDigest, FileDigestScope, FileIdentity, RecordedFileDigest};

const LEDGER_FILE: &str = "file-digests.json";
/// Version 4 drops ledgers written before digests recorded within a timestamp
/// tick of the file's last write were withheld: those could hold a digest for
/// bytes a later same-tick write replaced.
const LEDGER_VERSION: u8 = 4;

/// Entries kept on disk. Far above what a workspace and its dependency
/// graph name, and a bound on a checkout that keeps renaming its outputs.
const MAX_PERSISTED_ENTRIES: usize = 256 * 1024;

/// Above this many entries, a save checks each one's file still exists and
/// drops the ones whose file is gone. Below it the check is skipped: it costs
/// a stat per entry on every build, and an entry for a vanished file is only
/// dead weight, never a wrong answer, since the identity it answers under
/// can no longer match anything. A checkout that keeps renaming its outputs
/// therefore grows to this size once, is swept back down, and repeats.
const SWEEP_ABOVE_ENTRIES: usize = 64 * 1024;

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Ledger {
    version: u8,
    entries: Vec<LedgerEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct LedgerEntry {
    scope: FileDigestScope,
    file: FileIdentity,
    digest: CacheDigest,
}

impl LedgerEntry {
    fn new(scope: FileDigestScope, record: RecordedFileDigest) -> Self {
        Self {
            scope,
            file: record.file,
            digest: record.digest,
        }
    }

    fn into_record(self) -> (FileDigestScope, RecordedFileDigest) {
        (
            self.scope,
            RecordedFileDigest {
                file: self.file,
                digest: self.digest,
            },
        )
    }
}

/// Where a checkout's ledger lives, inside its private state directory.
pub(crate) fn path(state_dir: &Path) -> PathBuf {
    state_dir.join(LEDGER_FILE)
}

/// What the ledger file looked like at one moment: enough to tell whether
/// another session has written it since.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Stamp {
    len: u64,
    modified: Option<std::time::SystemTime>,
}

/// The ledger file's current stamp, or nothing where there is no file.
pub(crate) fn stamp(state_dir: &Path) -> Option<Stamp> {
    let metadata = std::fs::metadata(path(state_dir)).ok()?;
    Some(Stamp {
        len: metadata.len(),
        modified: metadata.modified().ok(),
    })
}

/// The entries an earlier session left in `state_dir`, or nothing.
///
/// A ledger this version cannot read is no ledger: the cost is rehashing what
/// one session would have hashed anyway.
pub(crate) fn load(state_dir: &Path) -> Vec<(FileDigestScope, RecordedFileDigest)> {
    read(&path(state_dir))
        .map(|ledger| {
            ledger
                .entries
                .into_iter()
                .map(LedgerEntry::into_record)
                .collect()
        })
        .unwrap_or_default()
}

/// Leave `entries` in `state_dir` for the next session.
///
/// Merged with whatever is there now rather than replacing it: two sessions
/// in one checkout can run at once, and the one to finish second would
/// otherwise discard everything the first learned. Where both have an entry
/// for a path this session's wins, which is safe either way because an entry
/// answers only while its identity still matches the file. Entries whose file
/// is gone are dropped here, once per session, so a checkout that keeps
/// rebuilding its outputs under new names does not carry every old name
/// forever.
pub(crate) fn save(
    state_dir: &Path,
    entries: Vec<(FileDigestScope, RecordedFileDigest)>,
    loaded: Option<Stamp>,
) -> Result<usize> {
    save_sweeping_above(state_dir, entries, loaded, SWEEP_ABOVE_ENTRIES)
}

fn save_sweeping_above(
    state_dir: &Path,
    entries: Vec<(FileDigestScope, RecordedFileDigest)>,
    loaded: Option<Stamp>,
    sweep_above: usize,
) -> Result<usize> {
    let path = path(state_dir);
    // A session that seeded itself from this file, and finds it as it left
    // it, already holds everything in it: the merge is for the session that
    // was not alone.
    let unchanged = loaded.is_some() && loaded == stamp(state_dir);
    let merged: Vec<(FileDigestScope, RecordedFileDigest)> = if unchanged {
        // The agent's ledger is already keyed by scope and path, so there is
        // nothing to merge and no map to build.
        entries
    } else {
        let mut merged: BTreeMap<(FileDigestScope, PathBuf), RecordedFileDigest> = read(&path)
            .map(|ledger| {
                ledger
                    .entries
                    .into_iter()
                    .map(LedgerEntry::into_record)
                    .map(|(scope, record)| ((scope, record.file.path.clone()), record))
                    .collect()
            })
            .unwrap_or_default();
        for (scope, record) in entries {
            merged.insert((scope, record.file.path.clone()), record);
        }
        merged
            .into_iter()
            .map(|((scope, _), record)| (scope, record))
            .collect()
    };
    let sweep = merged.len() > sweep_above;
    let mut entries = merged
        .into_iter()
        .filter(|(_, record)| !sweep || record.file.path.is_file())
        .map(|(scope, record)| LedgerEntry::new(scope, record))
        .collect::<Vec<_>>();
    if entries.len() > MAX_PERSISTED_ENTRIES {
        // Nothing here says which entries matter more, so the newest write is
        // simply the one that has to fit: keep what sorts last, which for
        // outputs in one target directory is the most recently named.
        entries.drain(..entries.len() - MAX_PERSISTED_ENTRIES);
    }
    let count = entries.len();
    let ledger = Ledger {
        version: LEDGER_VERSION,
        entries,
    };
    let bytes = serde_json::to_vec(&ledger)?;
    crate::util::write_advisory(&path, &bytes)
        .wrap_err_with(|| format!("failed to write the file-digest ledger {}", path.display()))?;
    Ok(count)
}

fn read(path: &Path) -> Option<Ledger> {
    let bytes = std::fs::read(path).ok()?;
    let ledger = serde_json::from_slice::<Ledger>(&bytes).ok()?;
    (ledger.version == LEDGER_VERSION).then_some(ledger)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tuist_cargo_cache_core::{CacheDigest, FileIdentity, FileObjectIdentity};

    fn record(path: &Path) -> RecordedFileDigest {
        let metadata = std::fs::metadata(path).unwrap();
        RecordedFileDigest {
            file: FileIdentity::describe(path, &metadata).unwrap(),
            digest: CacheDigest::blake3_file(path).unwrap(),
        }
    }

    #[test]
    fn a_saved_ledger_loads_back_without_entries_for_vanished_files() {
        let state = tempfile::tempdir().unwrap();
        let files = tempfile::tempdir().unwrap();
        let kept = files.path().join("libkept.rlib");
        let gone = files.path().join("libgone.rlib");
        std::fs::write(&kept, b"kept").unwrap();
        std::fs::write(&gone, b"gone").unwrap();
        let entries = vec![
            (FileDigestScope::Content, record(&kept)),
            (FileDigestScope::CcInput, record(&gone)),
        ];
        std::fs::remove_file(&gone).unwrap();

        assert_eq!(
            save_sweeping_above(state.path(), entries.clone(), None, 0).unwrap(),
            1
        );
        assert_eq!(load(state.path()), vec![entries[0].clone()]);
    }

    #[test]
    fn saving_merges_with_what_another_session_left() {
        let state = tempfile::tempdir().unwrap();
        let files = tempfile::tempdir().unwrap();
        let theirs = files.path().join("libtheirs.rlib");
        let shared = files.path().join("libshared.rlib");
        std::fs::write(&theirs, b"theirs").unwrap();
        std::fs::write(&shared, b"shared").unwrap();
        let stale_shared = RecordedFileDigest {
            digest: CacheDigest::blake3(b"an older shared"),
            ..record(&shared)
        };
        save(
            state.path(),
            vec![
                (FileDigestScope::Content, record(&theirs)),
                (FileDigestScope::Content, stale_shared),
            ],
            None,
        )
        .unwrap();

        let ours = record(&shared);
        assert_eq!(
            save(
                state.path(),
                vec![(FileDigestScope::Content, ours.clone())],
                None
            )
            .unwrap(),
            2
        );
        let loaded = load(state.path());
        assert_eq!(loaded.len(), 2);
        assert!(loaded.contains(&(FileDigestScope::Content, record(&theirs))));
        assert!(loaded.contains(&(FileDigestScope::Content, ours)));
    }

    #[test]
    fn an_unreadable_or_foreign_ledger_is_an_empty_one() {
        let state = tempfile::tempdir().unwrap();
        assert!(load(state.path()).is_empty());
        std::fs::write(path(state.path()), b"not json").unwrap();
        assert!(load(state.path()).is_empty());
        std::fs::write(path(state.path()), br#"{"version":2,"entries":[]}"#).unwrap();
        assert!(load(state.path()).is_empty());
        std::fs::write(path(state.path()), br#"{"version":99,"entries":[]}"#).unwrap();
        assert!(load(state.path()).is_empty());
    }

    #[test]
    fn an_nfs_object_identity_survives_a_session_boundary() {
        let state = tempfile::tempdir().unwrap();
        let files = tempfile::tempdir().unwrap();
        let file = files.path().join("libnfs.rlib");
        std::fs::write(&file, b"nfs dependency").unwrap();
        let mut record = record(&file);
        record.file.changed = None;
        record.file.object = Some(FileObjectIdentity {
            device_major: 0,
            device_minor: 51,
            mount_id: 12,
            inode: 9001,
        });

        save(
            state.path(),
            vec![(FileDigestScope::Content, record.clone())],
            None,
        )
        .unwrap();

        assert_eq!(load(state.path()), vec![(FileDigestScope::Content, record)]);
    }
}
