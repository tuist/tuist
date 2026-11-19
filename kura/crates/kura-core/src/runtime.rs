//! The data directory's single-writer lock, taken before the store opens. The rest of the process
//! runtime state lives in the kura crate's `runtime` module.
use std::{
    fs::{File, OpenOptions},
    io::Write,
    path::Path,
};

#[cfg(test)]
use std::path::PathBuf;

const DATA_DIR_LOCK_FILE: &str = ".kura.writer.lock";

pub struct DataDirLock {
    _file: File,
    #[cfg(test)]
    path: PathBuf,
}

impl DataDirLock {
    pub fn acquire(data_dir: &Path) -> Result<Self, String> {
        let path = data_dir.join(DATA_DIR_LOCK_FILE);
        let mut file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .truncate(false)
            .open(&path)
            .map_err(|error| {
                format!(
                    "failed to open writer lock file {}: {error}",
                    path.display()
                )
            })?;

        try_lock_exclusive(&file).map_err(|error| {
            format!("failed to acquire writer lock {}: {error}", path.display())
        })?;

        file.set_len(0).map_err(|error| {
            format!(
                "failed to reset writer lock file {}: {error}",
                path.display()
            )
        })?;
        writeln!(file, "pid={}", std::process::id()).map_err(|error| {
            format!(
                "failed to write writer lock file {}: {error}",
                path.display()
            )
        })?;
        file.flush().map_err(|error| {
            format!(
                "failed to flush writer lock file {}: {error}",
                path.display()
            )
        })?;

        Ok(Self {
            _file: file,
            #[cfg(test)]
            path,
        })
    }

    #[cfg(test)]
    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(unix)]
fn try_lock_exclusive(file: &File) -> Result<(), std::io::Error> {
    use std::os::fd::AsRawFd;

    let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
    if result == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(not(unix))]
fn try_lock_exclusive(_file: &File) -> Result<(), std::io::Error> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use tempfile::tempdir;

    use super::*;

    #[test]
    fn data_dir_lock_rejects_second_owner() {
        let temp_dir = tempdir().expect("failed to create temp dir");
        let first = DataDirLock::acquire(temp_dir.path()).expect("first lock should succeed");
        let second = DataDirLock::acquire(temp_dir.path());
        assert!(second.is_err(), "second lock acquisition should fail");
        assert_eq!(
            first.path(),
            temp_dir.path().join(DATA_DIR_LOCK_FILE).as_path()
        );
    }
}
