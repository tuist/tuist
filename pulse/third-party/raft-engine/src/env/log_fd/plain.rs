// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

//! A naive file handle implementation based on standard `File`. All I/O
//! operations need to synchronize under a `RwLock`.

use crate::env::{Handle, Permission};

use fail::fail_point;
use parking_lot::RwLock;

use std::fs::{File, OpenOptions};
use std::io::{Error, ErrorKind, Read, Result, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::Arc;

pub struct LogFd(Arc<RwLock<File>>);

impl LogFd {
    pub fn open<P: AsRef<Path>>(path: P, _: Permission) -> Result<Self> {
        OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .map(|x| Self(Arc::new(RwLock::new(x))))
    }

    pub fn create<P: AsRef<Path>>(path: P) -> Result<Self> {
        OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(path)
            .map(|x| Self(Arc::new(RwLock::new(x))))
    }

    pub fn read(&self, offset: usize, buf: &mut [u8]) -> Result<usize> {
        let mut file = self.0.write();
        let _ = file.seek(SeekFrom::Start(offset as u64))?;
        file.read(buf)
    }

    pub fn write(&self, offset: usize, content: &[u8]) -> Result<usize> {
        fail_point!("log_fd::write::no_space_err", |_| {
            Err(Error::new(ErrorKind::Other, "nospace"))
        });

        let mut file = self.0.write();
        let _ = file.seek(SeekFrom::Start(offset as u64))?;
        file.write(content)
    }

    pub fn truncate(&self, offset: usize) -> Result<()> {
        let file = self.0.write();
        file.set_len(offset as u64)
    }

    pub fn allocate(&self, _offset: usize, _size: usize) -> Result<()> {
        Ok(())
    }
}

impl Handle for LogFd {
    fn truncate(&self, offset: usize) -> Result<()> {
        self.truncate(offset)
    }

    fn file_size(&self) -> Result<usize> {
        fail_point!("log_fd::file_size::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        let file = self.0.read();
        file.metadata().map(|x| x.len() as usize)
    }

    fn sync(&self) -> Result<()> {
        fail_point!("log_fd::sync::err", |_| {
            Err(Error::new(ErrorKind::InvalidInput, "fp"))
        });

        let file = self.0.write();
        file.sync_all()
    }
}
