//! Binary encoding for file-shaped action outputs.
//!
//! Raw file bytes alone cannot preserve Unix permission bits on restore.
//! This format stores the mode beside the contents while keeping directory
//! output encoding separate.

use std::path::Path;

use crate::{Error, Result};

pub(crate) const FILE_BLOB_MAGIC: &[u8] = b"once.file.v1\0";

pub(crate) fn capture_file_blob(path: &Path) -> std::io::Result<Vec<u8>> {
    let metadata = std::fs::metadata(path)?;
    #[cfg(unix)]
    let mode = {
        use std::os::unix::fs::PermissionsExt;
        metadata.permissions().mode() & 0o777
    };
    #[cfg(not(unix))]
    let mode = 0o644_u32;

    let content = std::fs::read(path)?;
    let mut out = Vec::with_capacity(FILE_BLOB_MAGIC.len() + 4 + content.len());
    out.extend_from_slice(FILE_BLOB_MAGIC);
    out.extend_from_slice(&mode.to_le_bytes());
    out.extend_from_slice(&content);
    Ok(out)
}

pub(crate) fn restore_file_blob(logical_path: &str, abs: &Path, bytes: &[u8]) -> Result<()> {
    let (mode, content) = decode_file_blob(logical_path, bytes)?;
    if let Some(parent) = abs.parent() {
        std::fs::create_dir_all(parent).map_err(|source| Error::RestoreOutput {
            path: logical_path.to_string(),
            source,
        })?;
    }
    std::fs::write(abs, content).map_err(|source| Error::RestoreOutput {
        path: logical_path.to_string(),
        source,
    })?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(abs, std::fs::Permissions::from_mode(mode)).map_err(|source| {
            Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            }
        })?;
    }
    #[cfg(not(unix))]
    {
        let mut permissions = std::fs::metadata(abs)
            .map_err(|source| Error::RestoreOutput {
                path: logical_path.to_string(),
                source,
            })?
            .permissions();
        permissions.set_readonly(mode & 0o222 == 0);
        std::fs::set_permissions(abs, permissions).map_err(|source| Error::RestoreOutput {
            path: logical_path.to_string(),
            source,
        })?;
    }
    Ok(())
}

fn decode_file_blob<'a>(logical_path: &str, bytes: &'a [u8]) -> Result<(u32, &'a [u8])> {
    if !bytes.starts_with(FILE_BLOB_MAGIC) {
        return Err(Error::InvalidFileOutput {
            path: logical_path.to_string(),
            message: "missing file blob magic".to_string(),
        });
    }
    let mode_bytes = bytes
        .get(FILE_BLOB_MAGIC.len()..FILE_BLOB_MAGIC.len() + 4)
        .ok_or_else(|| Error::InvalidFileOutput {
            path: logical_path.to_string(),
            message: "truncated file mode".to_string(),
        })?;
    let content = bytes.get(FILE_BLOB_MAGIC.len() + 4..).unwrap_or_default();
    let mut raw_mode = [0u8; 4];
    raw_mode.copy_from_slice(mode_bytes);
    Ok((u32::from_le_bytes(raw_mode) & 0o777, content))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_rejects_missing_magic() {
        let error = decode_file_blob("out/file", b"raw").unwrap_err();

        assert!(matches!(error, Error::InvalidFileOutput { .. }));
        assert!(error.to_string().contains("missing file blob magic"));
    }

    #[test]
    fn decode_rejects_truncated_mode() {
        let mut bytes = Vec::from(FILE_BLOB_MAGIC);
        bytes.extend_from_slice(&[1, 2, 3]);

        let error = decode_file_blob("out/file", &bytes).unwrap_err();

        assert!(matches!(error, Error::InvalidFileOutput { .. }));
        assert!(error.to_string().contains("truncated file mode"));
    }
}
