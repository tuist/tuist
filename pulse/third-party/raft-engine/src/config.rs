// Copyright (c) 2017-present, PingCAP, Inc. Licensed under Apache-2.0.

use log::{info, warn};
use serde::{Deserialize, Serialize};

use crate::pipe_log::Version;
use crate::{util::ReadableSize, Result};

const MIN_RECOVERY_READ_BLOCK_SIZE: usize = 512;
const MIN_RECOVERY_THREADS: usize = 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum RecoveryMode {
    AbsoluteConsistency,
    // For backward compatibility.
    #[serde(
        alias = "tolerate-corrupted-tail-records",
        rename(serialize = "tolerate-corrupted-tail-records")
    )]
    TolerateTailCorruption,
    TolerateAnyCorruption,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
#[serde(rename_all = "kebab-case")]
pub struct Config {
    /// Main directory to store log files. Will create on startup if not exists.
    ///
    /// Default: ""
    pub dir: String,

    /// Auxiliary directory to store log files. Will create on startup if
    /// set but not exists.
    ///
    /// Newly logs will be put into this dir when the main `dir` is full
    /// and no spare space for new logs.
    ///
    /// Default: None
    pub spill_dir: Option<String>,

    /// How to deal with file corruption during recovery.
    ///
    /// Default: "tolerate-tail-corruption".
    pub recovery_mode: RecoveryMode,
    /// Minimum I/O size for reading log files during recovery.
    ///
    /// Default: "16KB". Minimum: "512B".
    pub recovery_read_block_size: ReadableSize,
    /// The number of threads used to scan and recovery log files.
    ///
    /// Default: 4. Minimum: 1.
    pub recovery_threads: usize,

    /// Compress a log batch if its size exceeds this value. Setting it to zero
    /// disables compression.
    ///
    /// Default: "8KB"
    pub batch_compression_threshold: ReadableSize,
    /// Acceleration factor for LZ4 compression. It can be fine tuned, with each
    /// successive value providing roughly +~3% to speed. The value will be
    /// capped within [1, 65537] by LZ4.
    ///
    /// Default: 1.
    pub compression_level: Option<usize>,
    /// Deprecated.
    /// Incrementally sync log files after specified bytes have been written.
    /// Setting it to zero disables incremental sync.
    ///
    /// Default: "4MB"
    pub bytes_per_sync: Option<ReadableSize>,

    /// Version of the log file.
    ///
    /// Default: 2
    pub format_version: Version,

    /// Target file size for rotating log files.
    ///
    /// Default: "128MB"
    pub target_file_size: ReadableSize,

    /// Purge append log queue if its size exceeds this value.
    ///
    /// Default: "10GB"
    pub purge_threshold: ReadableSize,
    /// Purge rewrite log queue if its size exceeds this value.
    ///
    /// Default: MAX(`purge_threshold` / 10, `target_file_size`)
    pub purge_rewrite_threshold: Option<ReadableSize>,
    /// Purge rewrite log queue if its garbage ratio exceeds this value.
    ///
    /// Default: "0.6"
    pub purge_rewrite_garbage_ratio: f64,

    /// Maximum memory bytes allowed for the in-memory index.
    /// Effective under the `swap` feature only.
    ///
    /// Default: None
    pub memory_limit: Option<ReadableSize>,

    /// Whether to recycle stale log files.
    /// If `true`, logically purged log files will be reserved for recycling.
    /// Only available for `format_version` 2 and above.
    ///
    /// Default: true
    pub enable_log_recycle: bool,

    /// Whether to prepare log files for recycling when start.
    /// If `true`, batch empty log files will be prepared for recycling when
    /// starting engine.
    /// Only available for `enable-log-reycle` is true.
    ///
    /// Default: false
    pub prefill_for_recycle: bool,

    /// Maximum capacity for preparing log files for recycling when start.
    /// If `None`, its size is equal to `purge-threshold`*1.5.
    /// Only available for `prefill-for-recycle` is true.
    ///
    /// Default: None
    pub prefill_limit: Option<ReadableSize>,
}

impl Default for Config {
    fn default() -> Config {
        #[allow(unused_mut)]
        let mut cfg = Config {
            dir: "".to_owned(),
            spill_dir: None,
            recovery_mode: RecoveryMode::TolerateTailCorruption,
            recovery_read_block_size: ReadableSize::kb(16),
            recovery_threads: 4,
            batch_compression_threshold: ReadableSize::kb(8),
            compression_level: None,
            bytes_per_sync: None,
            format_version: Version::V2,
            target_file_size: ReadableSize::mb(128),
            purge_threshold: ReadableSize::gb(10),
            purge_rewrite_threshold: None,
            purge_rewrite_garbage_ratio: 0.6,
            memory_limit: None,
            enable_log_recycle: true,
            prefill_for_recycle: false,
            prefill_limit: None,
        };
        // Test-specific configurations.
        #[cfg(test)]
        {
            cfg.memory_limit = Some(ReadableSize(0));
        }
        cfg
    }
}

impl Config {
    pub fn sanitize(&mut self) -> Result<()> {
        if self.purge_threshold.0 < self.target_file_size.0 {
            return Err(box_err!("purge-threshold < target-file-size"));
        }
        if self.purge_rewrite_threshold.is_none() {
            self.purge_rewrite_threshold = Some(ReadableSize(std::cmp::max(
                self.purge_threshold.0 / 10,
                self.target_file_size.0,
            )));
        }
        if self.bytes_per_sync.is_some() {
            warn!("bytes-per-sync has been deprecated.");
        }
        let min_recovery_read_block_size = ReadableSize(MIN_RECOVERY_READ_BLOCK_SIZE as u64);
        if self.recovery_read_block_size < min_recovery_read_block_size {
            warn!(
                "recovery-read-block-size ({}) is too small, setting it to {min_recovery_read_block_size}",
                self.recovery_read_block_size
            );
            self.recovery_read_block_size = min_recovery_read_block_size;
        }
        if self.recovery_threads < MIN_RECOVERY_THREADS {
            warn!(
                "recovery-threads ({}) is too small, setting it to {MIN_RECOVERY_THREADS}",
                self.recovery_threads
            );
            self.recovery_threads = MIN_RECOVERY_THREADS;
        }
        if self.enable_log_recycle && !self.format_version.has_log_signing() {
            return Err(box_err!(
                "format version {} doesn't support log recycle, use 2 or above",
                self.format_version
            ));
        }
        if !self.enable_log_recycle && self.prefill_for_recycle {
            return Err(box_err!(
                "prefill is not allowed when log recycle is disabled"
            ));
        }
        if !self.prefill_for_recycle && self.prefill_limit.is_some() {
            warn!("prefill-limit will be ignored when prefill is disabled");
            self.prefill_limit = None;
        }
        if self.prefill_for_recycle && self.prefill_limit.is_none() {
            info!("prefill-limit will be calibrated to purge-threshold");
            self.prefill_limit = Some(self.purge_threshold);
        }
        #[cfg(not(feature = "swap"))]
        if self.memory_limit.is_some() {
            warn!("memory-limit will be ignored because swap feature is disabled");
        }
        Ok(())
    }

    /// Returns the capacity for recycling log files.
    pub(crate) fn recycle_capacity(&self) -> usize {
        // Attention please, log files with Version::V1 could not be recycled, it might
        // cause LogBatchs in a mess in the recycled file, where the reader might get
        // an obsolete entries (unexpected) from the recycled file.
        if !self.format_version.has_log_signing() {
            return 0;
        }
        if self.enable_log_recycle && self.purge_threshold.0 >= self.target_file_size.0 {
            // (1) At most u32::MAX so that the file number can be capped into an u32
            // without colliding. (2) Increase the threshold by 50% to add some more file
            // as an additional buffer to avoid jitters.
            std::cmp::min(
                (self.purge_threshold.0 / self.target_file_size.0) as usize * 3 / 2,
                u32::MAX as usize,
            )
        } else {
            0
        }
    }

    /// Returns the capacity for preparing log files for recycling when start.
    pub(crate) fn prefill_capacity(&self) -> usize {
        // Attention please, log files with Version::V1 could not be recycled, so it's
        // useless for prefill.
        if !self.enable_log_recycle || !self.format_version.has_log_signing() {
            return 0;
        }
        let prefill_limit = self.prefill_limit.unwrap_or(ReadableSize(0)).0;
        if self.prefill_for_recycle && prefill_limit >= self.target_file_size.0 {
            // Keep same with the maximum setting of `recycle_capacity`.
            std::cmp::min(
                (prefill_limit / self.target_file_size.0) as usize * 3 / 2,
                u32::MAX as usize,
            )
        } else {
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serde() {
        let value = Config::default();
        let dump = toml::to_string_pretty(&value).unwrap();
        let load = toml::from_str(&dump).unwrap();
        assert_eq!(value, load);
        assert!(load.spill_dir.is_none());
    }

    #[test]
    fn test_custom() {
        let custom = r#"
            dir = "custom_dir"
            spill-dir = "custom_spill_dir"
            recovery-mode = "tolerate-tail-corruption"
            bytes-per-sync = "2KB"
            target-file-size = "1MB"
            purge-threshold = "3MB"
            format-version = 1
            enable-log-recycle = false
            prefill-for-recycle = false
        "#;
        let mut load: Config = toml::from_str(custom).unwrap();
        assert_eq!(load.dir, "custom_dir");
        assert_eq!(load.spill_dir, Some("custom_spill_dir".to_owned()));
        assert_eq!(load.recovery_mode, RecoveryMode::TolerateTailCorruption);
        assert_eq!(load.bytes_per_sync, Some(ReadableSize::kb(2)));
        assert_eq!(load.target_file_size, ReadableSize::mb(1));
        assert_eq!(load.purge_threshold, ReadableSize::mb(3));
        assert_eq!(load.format_version, Version::V1);
        assert_eq!(load.enable_log_recycle, false);
        assert_eq!(load.prefill_for_recycle, false);
        load.sanitize().unwrap();
    }

    #[test]
    fn test_invalid() {
        let hard_error = r#"
            target-file-size = "5MB"
            purge-threshold = "3MB"
        "#;
        let mut hard_load: Config = toml::from_str(hard_error).unwrap();
        assert!(hard_load.sanitize().is_err());

        let soft_error = r#"
            recovery-read-block-size = 1
            recovery-threads = 0
            target-file-size = "5000MB"
            format-version = 2
            enable-log-recycle = true
            prefill-for-recycle = true
        "#;
        let soft_load: Config = toml::from_str(soft_error).unwrap();
        assert!(soft_load.recovery_read_block_size.0 < MIN_RECOVERY_READ_BLOCK_SIZE as u64);
        assert!(soft_load.recovery_threads < MIN_RECOVERY_THREADS);
        let mut soft_sanitized = soft_load;
        soft_sanitized.sanitize().unwrap();
        assert!(soft_sanitized.recovery_read_block_size.0 >= MIN_RECOVERY_READ_BLOCK_SIZE as u64);
        assert!(soft_sanitized.recovery_threads >= MIN_RECOVERY_THREADS);
        assert_eq!(
            soft_sanitized.purge_rewrite_threshold.unwrap(),
            soft_sanitized.target_file_size
        );

        let recycle_error = r#"
            enable-log-recycle = true
            format-version = 1
        "#;
        let mut cfg_load: Config = toml::from_str(recycle_error).unwrap();
        assert!(cfg_load.sanitize().is_err());

        let prefill_error = r#"
            enable-log-recycle = false
            prefill-for-recycle = true
            format-version = 2
        "#;
        let mut cfg_load: Config = toml::from_str(prefill_error).unwrap();
        assert!(cfg_load.sanitize().is_err());
    }

    #[test]
    fn test_backward_compactibility() {
        // Upgrade from older version.
        let old = r#"
            recovery-mode = "tolerate-corrupted-tail-records"
        "#;
        let mut load: Config = toml::from_str(old).unwrap();
        load.sanitize().unwrap();
        // Downgrade to older version.
        assert!(toml::to_string(&load)
            .unwrap()
            .contains("tolerate-corrupted-tail-records"));
    }

    #[test]
    fn test_prefill_for_recycle() {
        let default_prefill_v1 = r#"
            enable-log-recycle = true
            prefill-for-recycle = true
        "#;
        let mut cfg_load: Config = toml::from_str(default_prefill_v1).unwrap();
        assert!(cfg_load.sanitize().is_ok());
        assert_eq!(cfg_load.prefill_limit.unwrap(), cfg_load.purge_threshold);

        let default_prefill_v2 = r#"
            enable-log-recycle = true
            prefill-for-recycle = false
            prefill-limit = "20GB"
        "#;
        let mut cfg_load: Config = toml::from_str(default_prefill_v2).unwrap();
        assert!(cfg_load.sanitize().is_ok());
        assert!(cfg_load.prefill_limit.is_none());
    }
}
