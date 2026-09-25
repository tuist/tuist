//! Binary encoding for directory-shaped action outputs.
//!
//! When an action's declared output is a directory (e.g. an `ebin/`
//! tree or a `.app` bundle), the runner serializes every file and
//! internal symlink into one CAS blob. Symlinks that point outside the
//! captured directory are materialized so the cached output is
//! standalone. Restoring is the inverse walk: recreate the directory
//! at the declared output path with each entry's contents, symlink
//! targets, and unix permission bits.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use crate::path::WorkspacePath;
use crate::{Error, OutputSymlinkMode, Result};

pub(crate) const DIRECTORY_BLOB_MAGIC: &[u8] = b"once.directory.v2\0";
const DIRECTORY_BLOB_V1_MAGIC: &[u8] = b"once.directory.v1\0";

#[derive(Clone, Copy)]
enum DirectoryEntryKind {
    File = 1,
    SymlinkFile = 2,
    SymlinkDir = 3,
}

impl DirectoryEntryKind {
    fn from_u8(raw: u8) -> Option<Self> {
        match raw {
            1 => Some(Self::File),
            2 => Some(Self::SymlinkFile),
            3 => Some(Self::SymlinkDir),
            _ => None,
        }
    }
}

struct DirectoryEntry {
    rel: String,
    kind: DirectoryEntryKind,
    mode: u32,
    bytes: Vec<u8>,
}

pub(crate) fn is_directory_blob(bytes: &[u8]) -> bool {
    bytes.starts_with(DIRECTORY_BLOB_MAGIC) || bytes.starts_with(DIRECTORY_BLOB_V1_MAGIC)
}

pub(crate) fn capture_directory_blob(
    root: &Path,
    symlink_mode: OutputSymlinkMode,
) -> std::io::Result<Vec<u8>> {
    let mut entries = Vec::new();
    let root_canonical = root.canonicalize()?;
    let mut materialized_dirs = HashSet::new();
    collect_directory_entries(
        &root_canonical,
        root,
        Path::new(""),
        &mut entries,
        &mut materialized_dirs,
        symlink_mode,
    )?;
    entries.sort_by(|a, b| a.rel.cmp(&b.rel));

    let mut out = Vec::from(DIRECTORY_BLOB_MAGIC);
    for entry in entries {
        let path_bytes = entry.rel.as_bytes();
        let path_len = u32::try_from(path_bytes.len()).map_err(|_| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "directory path is too long",
            )
        })?;
        let content_len = u64::try_from(entry.bytes.len()).map_err(|_| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "directory file is too large",
            )
        })?;
        out.push(entry.kind as u8);
        out.extend_from_slice(&path_len.to_le_bytes());
        out.extend_from_slice(&entry.mode.to_le_bytes());
        out.extend_from_slice(&content_len.to_le_bytes());
        out.extend_from_slice(path_bytes);
        out.extend_from_slice(&entry.bytes);
    }
    Ok(out)
}

fn collect_directory_entries(
    root_canonical: &Path,
    dir: &Path,
    logical_dir: &Path,
    entries: &mut Vec<DirectoryEntry>,
    materialized_dirs: &mut HashSet<PathBuf>,
    symlink_mode: OutputSymlinkMode,
) -> std::io::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        let logical_path = logical_dir.join(entry.file_name());
        let metadata = std::fs::symlink_metadata(&path)?;
        let file_type = metadata.file_type();
        if file_type.is_symlink() {
            collect_symlink_entry(
                root_canonical,
                &path,
                &logical_path,
                entries,
                materialized_dirs,
                symlink_mode,
            )?;
        } else if metadata.is_dir() {
            collect_directory_entries(
                root_canonical,
                &path,
                &logical_path,
                entries,
                materialized_dirs,
                symlink_mode,
            )?;
        } else if metadata.is_file() {
            entries.push(capture_file_entry(&logical_path, &path, &metadata)?);
        }
    }
    Ok(())
}

fn collect_symlink_entry(
    root_canonical: &Path,
    path: &Path,
    logical_path: &Path,
    entries: &mut Vec<DirectoryEntry>,
    materialized_dirs: &mut HashSet<PathBuf>,
    symlink_mode: OutputSymlinkMode,
) -> std::io::Result<()> {
    let target = std::fs::read_link(path)?;
    if symlink_mode == OutputSymlinkMode::Preserve {
        entries.push(capture_symlink_entry(path, logical_path, &target));
        return Ok(());
    }
    let resolved_target = resolve_symlink_target(path, &target);
    // Follow the link here so external targets can be classified and
    // materialized, while the directory walk itself never follows links.
    let Ok(target_metadata) = std::fs::metadata(path) else {
        entries.push(capture_symlink_entry(path, logical_path, &target));
        return Ok(());
    };
    let Ok(target_canonical) = resolved_target.canonicalize() else {
        entries.push(capture_symlink_entry(path, logical_path, &target));
        return Ok(());
    };
    if target_canonical.starts_with(root_canonical) {
        entries.push(capture_symlink_entry(path, logical_path, &target));
    } else if target_metadata.is_dir() {
        if !materialized_dirs.insert(target_canonical.clone()) {
            entries.push(capture_symlink_entry(path, logical_path, &target));
            return Ok(());
        }
        collect_directory_entries(
            root_canonical,
            &resolved_target,
            logical_path,
            entries,
            materialized_dirs,
            symlink_mode,
        )?;
        // Track only the active recursion stack. Reusing the same
        // external target from another link should materialize another
        // standalone subtree at that output path, not restore a link
        // back to the external store.
        materialized_dirs.remove(&target_canonical);
    } else if target_metadata.is_file() {
        entries.push(capture_file_entry(
            logical_path,
            &resolved_target,
            &target_metadata,
        )?);
    } else {
        entries.push(capture_symlink_entry(path, logical_path, &target));
    }
    Ok(())
}

fn capture_symlink_entry(path: &Path, logical_path: &Path, target: &Path) -> DirectoryEntry {
    DirectoryEntry {
        rel: logical_entry_path(logical_path),
        kind: symlink_kind(path),
        mode: 0o777,
        bytes: path_to_bytes(target),
    }
}

fn capture_file_entry(
    logical_path: &Path,
    path: &Path,
    metadata: &std::fs::Metadata,
) -> std::io::Result<DirectoryEntry> {
    Ok(DirectoryEntry {
        rel: logical_entry_path(logical_path),
        kind: DirectoryEntryKind::File,
        mode: file_mode(metadata),
        bytes: std::fs::read(path)?,
    })
}

fn logical_entry_path(path: &Path) -> String {
    path.to_string_lossy()
        .replace(std::path::MAIN_SEPARATOR, "/")
}

fn resolve_symlink_target(path: &Path, target: &Path) -> PathBuf {
    if target.is_absolute() {
        target.to_path_buf()
    } else {
        path.parent().unwrap_or_else(|| Path::new("")).join(target)
    }
}

fn file_mode(metadata: &std::fs::Metadata) -> u32 {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o777
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        0o644
    }
}

fn symlink_kind(path: &Path) -> DirectoryEntryKind {
    match std::fs::metadata(path) {
        Ok(metadata) if metadata.is_dir() => DirectoryEntryKind::SymlinkDir,
        _ => DirectoryEntryKind::SymlinkFile,
    }
}

fn path_to_bytes(path: &Path) -> Vec<u8> {
    path.to_string_lossy().as_bytes().to_vec()
}

pub(crate) fn restore_directory_blob(logical_path: &str, abs: &Path, bytes: &[u8]) -> Result<()> {
    let entries = decode_directory_blob(logical_path, bytes)?;
    if let Ok(metadata) = std::fs::symlink_metadata(abs) {
        if metadata.file_type().is_symlink() {
            std::fs::remove_file(abs).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        } else if metadata.is_dir() {
            std::fs::remove_dir_all(abs).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        } else {
            std::fs::remove_file(abs).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        }
    } else if abs.exists() {
        let metadata = std::fs::metadata(abs).map_err(|source| Error::RestoreOutput {
            path: logical_path.to_string(),
            source,
        })?;
        if metadata.is_dir() {
            std::fs::remove_dir_all(abs).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        } else {
            std::fs::remove_file(abs).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        }
    }
    std::fs::create_dir_all(abs).map_err(|source| Error::RestoreOutput {
        path: logical_path.to_string(),
        source,
    })?;
    for entry in entries {
        let rel_path = WorkspacePath::try_from(entry.rel.as_str()).map_err(|source| {
            Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: source.to_string(),
            }
        })?;
        if rel_path.as_str().is_empty() {
            return Err(Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "directory entry path is empty".to_string(),
            });
        }
        let dest = rel_path.resolve(abs);
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent).map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?;
        }
        match entry.kind {
            DirectoryEntryKind::File => {
                std::fs::write(&dest, entry.bytes).map_err(|source| Error::RestoreOutput {
                    path: logical_path.to_string(),
                    source,
                })?;
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    std::fs::set_permissions(
                        &dest,
                        std::fs::Permissions::from_mode(entry.mode.max(0o400)),
                    )
                    .map_err(|source| Error::RestoreOutput {
                        path: logical_path.to_string(),
                        source,
                    })?;
                }
            }
            DirectoryEntryKind::SymlinkFile | DirectoryEntryKind::SymlinkDir => {
                let target = symlink_target(logical_path, &entry.bytes)?;
                create_symlink(entry.kind, &target, &dest).map_err(|source| {
                    Error::RestoreOutput {
                        path: logical_path.to_string(),
                        source,
                    }
                })?;
            }
        }
    }
    Ok(())
}

fn decode_directory_blob(logical_path: &str, bytes: &[u8]) -> Result<Vec<DirectoryEntry>> {
    if bytes.starts_with(DIRECTORY_BLOB_V1_MAGIC) {
        return decode_v1_directory_blob(logical_path, bytes);
    }
    if !bytes.starts_with(DIRECTORY_BLOB_MAGIC) {
        return Err(Error::InvalidDirectoryOutput {
            path: logical_path.to_string(),
            message: "missing directory blob magic".to_string(),
        });
    }
    let mut pos = DIRECTORY_BLOB_MAGIC.len();
    let mut entries = Vec::new();
    while pos < bytes.len() {
        let kind = DirectoryEntryKind::from_u8(read_u8(logical_path, bytes, &mut pos)?)
            .ok_or_else(|| Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "unknown directory entry kind".to_string(),
            })?;
        let path_len = usize::try_from(read_u32(logical_path, bytes, &mut pos)?).map_err(|_| {
            Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "entry path length does not fit usize".to_string(),
            }
        })?;
        let mode = read_u32(logical_path, bytes, &mut pos)?;
        let content_len =
            usize::try_from(read_u64(logical_path, bytes, &mut pos)?).map_err(|_| {
                Error::InvalidDirectoryOutput {
                    path: logical_path.to_string(),
                    message: "entry content length does not fit usize".to_string(),
                }
            })?;
        if bytes.len().saturating_sub(pos) < path_len {
            return Err(Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "truncated entry path".to_string(),
            });
        }
        let path_bytes = &bytes[pos..pos + path_len];
        pos += path_len;
        let path = std::str::from_utf8(path_bytes)
            .map_err(|e| Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: format!("entry path is not utf-8: {e}"),
            })?
            .to_string();
        if bytes.len().saturating_sub(pos) < content_len {
            return Err(Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "truncated entry content".to_string(),
            });
        }
        let bytes = bytes[pos..pos + content_len].to_vec();
        pos += content_len;
        entries.push(DirectoryEntry {
            rel: path,
            kind,
            mode,
            bytes,
        });
    }
    Ok(entries)
}

fn decode_v1_directory_blob(logical_path: &str, bytes: &[u8]) -> Result<Vec<DirectoryEntry>> {
    let mut pos = DIRECTORY_BLOB_V1_MAGIC.len();
    let mut entries = Vec::new();
    while pos < bytes.len() {
        let path_len = usize::try_from(read_u32(logical_path, bytes, &mut pos)?).map_err(|_| {
            Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "entry path length does not fit usize".to_string(),
            }
        })?;
        let mode = read_u32(logical_path, bytes, &mut pos)?;
        let content_len =
            usize::try_from(read_u64(logical_path, bytes, &mut pos)?).map_err(|_| {
                Error::InvalidDirectoryOutput {
                    path: logical_path.to_string(),
                    message: "entry content length does not fit usize".to_string(),
                }
            })?;
        if bytes.len().saturating_sub(pos) < path_len {
            return Err(Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "truncated entry path".to_string(),
            });
        }
        let path_bytes = &bytes[pos..pos + path_len];
        pos += path_len;
        let path = std::str::from_utf8(path_bytes)
            .map_err(|e| Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: format!("entry path is not utf-8: {e}"),
            })?
            .to_string();
        if bytes.len().saturating_sub(pos) < content_len {
            return Err(Error::InvalidDirectoryOutput {
                path: logical_path.to_string(),
                message: "truncated entry content".to_string(),
            });
        }
        let bytes = bytes[pos..pos + content_len].to_vec();
        pos += content_len;
        entries.push(DirectoryEntry {
            rel: path,
            kind: DirectoryEntryKind::File,
            mode,
            bytes,
        });
    }
    Ok(entries)
}

fn symlink_target(logical_path: &str, bytes: &[u8]) -> Result<PathBuf> {
    let target = std::str::from_utf8(bytes).map_err(|e| Error::InvalidDirectoryOutput {
        path: logical_path.to_string(),
        message: format!("symlink target is not utf-8: {e}"),
    })?;
    Ok(PathBuf::from(target))
}

#[cfg(unix)]
fn create_symlink(_: DirectoryEntryKind, target: &Path, link: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(target, link)
}

#[cfg(windows)]
fn create_symlink(kind: DirectoryEntryKind, target: &Path, link: &Path) -> std::io::Result<()> {
    match kind {
        DirectoryEntryKind::SymlinkDir => std::os::windows::fs::symlink_dir(target, link),
        DirectoryEntryKind::File | DirectoryEntryKind::SymlinkFile => {
            std::os::windows::fs::symlink_file(target, link)
        }
    }
}

#[cfg(not(any(unix, windows)))]
fn create_symlink(_: DirectoryEntryKind, target: &Path, link: &Path) -> std::io::Result<()> {
    std::fs::write(link, target.to_string_lossy().as_bytes())
}

fn read_u8(logical_path: &str, bytes: &[u8], pos: &mut usize) -> Result<u8> {
    let Some(value) = bytes.get(*pos).copied() else {
        return Err(Error::InvalidDirectoryOutput {
            path: logical_path.to_string(),
            message: "truncated u8".to_string(),
        });
    };
    *pos += 1;
    Ok(value)
}

fn read_u32(logical_path: &str, bytes: &[u8], pos: &mut usize) -> Result<u32> {
    if bytes.len().saturating_sub(*pos) < 4 {
        return Err(Error::InvalidDirectoryOutput {
            path: logical_path.to_string(),
            message: "truncated u32".to_string(),
        });
    }
    let mut raw = [0u8; 4];
    raw.copy_from_slice(&bytes[*pos..*pos + 4]);
    *pos += 4;
    Ok(u32::from_le_bytes(raw))
}

fn read_u64(logical_path: &str, bytes: &[u8], pos: &mut usize) -> Result<u64> {
    if bytes.len().saturating_sub(*pos) < 8 {
        return Err(Error::InvalidDirectoryOutput {
            path: logical_path.to_string(),
            message: "truncated u64".to_string(),
        });
    }
    let mut raw = [0u8; 8];
    raw.copy_from_slice(&bytes[*pos..*pos + 8]);
    *pos += 8;
    Ok(u64::from_le_bytes(raw))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[cfg(unix)]
    #[test]
    fn directory_blob_restores_file_permissions() {
        use std::os::unix::fs::PermissionsExt;

        let tmp = TempDir::new().unwrap();
        let source = tmp.path().join("source");
        let restored = tmp.path().join("restored");
        std::fs::create_dir(&source).unwrap();
        std::fs::write(source.join("tool"), b"run").unwrap();
        std::fs::set_permissions(source.join("tool"), std::fs::Permissions::from_mode(0o750))
            .unwrap();

        let blob = capture_directory_blob(&source, OutputSymlinkMode::MaterializeExternal).unwrap();
        restore_directory_blob("bundle", &restored, &blob).unwrap();

        let mode = std::fs::metadata(restored.join("tool"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o750);
    }

    #[cfg(unix)]
    #[test]
    fn directory_blob_preserves_internal_symlinked_file() {
        use std::os::unix::fs::symlink;

        let tmp = TempDir::new().unwrap();
        let source = tmp.path().join("source");
        let restored = tmp.path().join("restored");
        std::fs::create_dir(&source).unwrap();
        std::fs::write(source.join("real.txt"), b"internal").unwrap();
        symlink("real.txt", source.join("linked.txt")).unwrap();

        let blob = capture_directory_blob(&source, OutputSymlinkMode::MaterializeExternal).unwrap();
        restore_directory_blob("bundle", &restored, &blob).unwrap();

        let restored_link = restored.join("linked.txt");
        let metadata = std::fs::symlink_metadata(&restored_link).unwrap();
        assert!(metadata.file_type().is_symlink());
        assert_eq!(
            std::fs::read_link(&restored_link).unwrap(),
            PathBuf::from("real.txt")
        );
        assert_eq!(std::fs::read(restored_link).unwrap(), b"internal");
    }

    #[cfg(unix)]
    #[test]
    fn directory_blob_materializes_external_symlinked_file() {
        use std::os::unix::fs::symlink;

        let tmp = TempDir::new().unwrap();
        let source = tmp.path().join("source");
        let restored = tmp.path().join("restored");
        let external = tmp.path().join("external.txt");
        std::fs::create_dir(&source).unwrap();
        std::fs::write(&external, b"external").unwrap();
        symlink(&external, source.join("linked.txt")).unwrap();

        let blob = capture_directory_blob(&source, OutputSymlinkMode::MaterializeExternal).unwrap();
        std::fs::remove_file(&external).unwrap();
        restore_directory_blob("bundle", &restored, &blob).unwrap();

        let restored_link = restored.join("linked.txt");
        let metadata = std::fs::symlink_metadata(&restored_link).unwrap();
        assert!(!metadata.file_type().is_symlink());
        assert!(metadata.is_file());
        assert_eq!(std::fs::read(restored_link).unwrap(), b"external");
    }

    #[cfg(unix)]
    #[test]
    fn directory_blob_preserves_external_symlinked_file_when_configured() {
        use std::os::unix::fs::symlink;

        let tmp = TempDir::new().unwrap();
        let source = tmp.path().join("source");
        let restored = tmp.path().join("restored");
        let external = tmp.path().join("external.txt");
        std::fs::create_dir(&source).unwrap();
        std::fs::write(&external, b"external").unwrap();
        symlink(&external, source.join("linked.txt")).unwrap();

        let blob = capture_directory_blob(&source, OutputSymlinkMode::Preserve).unwrap();
        std::fs::remove_file(&external).unwrap();
        restore_directory_blob("bundle", &restored, &blob).unwrap();

        let restored_link = restored.join("linked.txt");
        let metadata = std::fs::symlink_metadata(&restored_link).unwrap();
        assert!(metadata.file_type().is_symlink());
        assert_eq!(std::fs::read_link(restored_link).unwrap(), external);
    }

    #[cfg(unix)]
    #[test]
    fn directory_blob_materializes_external_symlinked_directory() {
        use std::os::unix::fs::symlink;

        let tmp = TempDir::new().unwrap();
        let source = tmp.path().join("source");
        let restored = tmp.path().join("restored");
        let external = tmp.path().join("external-pkg");
        std::fs::create_dir(&source).unwrap();
        std::fs::create_dir(&external).unwrap();
        std::fs::write(external.join("index.js"), b"pkg").unwrap();
        symlink("../external-pkg", source.join("linked-pkg")).unwrap();

        let blob = capture_directory_blob(&source, OutputSymlinkMode::MaterializeExternal).unwrap();
        std::fs::remove_dir_all(&external).unwrap();
        restore_directory_blob("bundle", &restored, &blob).unwrap();

        let restored_link = restored.join("linked-pkg");
        let metadata = std::fs::symlink_metadata(&restored_link).unwrap();
        assert!(!metadata.file_type().is_symlink());
        assert!(metadata.is_dir());
        assert_eq!(
            std::fs::read(restored_link.join("index.js")).unwrap(),
            b"pkg"
        );
    }

    #[test]
    fn legacy_v1_directory_blob_still_restores() {
        let tmp = TempDir::new().unwrap();
        let restored = tmp.path().join("restored");
        let mut blob = Vec::from(DIRECTORY_BLOB_V1_MAGIC);
        let path = b"nested/file.txt";
        let content = b"legacy";
        let path_len = u32::try_from(path.len()).unwrap();
        blob.extend_from_slice(&path_len.to_le_bytes());
        blob.extend_from_slice(&0o644_u32.to_le_bytes());
        blob.extend_from_slice(&(content.len() as u64).to_le_bytes());
        blob.extend_from_slice(path);
        blob.extend_from_slice(content);

        restore_directory_blob("bundle", &restored, &blob).unwrap();

        assert_eq!(
            std::fs::read(restored.join("nested/file.txt")).unwrap(),
            content
        );
    }
}
