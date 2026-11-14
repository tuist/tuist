// Copyright 2023 Greptime Team
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Modified by Tuist; see pulse/FORK.md.

use common_base::regex_pattern::NAME_PATTERN_REG;
pub use datafusion_common::ScalarValue;
use once_cell::sync::OnceCell;
use snafu::ensure;

pub use crate::columnar_value::ColumnarValue;
use crate::error::{InvalidColumnPrefixSnafu, Result};
use crate::native_histogram::NATIVE_HISTOGRAM_FIELD;

/// Default time index column name.
static PULSE_TIMESTAMP_CELL: OnceCell<String> = OnceCell::new();

/// Default value column name.
static PULSE_VALUE_CELL: OnceCell<String> = OnceCell::new();

/// Default native histogram column name.
static PULSE_NATIVE_HISTOGRAM_CELL: OnceCell<String> = OnceCell::new();

pub fn set_default_prefix(prefix: Option<&str>) -> Result<()> {
    // Strip surrounding double quotes as a defensive measure against upstream
    // sources (scripts, CI, template engines, incorrect shell escaping) that may
    // pass literal `""` as the value instead of an empty string.
    let stripped = prefix.map(|s| {
        s.strip_prefix('"')
            .and_then(|s| s.strip_suffix('"'))
            .unwrap_or(s)
    });

    match stripped {
        None => {
            // use default pulse prefix
            PULSE_TIMESTAMP_CELL.get_or_init(|| PULSE_TIMESTAMP.to_string());
            PULSE_VALUE_CELL.get_or_init(|| PULSE_VALUE.to_string());
            PULSE_NATIVE_HISTOGRAM_CELL.get_or_init(|| NATIVE_HISTOGRAM_FIELD.to_string());
        }
        Some(s) if s.trim().is_empty() => {
            // use "" to disable prefix
            PULSE_TIMESTAMP_CELL.get_or_init(|| "timestamp".to_string());
            PULSE_VALUE_CELL.get_or_init(|| "value".to_string());
            PULSE_NATIVE_HISTOGRAM_CELL.get_or_init(|| "native_histogram".to_string());
        }
        Some(x) => {
            ensure!(
                NAME_PATTERN_REG.is_match(x),
                InvalidColumnPrefixSnafu { prefix: x }
            );
            PULSE_TIMESTAMP_CELL.get_or_init(|| format!("{}_timestamp", x));
            PULSE_VALUE_CELL.get_or_init(|| format!("{}_value", x));
            PULSE_NATIVE_HISTOGRAM_CELL.get_or_init(|| format!("{}_native_histogram", x));
        }
    }
    Ok(())
}

/// Get the default timestamp column name.
/// Returns the configured value, or `pulse_timestamp` if not set.
pub fn pulse_timestamp() -> &'static str {
    PULSE_TIMESTAMP_CELL.get_or_init(|| PULSE_TIMESTAMP.to_string())
}

/// Get the default value column name.
/// Returns the configured value, or `pulse_value` if not set.
pub fn pulse_value() -> &'static str {
    PULSE_VALUE_CELL.get_or_init(|| PULSE_VALUE.to_string())
}

/// Get the default native histogram column name.
/// Returns the configured value, or `pulse_native_histogram` if not set.
#[inline]
pub fn pulse_native_histogram() -> &'static str {
    PULSE_NATIVE_HISTOGRAM_CELL
        .get()
        .map_or(NATIVE_HISTOGRAM_FIELD, String::as_str)
}

/// Default timestamp column name constant for backward compatibility.
const PULSE_TIMESTAMP: &str = "pulse_timestamp";
/// Default value column name constant for backward compatibility.
const PULSE_VALUE: &str = "pulse_value";
/// Default counter column name for OTLP metrics (legacy mode).
pub const PULSE_COUNT: &str = "pulse_count";
/// Stored series label that opts ordinary float samples into raw-delta math.
pub const OTLP_AGGREGATION_TEMPORALITY_LABEL: &str = "otlp_aggregation_temporality";
/// Authoritative raw-delta value for [`OTLP_AGGREGATION_TEMPORALITY_LABEL`].
pub const PULSE_TEMPORALITY_DELTA: &str = "delta";
/// Default physical table name
pub const PULSE_PHYSICAL_TABLE: &str = "pulse_physical_table";

#[cfg(test)]
mod tests {
    use super::*;

    // Each test runs in a separate process via `cargo nextest`, so OnceCell
    // state does not leak between tests.

    #[test]
    fn test_set_default_prefix_none() {
        set_default_prefix(None).unwrap();
        assert_eq!(pulse_timestamp(), "pulse_timestamp");
        assert_eq!(pulse_value(), "pulse_value");
        assert_eq!(pulse_native_histogram(), "pulse_native_histogram");
    }

    #[test]
    fn test_set_default_prefix_empty_string() {
        set_default_prefix(Some("")).unwrap();
        assert_eq!(pulse_timestamp(), "timestamp");
        assert_eq!(pulse_value(), "value");
        assert_eq!(pulse_native_histogram(), "native_histogram");
    }

    #[test]
    fn test_set_default_prefix_quoted_empty() {
        // Handles upstream sources that pass literal `""` instead of an empty string
        set_default_prefix(Some("\"\"")).unwrap();
        assert_eq!(pulse_timestamp(), "timestamp");
        assert_eq!(pulse_value(), "value");
        assert_eq!(pulse_native_histogram(), "native_histogram");
    }

    #[test]
    fn test_set_default_prefix_custom() {
        set_default_prefix(Some("mydb")).unwrap();
        assert_eq!(pulse_timestamp(), "mydb_timestamp");
        assert_eq!(pulse_value(), "mydb_value");
        assert_eq!(pulse_native_histogram(), "mydb_native_histogram");
    }

    #[test]
    fn test_set_default_prefix_invalid() {
        assert!(set_default_prefix(Some("invalid prefix!")).is_err());
    }
}
