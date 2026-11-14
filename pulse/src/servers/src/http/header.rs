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

use std::collections::HashMap;
use std::sync::Arc;

use common_plugins::PULSE_EXEC_PREFIX;
use datafusion::physical_plan::ExecutionPlan;
use datafusion::physical_plan::metrics::MetricValue;
use headers::{Header, HeaderName, HeaderValue};
use hyper::HeaderMap;
use serde_json::Value;

pub mod constants {
    // New headers use the `x-pulse-db-` prefix.

    pub const PULSE_DB_HEADER_FORMAT: &str = "x-pulse-format";
    pub const PULSE_DB_HEADER_TIMEOUT: &str = "x-pulse-timeout";
    pub const PULSE_DB_HEADER_EXECUTION_TIME: &str = "x-pulse-execution-time";
    pub const PULSE_DB_HEADER_METRICS: &str = "x-pulse-metrics";
    pub const PULSE_DB_HEADER_NAME: &str = "x-pulse-db-name";
    pub const PULSE_DB_HEADER_READ_PREFERENCE: &str = "x-pulse-read-preference";
    pub const PULSE_INSERT_SKIP_WAL_HEADER_NAME: &str = "x-pulse-insert-skip-wal";
    pub const PULSE_TIMEZONE_HEADER_NAME: &str = "x-pulse-timezone";
    pub const PULSE_DB_HEADER_ERROR_CODE: &str = common_error::PULSE_DB_HEADER_ERROR_CODE;

    // Deprecated: pipeline is also used with trace, so we remove log from it.
    pub const PULSE_LOG_PIPELINE_NAME_HEADER_NAME: &str = "x-pulse-log-pipeline-name";
    pub const PULSE_LOG_PIPELINE_VERSION_HEADER_NAME: &str = "x-pulse-log-pipeline-version";

    // More generic pipeline header name
    pub const PULSE_PIPELINE_NAME_HEADER_NAME: &str = "x-pulse-pipeline-name";
    pub const PULSE_PIPELINE_VERSION_HEADER_NAME: &str = "x-pulse-pipeline-version";

    pub const PULSE_LOG_TABLE_NAME_HEADER_NAME: &str = "x-pulse-log-table-name";
    pub const PULSE_LOG_EXTRACT_KEYS_HEADER_NAME: &str = "x-pulse-log-extract-keys";
    pub const PULSE_TRACE_TABLE_NAME_HEADER_NAME: &str = "x-pulse-trace-table-name";

    // OTLP headers
    pub const PULSE_OTLP_METRIC_PROMOTE_ALL_RESOURCE_ATTRS_HEADER_NAME: &str =
        "x-pulse-otlp-metric-promote-all-resource-attrs";
    pub const PULSE_OTLP_METRIC_PROMOTE_RESOURCE_ATTRS_HEADER_NAME: &str =
        "x-pulse-otlp-metric-promote-resource-attrs";
    pub const PULSE_OTLP_METRIC_IGNORE_RESOURCE_ATTRS_HEADER_NAME: &str =
        "x-pulse-otlp-metric-ignore-resource-attrs";
    pub const PULSE_OTLP_METRIC_PROMOTE_SCOPE_ATTRS_HEADER_NAME: &str =
        "x-pulse-otlp-metric-promote-scope-attrs";
    pub const PULSE_OTLP_METRIC_TRANSLATION_STRATEGY_HEADER_NAME: &str =
        "x-pulse-otlp-metric-translation-strategy";

    /// The header key that contains the pipeline params.
    pub const PULSE_PIPELINE_PARAMS_HEADER: &str = "x-pulse-pipeline-params";
}

pub static PULSE_DB_HEADER_FORMAT: HeaderName =
    HeaderName::from_static(constants::PULSE_DB_HEADER_FORMAT);
pub static PULSE_DB_HEADER_EXECUTION_TIME: HeaderName =
    HeaderName::from_static(constants::PULSE_DB_HEADER_EXECUTION_TIME);
pub static PULSE_DB_HEADER_METRICS: HeaderName =
    HeaderName::from_static(constants::PULSE_DB_HEADER_METRICS);

/// Header key of `db-name`. Example format of the header value is `pulse-public`.
pub static PULSE_DB_HEADER_NAME: HeaderName =
    HeaderName::from_static(constants::PULSE_DB_HEADER_NAME);

/// Header key of query specific timezone. Example format of the header value is `Asia/Shanghai` or `+08:00`.
pub static PULSE_TIMEZONE_HEADER_NAME: HeaderName =
    HeaderName::from_static(constants::PULSE_TIMEZONE_HEADER_NAME);

/// Header key of query specific read preference. Example format of the header value is `leader`.
pub static PULSE_DB_HEADER_READ_PREFERENCE: HeaderName =
    HeaderName::from_static(constants::PULSE_DB_HEADER_READ_PREFERENCE);

/// Request-level WAL policy, independent of the table-level skip_wal option.
pub static PULSE_INSERT_SKIP_WAL_HEADER_NAME: HeaderName =
    HeaderName::from_static(constants::PULSE_INSERT_SKIP_WAL_HEADER_NAME);

pub static CONTENT_TYPE_PROTOBUF_STR: &str = "application/x-protobuf";
pub static CONTENT_TYPE_PROTOBUF: HeaderValue = HeaderValue::from_static(CONTENT_TYPE_PROTOBUF_STR);
pub static CONTENT_ENCODING_SNAPPY: HeaderValue = HeaderValue::from_static("snappy");

pub static CONTENT_TYPE_NDJSON_STR: &str = "application/x-ndjson";
pub static CONTENT_TYPE_NDJSON_SUBTYPE_STR: &str = "x-ndjson";

pub struct PulseName(Option<String>);

impl Header for PulseName {
    fn name() -> &'static HeaderName {
        &PULSE_DB_HEADER_NAME
    }

    fn decode<'i, I>(values: &mut I) -> Result<Self, headers::Error>
    where
        Self: Sized,
        I: Iterator<Item = &'i HeaderValue>,
    {
        if let Some(value) = values.next() {
            let str_value = value.to_str().map_err(|_| headers::Error::invalid())?;
            Ok(Self(Some(str_value.to_owned())))
        } else {
            Ok(Self(None))
        }
    }

    fn encode<E: Extend<HeaderValue>>(&self, values: &mut E) {
        if let Some(name) = &self.0
            && let Ok(value) = HeaderValue::from_str(name)
        {
            values.extend(std::iter::once(value));
        }
    }
}

impl PulseName {
    pub fn value(&self) -> Option<&String> {
        self.0.as_ref()
    }
}

// collect write
pub fn write_cost_header_map(cost: usize) -> HeaderMap {
    let mut header_map = HeaderMap::new();
    if cost > 0 {
        let mut map: HashMap<String, Value> = HashMap::new();
        map.insert(
            common_plugins::PULSE_EXEC_WRITE_COST.to_string(),
            Value::from(cost),
        );
        let _ = serde_json::to_string(&map)
            .ok()
            .and_then(|s| HeaderValue::from_str(&s).ok())
            .and_then(|v| header_map.insert(&PULSE_DB_HEADER_METRICS, v));
    }
    header_map
}

fn collect_into_maps(name: &str, value: u64, maps: &mut [&mut HashMap<String, u64>]) {
    if name.starts_with(PULSE_EXEC_PREFIX) && value > 0 {
        maps.iter_mut().for_each(|map| {
            map.entry(name.to_string())
                .and_modify(|v| *v += value)
                .or_insert(value);
        });
    }
}

pub fn collect_plan_metrics(plan: &Arc<dyn ExecutionPlan>, maps: &mut [&mut HashMap<String, u64>]) {
    if let Some(m) = plan.metrics() {
        m.iter().for_each(|m| match m.value() {
            MetricValue::Count { name, count } => {
                collect_into_maps(name, count.value() as u64, maps);
            }
            MetricValue::Gauge { name, gauge } => {
                collect_into_maps(name, gauge.value() as u64, maps);
            }
            MetricValue::Time { name, time } if name.starts_with(PULSE_EXEC_PREFIX) => {
                // override
                maps.iter_mut().for_each(|map| {
                    map.insert(name.to_string(), time.value() as u64);
                });
            }
            _ => {}
        });
    }

    for c in plan.children() {
        collect_plan_metrics(c, maps);
    }
}
