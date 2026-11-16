// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

//! Representations of objects in filesystem.

use std::io::BufRead;
use std::path::{Path, PathBuf};

use num_traits::{FromPrimitive, ToPrimitive};

use crate::codec::{self, NumberEncoder};
use crate::pipe_log::{FileId, FileSeq, LogQueue, Version};
use crate::{Error, Result};

/// Width to format log sequence number.
const LOG_SEQ_WIDTH: usize = 16;
/// Name suffix for Append queue files.
const LOG_APPEND_SUFFIX: &str = ".raftlog";
/// Name suffix for Rewrite queue files.
const LOG_REWRITE_SUFFIX: &str = ".rewrite";
/// Name suffix for reserved log files that contain only zeros.
const LOG_APPEND_RESERVED_SUFFIX: &str = ".raftlog.reserved";
/// File header.
const LOG_FILE_MAGIC_HEADER: &[u8] = b"RAFT-LOG-FILE-HEADER-9986AB3E47F320B394C8E84916EB0ED5";

/// Checks whether the given `buf` is padded with zeros.
///
/// To simplify the checking strategy, we just check the first
/// and last byte in the `buf`.
///
/// In most common cases, the paddings will be filled with `0`,
/// and several corner cases, where there exists corrupted blocks
/// in the disk, might pass through this rule, but will failed in
/// followed processing. So, we can just keep it simplistic.
#[inline]
pub(crate) fn is_zero_padded(buf: &[u8]) -> bool {
    buf.is_empty() || (buf[0] == 0 && buf[buf.len() - 1] == 0)
}

/// `FileNameExt` offers file name formatting extensions to [`FileId`].
pub trait FileNameExt: Sized {
    fn parse_file_name(file_name: &str) -> Option<Self>;

    fn build_file_name(&self) -> String;

    fn build_file_path<P: AsRef<Path>>(&self, dir: P) -> PathBuf {
        let mut path = PathBuf::from(dir.as_ref());
        path.push(self.build_file_name());
        path
    }
}

impl FileNameExt for FileId {
    fn parse_file_name(file_name: &str) -> Option<FileId> {
        if file_name.len() > LOG_SEQ_WIDTH {
            if let Ok(seq) = file_name[..LOG_SEQ_WIDTH].parse::<u64>() {
                if file_name.ends_with(LOG_APPEND_SUFFIX) {
                    return Some(FileId {
                        queue: LogQueue::Append,
                        seq,
                    });
                } else if file_name.ends_with(LOG_REWRITE_SUFFIX) {
                    return Some(FileId {
                        queue: LogQueue::Rewrite,
                        seq,
                    });
                }
            }
        }
        None
    }

    fn build_file_name(&self) -> String {
        let width = LOG_SEQ_WIDTH;
        match self.queue {
            LogQueue::Append => format!("{:0width$}{LOG_APPEND_SUFFIX}", self.seq,),
            LogQueue::Rewrite => format!("{:0width$}{LOG_REWRITE_SUFFIX}", self.seq,),
        }
    }
}

pub fn parse_reserved_file_name(file_name: &str) -> Option<FileSeq> {
    if file_name.len() > LOG_SEQ_WIDTH {
        if let Ok(seq) = file_name[..LOG_SEQ_WIDTH].parse::<u64>() {
            if file_name.ends_with(LOG_APPEND_RESERVED_SUFFIX) {
                // As reserved files are only used for LogQueue::Append,
                // we just return the related FileSeq of it.
                return Some(seq);
            }
        }
    }
    None
}

pub fn build_reserved_file_name(seq: FileSeq) -> String {
    let width = LOG_SEQ_WIDTH;
    format!("{seq:0width$}{LOG_APPEND_RESERVED_SUFFIX}",)
}

/// Path to the lock file under `dir`.
pub(super) fn lock_file_path<P: AsRef<Path>>(dir: P) -> PathBuf {
    let mut path = PathBuf::from(dir.as_ref());
    path.push("LOCK");
    path
}

/// Log file format. It will be encoded to file header.
#[derive(Copy, Clone, Debug, Eq, PartialEq, Default)]
pub struct LogFileFormat {
    pub version: Version,
    /// 0 stands for no alignment.
    pub alignment: u64,
}

impl LogFileFormat {
    pub fn new(version: Version, alignment: u64) -> Self {
        Self { version, alignment }
    }

    /// Length of header written on storage.
    const fn header_len() -> usize {
        LOG_FILE_MAGIC_HEADER.len() + std::mem::size_of::<Version>()
    }

    const fn payload_len(version: Version) -> usize {
        match version {
            Version::V1 => 0,
            Version::V2 => std::mem::size_of::<u64>(),
        }
    }

    pub const fn max_encoded_len() -> usize {
        Self::header_len() + Self::payload_len(Version::V2)
    }

    /// Length of whole `LogFileFormat` written on storage.
    pub fn encoded_len(version: Version) -> usize {
        Self::header_len() + Self::payload_len(version)
    }

    /// Decodes a slice of bytes into a `LogFileFormat`.
    pub fn decode(buf: &mut &[u8]) -> Result<LogFileFormat> {
        let mut format = LogFileFormat::default();
        if !buf.starts_with(LOG_FILE_MAGIC_HEADER) {
            return Err(Error::Corruption(
                "log file magic header mismatch".to_owned(),
            ));
        }
        buf.consume(LOG_FILE_MAGIC_HEADER.len());

        let version_u64 = codec::decode_u64(buf)?;
        if let Some(version) = Version::from_u64(version_u64) {
            format.version = version;
        } else {
            return Err(Error::Corruption(format!(
                "unrecognized log file version: {version_u64}",
            )));
        }

        let payload_len = Self::payload_len(format.version);
        if buf.len() < payload_len {
            return Err(Error::Corruption("missing header payload".to_owned()));
        } else if payload_len > 0 {
            format.alignment = codec::decode_u64(buf)?;
        }

        Ok(format)
    }

    /// Encodes this header and appends the bytes to the provided buffer.
    pub fn encode(&self, buf: &mut Vec<u8>) -> Result<()> {
        buf.extend_from_slice(LOG_FILE_MAGIC_HEADER);
        buf.encode_u64(self.version.to_u64().unwrap())?;
        if Self::payload_len(self.version) > 0 {
            buf.encode_u64(self.alignment)?;
        } else {
            assert_eq!(self.alignment, 0);
        }
        #[cfg(feature = "failpoints")]
        {
            // Set header corrupted.
            let corrupted = || {
                fail::fail_point!("log_file_header::corrupted", |_| true);
                false
            };
            // Set abnormal DataLayout.
            let too_large = || {
                fail::fail_point!("log_file_header::too_large", |_| true);
                false
            };
            // Set corrupted DataLayout for `payload`.
            let too_small = || {
                fail::fail_point!("log_file_header::too_small", |_| true);
                false
            };
            if corrupted() {
                buf[0] += 1;
            }
            assert!(!(too_large() && too_small()));
            if too_large() {
                buf.encode_u64(0_u64)?;
            }
            if too_small() {
                buf.pop();
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pipe_log::LogFileContext;
    use crate::test_util::catch_unwind_silent;

    #[test]
    fn test_check_paddings_is_valid() {
        // normal buffer
        let mut buf = vec![0; 128];
        // len < 8
        assert!(is_zero_padded(&buf[0..6]));
        // len == 8
        assert!(is_zero_padded(&buf[120..]));
        // len > 8
        assert!(is_zero_padded(&buf));

        // abnormal buffer
        buf[127] = 3_u8;
        assert!(is_zero_padded(&buf[0..110]));
        assert!(is_zero_padded(&buf[120..125]));
        assert!(!is_zero_padded(&buf[124..128]));
        assert!(!is_zero_padded(&buf[120..]));
        assert!(!is_zero_padded(&buf));
    }

    #[test]
    fn test_file_name() {
        let file_name: &str = "0000000000000123.raftlog";
        let file_id = FileId {
            queue: LogQueue::Append,
            seq: 123,
        };
        assert_eq!(FileId::parse_file_name(file_name).unwrap(), file_id,);
        assert_eq!(file_id.build_file_name(), file_name);

        let file_name: &str = "0000000000000123.rewrite";
        let file_id = FileId {
            queue: LogQueue::Rewrite,
            seq: 123,
        };
        assert_eq!(FileId::parse_file_name(file_name).unwrap(), file_id,);
        assert_eq!(file_id.build_file_name(), file_name);

        let invalid_cases = vec!["0000000000000123.log", "123.rewrite"];
        for case in invalid_cases {
            assert!(FileId::parse_file_name(case).is_none());
        }
    }

    #[test]
    fn test_version() {
        let version = Version::default();
        assert_eq!(Version::V1.to_u64().unwrap(), version.to_u64().unwrap());
        let version2 = Version::from_u64(1).unwrap();
        assert_eq!(version, version2);
    }

    #[test]
    fn test_encoding_decoding_file_format() {
        fn enc_dec_file_format(file_format: LogFileFormat) -> Result<LogFileFormat> {
            let mut buf = Vec::with_capacity(
                LogFileFormat::header_len() + LogFileFormat::payload_len(file_format.version),
            );
            file_format.encode(&mut buf).unwrap();
            LogFileFormat::decode(&mut &buf[..])
        }
        // header with aligned-sized data_layout
        {
            let mut buf = Vec::with_capacity(LogFileFormat::header_len());
            let version = Version::V2;
            let alignment = 4096;
            buf.extend_from_slice(LOG_FILE_MAGIC_HEADER);
            buf.encode_u64(version.to_u64().unwrap()).unwrap();
            buf.encode_u64(alignment).unwrap();
            assert_eq!(
                LogFileFormat::decode(&mut &buf[..]).unwrap(),
                LogFileFormat::new(version, alignment)
            );
        }
        // header with abnormal version
        {
            let mut buf = Vec::with_capacity(LogFileFormat::header_len());
            let abnormal_version = 4_u64; /* abnormal version */
            buf.extend_from_slice(LOG_FILE_MAGIC_HEADER);
            buf.encode_u64(abnormal_version).unwrap();
            buf.encode_u64(16).unwrap();
            assert!(LogFileFormat::decode(&mut &buf[..]).is_err());
        }
        {
            let file_format = LogFileFormat::new(Version::default(), 0);
            assert_eq!(
                LogFileFormat::new(Version::default(), 0),
                enc_dec_file_format(file_format).unwrap()
            );
            let file_format = LogFileFormat::new(Version::default(), 4096);
            assert!(catch_unwind_silent(|| enc_dec_file_format(file_format)).is_err());
        }
    }

    #[test]
    fn test_file_context() {
        let mut file_context =
            LogFileContext::new(FileId::dummy(LogQueue::Append), Version::default());
        assert_eq!(file_context.get_signature(), None);
        file_context.id.seq = 10;
        file_context.version = Version::V2;
        assert_eq!(file_context.get_signature().unwrap(), 10);
        let abnormal_seq = (file_context.id.seq << 32) + 100_u64;
        file_context.id.seq = abnormal_seq;
        assert_ne!(file_context.get_signature().unwrap() as u64, abnormal_seq);
        assert_eq!(file_context.get_signature().unwrap(), 100);
    }
}
