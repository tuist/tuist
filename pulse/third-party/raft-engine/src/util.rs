// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use std::fmt::{self, Display, Write};
use std::ops::{Div, Mul};
use std::str::FromStr;
use std::time::{Duration, Instant};

use crc32fast::Hasher;
use serde::de::{self, Unexpected, Visitor};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

const UNIT: u64 = 1;

const BINARY_DATA_MAGNITUDE: u64 = 1024;
pub const B: u64 = UNIT;
pub const KIB: u64 = B * BINARY_DATA_MAGNITUDE;
pub const MIB: u64 = KIB * BINARY_DATA_MAGNITUDE;
pub const GIB: u64 = MIB * BINARY_DATA_MAGNITUDE;
pub const TIB: u64 = GIB * BINARY_DATA_MAGNITUDE;
pub const PIB: u64 = TIB * BINARY_DATA_MAGNITUDE;

#[derive(Clone, Debug, Copy, PartialEq, Eq, PartialOrd)]
pub struct ReadableSize(pub u64);

impl ReadableSize {
    pub const fn kb(count: u64) -> ReadableSize {
        ReadableSize(count * KIB)
    }

    pub const fn mb(count: u64) -> ReadableSize {
        ReadableSize(count * MIB)
    }

    pub const fn gb(count: u64) -> ReadableSize {
        ReadableSize(count * GIB)
    }

    pub const fn as_mb(self) -> u64 {
        self.0 / MIB
    }
}

impl Div<u64> for ReadableSize {
    type Output = ReadableSize;

    fn div(self, rhs: u64) -> ReadableSize {
        ReadableSize(self.0 / rhs)
    }
}

impl Div<ReadableSize> for ReadableSize {
    type Output = u64;

    fn div(self, rhs: ReadableSize) -> u64 {
        self.0 / rhs.0
    }
}

impl Mul<u64> for ReadableSize {
    type Output = ReadableSize;

    fn mul(self, rhs: u64) -> ReadableSize {
        ReadableSize(self.0 * rhs)
    }
}

impl Serialize for ReadableSize {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut buffer = String::new();
        write!(buffer, "{self}").unwrap();
        serializer.serialize_str(&buffer)
    }
}

impl FromStr for ReadableSize {
    type Err = String;

    // This method parses value in binary unit.
    fn from_str(s: &str) -> Result<ReadableSize, String> {
        let size_str = s.trim();
        if size_str.is_empty() {
            return Err(format!("{s:?} is not a valid size."));
        }

        if !size_str.is_ascii() {
            return Err(format!("ASCII string is expected, but got {s:?}"));
        }

        // size: digits and '.' as decimal separator
        let size_len = size_str
            .to_string()
            .chars()
            .take_while(|c| char::is_ascii_digit(c) || ['.', 'e', 'E', '-', '+'].contains(c))
            .count();

        // unit: alphabetic characters
        let (size, unit) = size_str.split_at(size_len);

        let unit = match unit.trim() {
            "K" | "KB" | "KiB" => KIB,
            "M" | "MB" | "MiB" => MIB,
            "G" | "GB" | "GiB" => GIB,
            "T" | "TB" | "TiB" => TIB,
            "P" | "PB" | "PiB" => PIB,
            "B" | "" => B,
            _ => {
                return Err(format!(
                    "only B, KB, KiB, MB, MiB, GB, GiB, TB, TiB, PB, and PiB are supported: {s:?}"
                ));
            }
        };

        match size.parse::<f64>() {
            Ok(n) => Ok(ReadableSize((n * unit as f64) as u64)),
            Err(_) => Err(format!("invalid size string: {s:?}")),
        }
    }
}

impl Display for ReadableSize {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let size = self.0;
        if size == 0 {
            write!(f, "{size}KiB")
        } else if size % PIB == 0 {
            write!(f, "{}PiB", size / PIB)
        } else if size % TIB == 0 {
            write!(f, "{}TiB", size / TIB)
        } else if size % GIB == 0 {
            write!(f, "{}GiB", size / GIB)
        } else if size % MIB == 0 {
            write!(f, "{}MiB", size / MIB)
        } else if size % KIB == 0 {
            write!(f, "{}KiB", size / KIB)
        } else {
            write!(f, "{size}B")
        }
    }
}

impl<'de> Deserialize<'de> for ReadableSize {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct SizeVisitor;

        impl<'de> Visitor<'de> for SizeVisitor {
            type Value = ReadableSize;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("valid size")
            }

            fn visit_i64<E>(self, size: i64) -> Result<ReadableSize, E>
            where
                E: de::Error,
            {
                if size >= 0 {
                    self.visit_u64(size as u64)
                } else {
                    Err(E::invalid_value(Unexpected::Signed(size), &self))
                }
            }

            fn visit_u64<E>(self, size: u64) -> Result<ReadableSize, E>
            where
                E: de::Error,
            {
                Ok(ReadableSize(size))
            }

            fn visit_str<E>(self, size_str: &str) -> Result<ReadableSize, E>
            where
                E: de::Error,
            {
                size_str.parse().map_err(E::custom)
            }
        }

        deserializer.deserialize_any(SizeVisitor)
    }
}

pub trait InstantExt {
    fn saturating_elapsed(&self) -> Duration;
}

impl InstantExt for Instant {
    #[inline]
    fn saturating_elapsed(&self) -> Duration {
        Instant::now().saturating_duration_since(*self)
    }
}

#[inline]
pub fn crc32(data: &[u8]) -> u32 {
    let mut hasher = Hasher::new();
    hasher.update(data);
    hasher.finalize()
}

// Credit: [splitmix64 algorithm](https://xorshift.di.unimi.it/splitmix64.c)
#[inline]
pub fn hash_u64(mut i: u64) -> u64 {
    i = (i ^ (i >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    i = (i ^ (i >> 27)).wrapping_mul(0x94d049bb133111eb);
    i ^ (i >> 31)
}

#[allow(dead_code)]
#[inline]
pub fn unhash_u64(mut i: u64) -> u64 {
    i = (i ^ (i >> 31) ^ (i >> 62)).wrapping_mul(0x319642b2d24d8ec3);
    i = (i ^ (i >> 27) ^ (i >> 54)).wrapping_mul(0x96de1b173f119089);
    i ^ (i >> 30) ^ (i >> 60)
}

pub mod lz4 {
    use crate::{Error, Result};
    use std::{i32, ptr};

    pub const DEFAULT_LZ4_COMPRESSION_LEVEL: usize = 1;

    /// Compress content in `buf[skip..]`, and append output to `buf`.
    pub fn append_compress_block(buf: &mut Vec<u8>, skip: usize, level: usize) -> Result<()> {
        let buf_len = buf.len();
        let content_len = buf_len - skip;
        if content_len > 0 {
            if content_len > i32::MAX as usize {
                return Err(Error::InvalidArgument(format!(
                    "Content too long {content_len}"
                )));
            }
            unsafe {
                let bound = lz4_sys::LZ4_compressBound(content_len as i32);
                debug_assert!(bound > 0);

                // Layout: { decoded_len | content }
                buf.reserve(buf_len + 4 + bound as usize);
                let buf_ptr = buf.as_mut_ptr();

                let le_len = content_len.to_le_bytes();
                ptr::copy_nonoverlapping(le_len.as_ptr(), buf_ptr.add(buf_len), 4);

                let compressed = lz4_sys::LZ4_compress_fast(
                    buf_ptr.add(skip) as _,
                    buf_ptr.add(buf_len + 4) as _,
                    content_len as i32,
                    bound,
                    level as i32,
                );
                if compressed == 0 {
                    return Err(Error::Other(box_err!("Compression failed")));
                }
                buf.set_len(buf_len + 4 + compressed as usize);
            }
        }
        Ok(())
    }

    pub fn decompress_block(src: &[u8]) -> Result<Vec<u8>> {
        if src.len() > 4 {
            unsafe {
                let len = u32::from_le(ptr::read_unaligned(src.as_ptr() as *const u32));
                let mut dst = Vec::with_capacity(len as usize);
                let l = lz4_sys::LZ4_decompress_safe(
                    src.as_ptr().add(4) as _,
                    dst.as_mut_ptr() as _,
                    src.len() as i32 - 4,
                    dst.capacity() as i32,
                );
                if l == len as i32 {
                    dst.set_len(l as usize);
                    Ok(dst)
                } else if l < 0 {
                    Err(Error::Other(box_err!("Decompression failed {l}")))
                } else {
                    Err(Error::Corruption(format!(
                        "Decompressed content length mismatch {l} != {len}"
                    )))
                }
            }
        } else if !src.is_empty() {
            Err(Error::Corruption(format!(
                "Content to compress too short {}",
                src.len()
            )))
        } else {
            Ok(Vec::new())
        }
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn test_basic() {
            let vecs: Vec<Vec<u8>> = vec![b"".to_vec(), b"123".to_vec(), b"12345678910".to_vec()];
            for mut vec in vecs.into_iter() {
                let uncompressed_len = vec.len();
                super::append_compress_block(&mut vec, 0, super::DEFAULT_LZ4_COMPRESSION_LEVEL)
                    .unwrap();
                let res = super::decompress_block(&vec[uncompressed_len..]).unwrap();
                assert_eq!(res, vec[..uncompressed_len].to_owned());
            }
        }
    }
}

pub trait Factory<Target>: Send + Sync {
    fn new_target(&self) -> Target;
}

/// Returns an aligned `offset`.
///
/// # Example:
///
/// ```ignore
/// assert_eq!(round_up(18, 4), 20);
/// assert_eq!(round_up(64, 16), 64);
/// ```
#[inline]
pub fn round_up(offset: usize, alignment: usize) -> usize {
    (offset + alignment - 1) / alignment * alignment
}

/// Returns an aligned `offset`.
///
/// # Example:
///
/// ```ignore
/// assert_eq!(round_down(18, 4), 16);
/// assert_eq!(round_down(64, 16), 64);
/// ```
#[allow(dead_code)]
#[inline]
pub fn round_down(offset: usize, alignment: usize) -> usize {
    offset / alignment * alignment
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_readable_size() {
        let s = ReadableSize::kb(2);
        assert_eq!(s.0, 2048);
        assert_eq!(s.as_mb(), 0);
        let s = ReadableSize::mb(2);
        assert_eq!(s.0, 2 * 1024 * 1024);
        assert_eq!(s.as_mb(), 2);
        let s = ReadableSize::gb(2);
        assert_eq!(s.0, 2 * 1024 * 1024 * 1024);
        assert_eq!(s.as_mb(), 2048);

        assert_eq!((ReadableSize::mb(2) / 2).0, MIB);
        assert_eq!((ReadableSize::mb(1) / 2).0, 512 * KIB);
        assert_eq!(ReadableSize::mb(2) / ReadableSize::kb(1), 2048);
    }

    #[test]
    fn test_parse_readable_size() {
        #[derive(Serialize, Deserialize)]
        struct SizeHolder {
            s: ReadableSize,
        }

        let legal_cases = vec![
            (0, "0KiB"),
            (2 * KIB, "2KiB"),
            (4 * MIB, "4MiB"),
            (5 * GIB, "5GiB"),
            (7 * TIB, "7TiB"),
            (11 * PIB, "11PiB"),
        ];
        for (size, exp) in legal_cases {
            let c = SizeHolder {
                s: ReadableSize(size),
            };
            let res_str = toml::to_string(&c).unwrap();
            let exp_str = format!("s = {exp:?}\n");
            assert_eq!(res_str, exp_str);
            let res_size: SizeHolder = toml::from_str(&exp_str).unwrap();
            assert_eq!(res_size.s.0, size);
        }

        let c = SizeHolder {
            s: ReadableSize(512),
        };
        let res_str = toml::to_string(&c).unwrap();
        assert_eq!(res_str, "s = \"512B\"\n");
        let res_size: SizeHolder = toml::from_str(&res_str).unwrap();
        assert_eq!(res_size.s.0, c.s.0);

        let decode_cases = vec![
            (" 0.5 PB", PIB / 2),
            ("0.5 TB", TIB / 2),
            ("0.5GB ", GIB / 2),
            ("0.5MB", MIB / 2),
            ("0.5KB", KIB / 2),
            ("0.5P", PIB / 2),
            ("0.5T", TIB / 2),
            ("0.5G", GIB / 2),
            ("0.5M", MIB / 2),
            ("0.5K", KIB / 2),
            ("23", 23),
            ("1", 1),
            ("1024B", KIB),
            // units with binary prefixes
            (" 0.5 PiB", PIB / 2),
            ("1PiB", PIB),
            ("0.5 TiB", TIB / 2),
            ("2 TiB", TIB * 2),
            ("0.5GiB ", GIB / 2),
            ("787GiB ", GIB * 787),
            ("0.5MiB", MIB / 2),
            ("3MiB", MIB * 3),
            ("0.5KiB", KIB / 2),
            ("1 KiB", KIB),
            // scientific notation
            ("0.5e6 B", B * 500000),
            ("0.5E6 B", B * 500000),
            ("1e6B", B * 1000000),
            ("8E6B", B * 8000000),
            ("8e7", B * 80000000),
            ("1e-1MB", MIB / 10),
            ("1e+1MB", MIB * 10),
            ("0e+10MB", 0),
        ];
        for (src, exp) in decode_cases {
            let src = format!("s = {src:?}");
            let res: SizeHolder = toml::from_str(&src).unwrap();
            assert_eq!(res.s.0, exp);
        }

        let illegal_cases = vec![
            "0.5kb", "0.5kB", "0.5Kb", "0.5k", "0.5g", "b", "gb", "1b", "B", "1K24B", " 5_KB",
            "4B7", "5M_",
        ];
        for src in illegal_cases {
            let src_str = format!("s = {src:?}");
            assert!(toml::from_str::<SizeHolder>(&src_str).is_err(), "{}", src);
        }
    }

    #[test]
    fn test_unhash() {
        assert_eq!(unhash_u64(hash_u64(777)), 777);
    }

    #[test]
    fn test_rounding() {
        // round_up
        assert_eq!(round_up(18, 4), 20);
        assert_eq!(round_up(64, 16), 64);
        assert_eq!(round_up(79, 4096), 4096);
        // round_down
        assert_eq!(round_down(18, 4), 16);
        assert_eq!(round_down(64, 16), 64);
        assert_eq!(round_down(79, 4096), 0);
    }
}
