// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

//! Log file types.

use std::io::{Read, Result as IoResult, Seek, SeekFrom, Write};
use std::sync::Arc;

use fail::fail_point;
use log::warn;

use crate::env::{FileSystem, Handle, WriteExt};
use crate::metrics::*;
use crate::pipe_log::FileBlockHandle;
use crate::{Error, Result};

use super::format::LogFileFormat;

/// Maximum number of bytes to allocate ahead.
const FILE_ALLOCATE_SIZE: usize = 2 * 1024 * 1024;

/// Builds a file writer.
///
/// # Arguments
///
/// * `handle`: standard handle of a log file.
/// * `format`: format infos of the log file.
/// * `force_reset`: if true => rewrite the header of this file.
pub(super) fn build_file_writer<F: FileSystem>(
    system: &F,
    handle: Arc<F::Handle>,
    format: LogFileFormat,
    force_reset: bool,
) -> Result<LogFileWriter<F>> {
    let writer = system.new_writer(handle.clone())?;
    LogFileWriter::open(handle, writer, format, force_reset)
}

/// Append-only writer for log file. It also handles the file header write.
pub struct LogFileWriter<F: FileSystem> {
    handle: Arc<F::Handle>,
    writer: F::Writer,
    written: usize,
    capacity: usize,
}

// All APIs provided by `LogFileWriter` are fail-safe, i.e. caller can continue
// using the same "writer" even if the previous operation failed.
impl<F: FileSystem> LogFileWriter<F> {
    fn open(
        handle: Arc<F::Handle>,
        writer: F::Writer,
        format: LogFileFormat,
        force_reset: bool,
    ) -> Result<Self> {
        let file_size = handle.file_size()?;
        let mut f = Self {
            handle,
            writer,
            written: file_size,
            capacity: file_size,
        };
        // TODO: add tests for file_size in [header_len, max_encoded_len].
        if file_size < LogFileFormat::encoded_len(format.version) || force_reset {
            f.write_header(format)?;
        } else {
            f.writer.seek(SeekFrom::Start(file_size as u64))?;
        }
        Ok(f)
    }

    fn write_header(&mut self, format: LogFileFormat) -> IoResult<()> {
        self.writer.rewind()?;
        self.written = 0;
        let mut buf = Vec::with_capacity(LogFileFormat::encoded_len(format.version));
        format.encode(&mut buf).unwrap();
        self.write(&buf, 0)
    }

    pub fn close(&mut self) -> IoResult<()> {
        // Necessary to truncate extra zeros from fallocate().
        self.truncate()?;
        self.sync()
    }

    pub fn truncate(&mut self) -> IoResult<()> {
        if self.written < self.capacity {
            fail_point!("file_pipe_log::log_file_writer::skip_truncate", |_| {
                Ok(())
            });
            self.writer.truncate(self.written)?;
            self.capacity = self.written;
        }
        Ok(())
    }

    pub fn write(&mut self, buf: &[u8], target_size_hint: usize) -> IoResult<()> {
        let new_written = self.written + buf.len();
        if self.capacity < new_written {
            let _t = StopWatch::new(&*LOG_ALLOCATE_DURATION_HISTOGRAM);
            let alloc = std::cmp::min(
                FILE_ALLOCATE_SIZE,
                target_size_hint.saturating_sub(self.capacity),
            );
            let alloc = std::cmp::max(new_written - self.capacity, alloc);
            if let Err(e) = self.writer.allocate(self.capacity, alloc) {
                warn!("log file allocation failed: {e}");
            }
            self.capacity += alloc;
        }
        self.writer.write_all(buf).map_err(|e| {
            self.writer
                .seek(SeekFrom::Start(self.written as u64))
                .unwrap_or_else(|e| {
                    panic!("failed to reseek after write failure: {}", e);
                });
            e
        })?;
        self.written = new_written;
        Ok(())
    }

    pub fn sync(&mut self) -> IoResult<()> {
        let _t = StopWatch::new(&*LOG_SYNC_DURATION_HISTOGRAM);
        // Panic if sync fails, in case of data loss.
        self.handle.sync().unwrap();
        Ok(())
    }

    #[inline]
    pub fn offset(&self) -> usize {
        self.written
    }
}

/// Build a file reader.
pub(super) fn build_file_reader<F: FileSystem>(
    system: &F,
    handle: Arc<F::Handle>,
) -> Result<LogFileReader<F>> {
    let reader = system.new_reader(handle.clone())?;
    Ok(LogFileReader::open(handle, reader))
}

/// Random-access reader for log file.
pub struct LogFileReader<F: FileSystem> {
    handle: Arc<F::Handle>,
    reader: F::Reader,

    offset: u64,
}

impl<F: FileSystem> LogFileReader<F> {
    fn open(handle: Arc<F::Handle>, reader: F::Reader) -> LogFileReader<F> {
        Self {
            handle,
            reader,
            // Set to an invalid offset to force a reseek at first read.
            offset: u64::MAX,
        }
    }

    /// Function for reading the header of the log file, and return a
    /// `[LogFileFormat]`.
    ///
    /// Attention please, this function would move the `reader.offset`
    /// to `0`, that is, the beginning of the file, to parse the
    /// related `[LogFileFormat]`.
    pub fn parse_format(&mut self) -> Result<LogFileFormat> {
        let mut container = vec![0; LogFileFormat::max_encoded_len()];
        let size = self.read_to(0, &mut container)?;
        container.truncate(size);
        LogFileFormat::decode(&mut container.as_slice())
    }

    pub fn read(&mut self, handle: FileBlockHandle) -> Result<Vec<u8>> {
        let mut buf = vec![0; handle.len];
        let size = self.read_to(handle.offset, &mut buf)?;
        buf.truncate(size);
        Ok(buf)
    }

    /// Polls bytes from the file. Stops only when the buffer is filled or
    /// reaching the "end of file".
    pub fn read_to(&mut self, offset: u64, mut buf: &mut [u8]) -> Result<usize> {
        if offset != self.offset {
            self.reader.seek(SeekFrom::Start(offset))?;
            self.offset = offset;
        }
        loop {
            match self.reader.read(buf) {
                Ok(0) => break,
                Ok(n) => {
                    self.offset += n as u64;
                    buf = &mut buf[n..];
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => return Err(Error::Io(e)),
            }
        }
        Ok((self.offset - offset) as usize)
    }

    #[inline]
    pub fn file_size(&self) -> Result<usize> {
        Ok(self.handle.file_size()?)
    }
}
