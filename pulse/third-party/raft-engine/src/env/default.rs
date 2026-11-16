// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

#[cfg(feature = "failpoints")]
use std::io::{Error, ErrorKind};
use std::io::{Read, Result as IoResult, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::Arc;

use fail::fail_point;

use crate::env::log_fd::LogFd;
use crate::env::{FileSystem, Handle, Permission, WriteExt};

/// A low-level file adapted for standard interfaces including [`Seek`],
/// [`Write`] and [`Read`].
pub struct LogFile {
    inner: Arc<LogFd>,
    offset: usize,
}

impl LogFile {
    /// Creates a new [`LogFile`] from a shared [`LogFd`].
    pub fn new(fd: Arc<LogFd>) -> Self {
        Self {
            inner: fd,
            offset: 0,
        }
    }
}

impl Write for LogFile {
    fn write(&mut self, buf: &[u8]) -> IoResult<usize> {
        fail_point!("log_file::write::zero", |_| { Ok(0) });

        let len = self.inner.write(self.offset, buf)?;

        fail_point!("log_file::write::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        self.offset += len;
        Ok(len)
    }

    fn flush(&mut self) -> IoResult<()> {
        Ok(())
    }
}

impl Read for LogFile {
    fn read(&mut self, buf: &mut [u8]) -> IoResult<usize> {
        fail_point!("log_file::read::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        let len = self.inner.read(self.offset, buf)?;
        self.offset += len;
        Ok(len)
    }
}

impl Seek for LogFile {
    fn seek(&mut self, pos: SeekFrom) -> IoResult<u64> {
        fail_point!("log_file::seek::err", |_| {
            Err(std::io::Error::new(std::io::ErrorKind::Other, "fp"))
        });
        match pos {
            SeekFrom::Start(offset) => self.offset = offset as usize,
            SeekFrom::Current(i) => self.offset = (self.offset as i64 + i) as usize,
            SeekFrom::End(i) => self.offset = (self.inner.file_size()? as i64 + i) as usize,
        }
        Ok(self.offset as u64)
    }
}

impl WriteExt for LogFile {
    fn truncate(&mut self, offset: usize) -> IoResult<()> {
        fail_point!("log_file::truncate::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        self.inner.truncate(offset)?;
        self.offset = offset;
        Ok(())
    }

    fn allocate(&mut self, offset: usize, size: usize) -> IoResult<()> {
        fail_point!("log_file::allocate::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        self.inner.allocate(offset, size)
    }
}

pub struct DefaultFileSystem;

impl FileSystem for DefaultFileSystem {
    type Handle = LogFd;
    type Reader = LogFile;
    type Writer = LogFile;

    fn create<P: AsRef<Path>>(&self, path: P) -> IoResult<Self::Handle> {
        fail_point!("default_fs::create::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        LogFd::create(path.as_ref())
    }

    fn open<P: AsRef<Path>>(&self, path: P, perm: Permission) -> IoResult<Self::Handle> {
        fail_point!("default_fs::open::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        LogFd::open(path.as_ref(), perm)
    }

    fn delete<P: AsRef<Path>>(&self, path: P) -> IoResult<()> {
        fail_point!("default_fs::delete_skipped", |_| { Ok(()) });
        std::fs::remove_file(path)
    }

    fn rename<P: AsRef<Path>>(&self, src_path: P, dst_path: P) -> IoResult<()> {
        std::fs::rename(src_path, dst_path)
    }

    fn new_reader(&self, handle: Arc<Self::Handle>) -> IoResult<Self::Reader> {
        Ok(LogFile::new(handle))
    }

    fn new_writer(&self, handle: Arc<Self::Handle>) -> IoResult<Self::Writer> {
        Ok(LogFile::new(handle))
    }
}
