// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use crate::env::{Handle, Permission};

use fail::fail_point;
use log::error;

use std::io::Result as IoResult;
use std::os::unix::io::RawFd;

use nix::errno::Errno;
use nix::fcntl::{self, OFlag};
use nix::sys::stat::Mode;
use nix::sys::uio::{pread, pwrite};
use nix::unistd::{close, ftruncate, lseek, Whence};
use nix::NixPath;

fn from_nix_error(e: nix::Error, custom: &'static str) -> std::io::Error {
    let kind = std::io::Error::from(e).kind();
    std::io::Error::new(kind, custom)
}

impl From<Permission> for OFlag {
    fn from(value: Permission) -> OFlag {
        match value {
            Permission::ReadOnly => OFlag::O_RDONLY,
            Permission::ReadWrite => OFlag::O_RDWR,
        }
    }
}

/// A RAII-style low-level file. Errors occurred during automatic resource
/// release are logged and ignored.
///
/// A [`LogFd`] is essentially a thin wrapper around [`RawFd`]. It's only
/// supported on *Unix*, and primarily optimized for *Linux*.
///
/// All [`LogFd`] instances are opened with read and write permission.
pub struct LogFd(RawFd);

impl LogFd {
    /// Opens a file with the given `path`.
    pub fn open<P: ?Sized + NixPath>(path: &P, perm: Permission) -> IoResult<Self> {
        // Permission 644
        let mode = Mode::S_IRUSR | Mode::S_IWUSR | Mode::S_IRGRP | Mode::S_IROTH;
        fail_point!("log_fd::open::fadvise_dontneed", |_| {
            let fd =
                LogFd(fcntl::open(path, perm.into(), mode).map_err(|e| from_nix_error(e, "open"))?);
            #[cfg(target_os = "linux")]
            unsafe {
                extern crate libc;
                libc::posix_fadvise64(fd.0, 0, fd.file_size()? as i64, libc::POSIX_FADV_DONTNEED);
            }
            Ok(fd)
        });
        Ok(LogFd(
            fcntl::open(path, perm.into(), mode).map_err(|e| from_nix_error(e, "open"))?,
        ))
    }

    /// Opens a file with the given `path`. The specified file will be created
    /// first if not exists.
    pub fn create<P: ?Sized + NixPath>(path: &P) -> IoResult<Self> {
        let flags = OFlag::O_RDWR | OFlag::O_CREAT;
        // Permission 644
        let mode = Mode::S_IRUSR | Mode::S_IWUSR | Mode::S_IRGRP | Mode::S_IROTH;
        let fd = fcntl::open(path, flags, mode).map_err(|e| from_nix_error(e, "open"))?;
        Ok(LogFd(fd))
    }

    /// Closes the file.
    pub fn close(&self) -> IoResult<()> {
        fail_point!("log_fd::close::err", |_| {
            Err(from_nix_error(nix::Error::EINVAL, "fp"))
        });
        close(self.0).map_err(|e| from_nix_error(e, "close"))
    }

    /// Reads some bytes starting at `offset` from this file into the specified
    /// buffer. Returns how many bytes were read.
    pub fn read(&self, mut offset: usize, buf: &mut [u8]) -> IoResult<usize> {
        let mut readed = 0;
        while readed < buf.len() {
            let bytes = match pread(self.0, &mut buf[readed..], offset as i64) {
                Ok(bytes) => bytes,
                Err(Errno::EINTR) => continue,
                Err(e) => return Err(from_nix_error(e, "pread")),
            };
            // EOF
            if bytes == 0 {
                break;
            }
            readed += bytes;
            offset += bytes;
        }
        Ok(readed)
    }

    /// Writes some bytes to this file starting at `offset`. Returns how many
    /// bytes were written.
    pub fn write(&self, mut offset: usize, content: &[u8]) -> IoResult<usize> {
        fail_point!("log_fd::write::no_space_err", |_| {
            Err(from_nix_error(nix::Error::ENOSPC, "nospace"))
        });
        let mut written = 0;
        while written < content.len() {
            let bytes = match pwrite(self.0, &content[written..], offset as i64) {
                Ok(bytes) => bytes,
                Err(Errno::EINTR) => continue,
                Err(e) if e == Errno::ENOSPC => return Err(from_nix_error(e, "nospace")),
                Err(e) => return Err(from_nix_error(e, "pwrite")),
            };
            if bytes == 0 {
                break;
            }
            written += bytes;
            offset += bytes;
        }
        Ok(written)
    }

    /// Truncates all data after `offset`.
    pub fn truncate(&self, offset: usize) -> IoResult<()> {
        ftruncate(self.0, offset as i64).map_err(|e| from_nix_error(e, "ftruncate"))
    }

    /// Attempts to allocate space for `size` bytes starting at `offset`.
    #[allow(unused_variables)]
    pub fn allocate(&self, offset: usize, size: usize) -> IoResult<()> {
        #[cfg(target_os = "linux")]
        {
            if let Err(e) = fcntl::fallocate(
                self.0,
                fcntl::FallocateFlags::empty(),
                offset as i64,
                size as i64,
            ) {
                if e != nix::Error::EOPNOTSUPP {
                    return Err(from_nix_error(e, "fallocate"));
                }
            }
        }
        Ok(())
    }
}

impl Handle for LogFd {
    #[inline]
    fn truncate(&self, offset: usize) -> IoResult<()> {
        self.truncate(offset)
    }

    #[inline]
    fn file_size(&self) -> IoResult<usize> {
        fail_point!("log_fd::file_size::err", |_| {
            Err(from_nix_error(nix::Error::EINVAL, "fp"))
        });
        lseek(self.0, 0, Whence::SeekEnd)
            .map(|n| n as usize)
            .map_err(|e| from_nix_error(e, "lseek"))
    }

    #[inline]
    fn sync(&self) -> IoResult<()> {
        fail_point!("log_fd::sync::err", |_| {
            Err(from_nix_error(nix::Error::EINVAL, "fp"))
        });
        #[cfg(target_os = "linux")]
        {
            nix::unistd::fdatasync(self.0).map_err(|e| from_nix_error(e, "fdatasync"))
        }
        #[cfg(not(target_os = "linux"))]
        {
            nix::unistd::fsync(self.0).map_err(|e| from_nix_error(e, "fsync"))
        }
    }
}

impl Drop for LogFd {
    fn drop(&mut self) {
        if let Err(e) = self.close() {
            error!("error while closing file: {e}");
        }
    }
}
