// Copyright 2026 Tuist GmbH
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

//! Sentry's envelope ingest API, so Sentry SDKs report to Pulse.
//!
//! An SDK configured with the DSN
//! `http://<user>:<password>@<pulse>/v1/sentry/<service>/1` posts envelopes to
//! `/v1/sentry/<service>/api/1/envelope/` with the DSN's key and secret in
//! `X-Sentry-Auth`; [`credentials`] reads them as a Pulse user's name and
//! password. The service names the producer, and the project number is ignored:
//! SDKs require a numeric one.
//!
//! Items go where Pulse already keeps that kind of data:
//!
//! - Each `event` item becomes a `{"service", "event"}` row for the
//!   `sentry_errors` pipeline, which groups, scrubs and writes it to the
//!   `errors` table (`infra/helm/pulse`). Event items that are not JSON
//!   objects are dropped, as Atlas does. A service may send
//!   [`HttpOptions::sentry_events_per_minute`](crate::http::HttpOptions) of
//!   them per minute; beyond that they are refused with Sentry's rate-limit
//!   headers, which SDKs obey.
//! - `log` items become OpenTelemetry log records in `opentelemetry_logs`,
//!   and Spans v2 `span` items and the spans of `transaction` events become
//!   OpenTelemetry spans in `opentelemetry_traces`, written through the same
//!   OTLP handler the collectors use, with `service.name` set to the service.
//! - `session` and `sessions` items become rows of the `sessions` table
//!   (`infra/helm/pulse/sessions.sql`), from which crash-free session and
//!   user rates per release are computed.
//!
//! Other items, such as client reports and attachments, are accepted and
//! dropped. `pulse/FORK.md` lists what each mapping keeps and loses.

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::time::{Duration, Instant};

use api::v1::value::ValueData;
use api::v1::{
    ColumnDataType, ColumnSchema, Row, RowInsertRequest, RowInsertRequests, Rows, SemanticType,
    Value as PulseValue,
};
use axum::Extension;
use axum::body::Bytes;
use axum::extract::{Path, Request, State};
use axum::http::{HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use common_base::secrets::SecretString;
use common_catalog::consts::{TRACE_TABLE_NAME, TRACE_TABLE_NAME_SESSION_KEY};
use common_telemetry::warn;
use opentelemetry_proto::tonic::collector::logs::v1::ExportLogsServiceRequest;
use opentelemetry_proto::tonic::collector::trace::v1::ExportTraceServiceRequest;
use opentelemetry_proto::tonic::common::v1::{
    AnyValue, ArrayValue, KeyValue, KeyValueList, any_value,
};
use opentelemetry_proto::tonic::logs::v1::{LogRecord, ResourceLogs, ScopeLogs};
use opentelemetry_proto::tonic::resource::v1::Resource;
use opentelemetry_proto::tonic::trace::v1::span::{Link, SpanKind};
use opentelemetry_proto::tonic::trace::v1::status::StatusCode as SpanStatusCode;
use opentelemetry_proto::tonic::trace::v1::{ResourceSpans, ScopeSpans, Span, Status};
use pipeline::{PipelineDefinition, PipelineWay, PulsePipelineParams};
use serde_json::{Map, Value as JsonValue, json};
use session::context::{Channel, QueryContext};
use sha2::{Digest, Sha256};
use snafu::{ResultExt, ensure};
use vrl::value::{KeyString, Value as VrlValue};

use crate::error::{InvalidParameterSnafu, PipelineSnafu, Result};
use crate::http::HttpResponse;
use crate::http::event::{LogState, PipelineIngestRequest, ingest_logs_inner};
use crate::interceptor::LogIngestInterceptor;
use crate::query_handler::{OpenTelemetryProtocolHandlerRef, PipelineHandlerRef};

pub const SENTRY_PATH_PREFIX: &str = "/v1/sentry/";
/// The largest envelope accepted once decompressed: Sentry's limit for an
/// event item, which the Tuist server's account Sentry endpoint also applies
/// before forwarding envelopes here.
pub const ENVELOPE_LIMIT: usize = 1024 * 1024;
/// Error events a service may send per minute to one frontend, unless
/// `http.sentry_events_per_minute` says otherwise.
pub const DEFAULT_EVENTS_PER_MINUTE: u32 = 600;
const PIPELINE: &str = "sentry_errors";
const TABLE: &str = "errors";
const LOGS_TABLE: &str = "opentelemetry_logs";
const SESSIONS_TABLE: &str = "sessions";
const AUTH_HEADER: &str = "x-sentry-auth";
const RATE_LIMITS_HEADER: &str = "x-sentry-rate-limits";

pub(crate) fn is_sentry_request<B>(req: &Request<B>) -> bool {
    req.uri().path().starts_with(SENTRY_PATH_PREFIX)
}

/// The DSN's key and secret, from `X-Sentry-Auth` or, for clients that cannot
/// set headers, the `sentry_key` and `sentry_secret` query parameters.
/// <https://develop.sentry.dev/sdk/overview/#authentication>
pub(crate) fn credentials<B>(req: &Request<B>) -> Option<(String, SecretString)> {
    let mut key = None;
    let mut secret = None;
    if let Some(header) = req
        .headers()
        .get(AUTH_HEADER)
        .and_then(|value| value.to_str().ok())
    {
        let fields = header
            .trim_start()
            .get(..7)
            .filter(|scheme| scheme.eq_ignore_ascii_case("sentry "))
            .map_or(header, |_| &header.trim_start()[7..]);
        for (name, value) in fields
            .split(',')
            .filter_map(|field| field.trim().split_once('='))
        {
            let value = value.trim().trim_matches('"').to_string();
            match name.trim() {
                "sentry_key" => key = Some(value),
                "sentry_secret" => secret = Some(value),
                _ => {}
            }
        }
    } else if let Some(query) = req.uri().query() {
        for (name, value) in query.split('&').filter_map(|pair| pair.split_once('=')) {
            let value = urlencoding::decode(value)
                .ok()
                .map(|value| value.into_owned());
            match name {
                "sentry_key" => key = value,
                "sentry_secret" => secret = value,
                _ => {}
            }
        }
    }
    match (key, secret) {
        (Some(key), Some(secret)) if !key.is_empty() && !secret.is_empty() => {
            Some((key, secret.into()))
        }
        _ => None,
    }
}

/// The Sentry routes' state: the pipeline handler for events, the OTLP handler
/// for logs and spans, and the per-service event limit shared by every
/// request this server (and its API server) handles.
#[derive(Clone)]
pub struct SentryState {
    pub log_state: LogState,
    pub otlp_handler: OpenTelemetryProtocolHandlerRef,
    pub limiter: Arc<EventLimiter>,
}

#[axum_macros::debug_handler]
pub async fn envelope(
    State(state): State<SentryState>,
    Path((service, _project)): Path<(String, String)>,
    Extension(query_ctx): Extension<QueryContext>,
    payload: Bytes,
) -> Result<Response> {
    ensure!(
        is_valid_service(&service),
        InvalidParameterSnafu {
            reason: "the service in a Sentry DSN path has 1 to 64 letters, digits, '.', '_' or '-'",
        }
    );
    let Envelope {
        event_id,
        mut events,
        logs,
        spans,
        sessions,
    } = parse_envelope(&payload)?;
    let body = match event_id {
        Some(id) => json!({ "id": id.replace('-', "") }),
        None => json!({}),
    };

    let (admitted, retry_after) = state.limiter.admit(&service, events.len(), Instant::now());
    events.truncate(admitted);
    if let Some(seconds) = retry_after
        && events.is_empty()
        && logs.is_empty()
        && spans.is_empty()
        && sessions.is_empty()
    {
        return Ok(rate_limited(seconds));
    }

    if !events.is_empty()
        && let Some(error) = write_events(&state, &service, events, &query_ctx).await?
    {
        return Ok(error);
    }
    if !logs.is_empty() {
        write_logs(&state, &service, logs, &query_ctx).await?;
    }
    if !spans.is_empty() {
        write_spans(&state, &service, spans, &query_ctx).await?;
    }
    if !sessions.is_empty() {
        write_sessions(&state, &service, sessions, &query_ctx).await?;
    }

    let mut response = axum::Json(body).into_response();
    // SDKs read the header on any response, so the events refused from an
    // envelope whose other items were stored still back off.
    if let Some(seconds) = retry_after {
        response
            .headers_mut()
            .insert(RATE_LIMITS_HEADER, rate_limits(seconds));
    }
    Ok(response)
}

/// Runs error events through the `sentry_errors` pipeline. Returns the
/// pipeline's error response, if any.
async fn write_events(
    state: &SentryState,
    service: &str,
    events: Vec<VrlValue>,
    query_ctx: &QueryContext,
) -> Result<Option<Response>> {
    let rows = events
        .into_iter()
        .map(|event| {
            VrlValue::Object(BTreeMap::from([
                (
                    KeyString::from("service"),
                    VrlValue::Bytes(Bytes::from(service.to_string())),
                ),
                (KeyString::from("event"), event),
            ]))
        })
        .collect();

    let mut query_ctx = query_ctx.clone();
    query_ctx.set_channel(Channel::Log);
    let query_ctx = Arc::new(query_ctx);
    let log_state = &state.log_state;
    let rows = log_state
        .ingest_interceptor
        .as_ref()
        .pre_pipeline(rows, query_ctx.clone())?;
    let pipeline = PipelineDefinition::from_name(PIPELINE, None, None).context(PipelineSnafu)?;
    let response = ingest_logs_inner(
        log_state.log_handler.clone(),
        pipeline,
        vec![PipelineIngestRequest {
            table: TABLE.to_string(),
            values: rows,
        }],
        query_ctx,
        PulsePipelineParams::default(),
    )
    .await?;

    Ok(match response {
        HttpResponse::Error(error) => Some(error.into_response()),
        _ => None,
    })
}

/// Writes log records as the OTLP logs endpoint does by default.
async fn write_logs(
    state: &SentryState,
    service: &str,
    logs: Vec<LogRecord>,
    query_ctx: &QueryContext,
) -> Result<()> {
    let mut query_ctx = query_ctx.clone();
    query_ctx.set_channel(Channel::Otlp);
    let request = ExportLogsServiceRequest {
        resource_logs: vec![ResourceLogs {
            resource: Some(resource(service)),
            scope_logs: vec![ScopeLogs {
                log_records: logs,
                ..Default::default()
            }],
            ..Default::default()
        }],
    };
    let pipeline_handler: PipelineHandlerRef = state.otlp_handler.clone();
    state
        .otlp_handler
        .logs(
            pipeline_handler,
            request,
            PipelineWay::OtlpLogDirect(Box::default()),
            PulsePipelineParams::default(),
            LOGS_TABLE.to_string(),
            Arc::new(query_ctx),
        )
        .await?;
    Ok(())
}

/// Writes spans as the collectors do: OTLP through `pulse_trace_v1`.
async fn write_spans(
    state: &SentryState,
    service: &str,
    spans: Vec<Span>,
    query_ctx: &QueryContext,
) -> Result<()> {
    let mut query_ctx = query_ctx.clone();
    query_ctx.set_channel(Channel::Otlp);
    query_ctx.set_extension(TRACE_TABLE_NAME_SESSION_KEY, TRACE_TABLE_NAME);
    let request = ExportTraceServiceRequest {
        resource_spans: vec![ResourceSpans {
            resource: Some(resource(service)),
            scope_spans: vec![ScopeSpans {
                spans,
                ..Default::default()
            }],
            ..Default::default()
        }],
    };
    let pipeline_handler: PipelineHandlerRef = state.otlp_handler.clone();
    let outcome = state
        .otlp_handler
        .traces(
            pipeline_handler,
            request,
            PipelineWay::OtlpTraceDirectV1,
            PulsePipelineParams::default(),
            TRACE_TABLE_NAME.to_string(),
            Arc::new(query_ctx),
        )
        .await?;
    if outcome.rejected_spans > 0 {
        warn!(
            "Rejected {} of {} Sentry spans from {service}: {}",
            outcome.rejected_spans,
            outcome.rejected_spans + outcome.accepted_spans,
            outcome.error_message.unwrap_or_default()
        );
    }
    Ok(())
}

/// Writes session rows, only into a `sessions` table the chart created: a
/// table created on write would be append-only, so a session's updates would
/// add up instead of replacing each other.
async fn write_sessions(
    state: &SentryState,
    service: &str,
    sessions: Vec<SessionRow>,
    query_ctx: &QueryContext,
) -> Result<()> {
    let mut query_ctx = query_ctx.clone();
    query_ctx.set_channel(Channel::Log);
    let handler = &state.log_state.log_handler;
    if handler
        .get_table(SESSIONS_TABLE, &query_ctx)
        .await?
        .is_none()
    {
        warn!(
            "Dropped {} Sentry sessions from {service}: the {SESSIONS_TABLE} table does not exist",
            sessions.len()
        );
        return Ok(());
    }
    let request = sessions_request(service, sessions);
    for result in handler
        .insert_all(vec![(Arc::new(query_ctx), request)])
        .await?
    {
        result?;
    }
    Ok(())
}

fn resource(service: &str) -> Resource {
    Resource {
        attributes: vec![string_attribute("service.name", service)],
        ..Default::default()
    }
}

fn is_valid_service(service: &str) -> bool {
    (1..=64).contains(&service.len())
        && service
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

// Rate limiting.
// <https://develop.sentry.dev/sdk/foundations/transport/rate-limiting/>

/// Counts each service's error events in fixed one-minute windows.
pub struct EventLimiter {
    per_minute: u32,
    windows: parking_lot::Mutex<HashMap<String, Window>>,
}

struct Window {
    start: Instant,
    used: u32,
}

const WINDOW: Duration = Duration::from_secs(60);
/// Services tracked before expired windows are pruned.
const TRACKED_SERVICES: usize = 1024;

impl EventLimiter {
    /// A limiter admitting `per_minute` events per service; 0 admits all.
    pub fn new(per_minute: u32) -> Self {
        Self {
            per_minute,
            windows: Default::default(),
        }
    }

    /// Admits up to `wanted` events from `service`. Returns how many, and when
    /// some were refused, the seconds until the service's window resets.
    fn admit(&self, service: &str, wanted: usize, now: Instant) -> (usize, Option<u64>) {
        if self.per_minute == 0 || wanted == 0 {
            return (wanted, None);
        }
        let mut windows = self.windows.lock();
        if windows.len() >= TRACKED_SERVICES && !windows.contains_key(service) {
            windows.retain(|_, window| now.duration_since(window.start) < WINDOW);
        }
        let window = windows.entry(service.to_string()).or_insert(Window {
            start: now,
            used: 0,
        });
        if now.duration_since(window.start) >= WINDOW {
            *window = Window {
                start: now,
                used: 0,
            };
        }
        let admitted = wanted.min((self.per_minute - window.used) as usize);
        window.used += admitted as u32;
        if admitted == wanted {
            return (admitted, None);
        }
        let left = WINDOW.saturating_sub(now.duration_since(window.start));
        (admitted, Some(left.as_secs_f64().ceil().max(1.0) as u64))
    }
}

/// `X-Sentry-Rate-Limits` for refused error events: `retry_after`,
/// `categories` (SDKs count events without an exception as `default`),
/// `scope` (a service is a Sentry project) and `reason_code`.
fn rate_limits(seconds: u64) -> HeaderValue {
    HeaderValue::from_str(&format!("{seconds}:error;default:project:event_limit"))
        .expect("the header is ASCII")
}

fn rate_limited(seconds: u64) -> Response {
    (
        StatusCode::TOO_MANY_REQUESTS,
        [
            (header::RETRY_AFTER, HeaderValue::from(seconds)),
            (
                header::HeaderName::from_static(RATE_LIMITS_HEADER),
                rate_limits(seconds),
            ),
        ],
        axum::Json(json!({ "detail": "event rate limit exceeded" })),
    )
        .into_response()
}

// Envelope parsing.

#[derive(Debug, Default, PartialEq)]
struct Envelope {
    event_id: Option<String>,
    events: Vec<VrlValue>,
    logs: Vec<LogRecord>,
    spans: Vec<Span>,
    sessions: Vec<SessionRow>,
}

/// Parses an envelope: a JSON header line, then items made of a JSON header
/// line and a payload that is `length` bytes long or runs to the next newline.
/// <https://develop.sentry.dev/sdk/data-model/envelopes/>
fn parse_envelope(body: &[u8]) -> Result<Envelope> {
    let (header, mut rest) = split_line(body);
    let header = parse_header(header)?;
    let mut envelope = Envelope {
        event_id: header
            .get("event_id")
            .and_then(|id| id.as_str())
            .map(String::from),
        ..Default::default()
    };

    while !rest.iter().all(u8::is_ascii_whitespace) {
        let (item_header, after_header) = split_line(rest);
        let item_header = parse_header(item_header)?;
        let payload = match item_header.get("length") {
            Some(length) => {
                let length = length
                    .as_u64()
                    .and_then(|length| usize::try_from(length).ok())
                    .filter(|length| *length <= after_header.len())
                    .ok_or_else(|| invalid("an envelope item's length exceeds the envelope"))?;
                let (payload, after) = after_header.split_at(length);
                rest = after.strip_prefix(b"\n").unwrap_or(after);
                payload
            }
            None => {
                let (payload, after) = split_line(after_header);
                rest = after;
                payload
            }
        };

        // Items whose payload does not parse are dropped one by one, so an SDK
        // bug in one item does not lose the others.
        match item_header.get("type").and_then(|t| t.as_str()) {
            Some("event") => {
                if let Ok(event @ VrlValue::Object(_)) = serde_json::from_slice::<VrlValue>(payload)
                {
                    if envelope.event_id.is_none() {
                        envelope.event_id = event
                            .as_object()
                            .and_then(|event| event.get("event_id"))
                            .and_then(|id| id.as_str())
                            .map(|id| id.into_owned());
                    }
                    envelope.events.push(event);
                }
            }
            Some("log") => envelope
                .logs
                .extend(items(payload).iter().filter_map(log_record)),
            Some("span") => envelope
                .spans
                .extend(items(payload).iter().filter_map(stream_span)),
            Some("transaction") => {
                if let Some(transaction) = object(payload) {
                    envelope.spans.extend(transaction_spans(&transaction));
                }
            }
            Some("session") => envelope
                .sessions
                .extend(object(payload).as_ref().and_then(session_row)),
            Some("sessions") => {
                if let Some(aggregates) = object(payload) {
                    envelope.sessions.extend(aggregate_rows(&aggregates));
                }
            }
            _ => {}
        }
    }

    Ok(envelope)
}

fn split_line(bytes: &[u8]) -> (&[u8], &[u8]) {
    match bytes.iter().position(|b| *b == b'\n') {
        Some(at) => (&bytes[..at], &bytes[at + 1..]),
        None => (bytes, &[]),
    }
}

fn parse_header(line: &[u8]) -> Result<Map<String, JsonValue>> {
    match serde_json::from_slice(line) {
        Ok(JsonValue::Object(header)) => Ok(header),
        _ => Err(invalid("an envelope header is not a JSON object")),
    }
}

fn invalid(reason: &str) -> crate::error::Error {
    InvalidParameterSnafu { reason }.build()
}

fn object(payload: &[u8]) -> Option<Map<String, JsonValue>> {
    match serde_json::from_slice(payload) {
        Ok(JsonValue::Object(object)) => Some(object),
        _ => None,
    }
}

/// The objects in a `log` or `span` item's `items` array.
fn items(payload: &[u8]) -> Vec<Map<String, JsonValue>> {
    let Some(mut container) = object(payload) else {
        return Vec::new();
    };
    match container.remove("items") {
        Some(JsonValue::Array(items)) => items
            .into_iter()
            .filter_map(|item| match item {
                JsonValue::Object(item) => Some(item),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

fn str_field<'a>(object: &'a Map<String, JsonValue>, key: &str) -> Option<&'a str> {
    object.get(key).and_then(JsonValue::as_str)
}

/// Nanoseconds since the Unix epoch from seconds (logs, spans) or an RFC 3339
/// string (transactions, sessions), kept to the microsecond SDKs send.
fn timestamp_nanos(value: &JsonValue) -> Option<i64> {
    match value {
        JsonValue::Number(seconds) => {
            let seconds = seconds.as_f64().filter(|s| s.is_finite() && *s >= 0.0)?;
            let whole = seconds.trunc();
            let micros = ((seconds - whole) * 1e6).round() as i64;
            (whole as i64)
                .checked_mul(1_000_000_000)?
                .checked_add(micros * 1000)
        }
        JsonValue::String(time) => chrono::DateTime::parse_from_rfc3339(time)
            .map(|time| time.to_utc())
            // Some SDKs, such as sentry-elixir, leave out the offset.
            .or_else(|_| {
                chrono::NaiveDateTime::parse_from_str(time, "%Y-%m-%dT%H:%M:%S%.f")
                    .map(|time| time.and_utc())
            })
            .ok()?
            .timestamp_nanos_opt(),
        _ => None,
    }
}

/// A trace (16 bytes) or span (8 bytes) ID from its hex form.
fn hex_id(value: Option<&JsonValue>, len: usize) -> Option<Vec<u8>> {
    let id = value?.as_str()?.replace('-', "");
    hex::decode(id).ok().filter(|id| id.len() == len)
}

/// Attributes Sentry SDKs add only with `sendDefaultPii`: the user, the
/// client's address and request headers. Pulse keeps them out of logs and
/// traces, as the `sentry_errors` pipeline does for errors.
fn is_personal(key: &str) -> bool {
    key.starts_with("user.") || key == "client.address" || key.starts_with("http.request.header.")
}

/// Sentry's typed attributes, `{"key": {"value": ..., "type": ...}}`.
/// <https://develop.sentry.dev/sdk/foundations/state-management/scopes/attributes/>
fn typed_attributes(attributes: Option<&JsonValue>) -> Vec<KeyValue> {
    let Some(JsonValue::Object(attributes)) = attributes else {
        return Vec::new();
    };
    attributes
        .iter()
        .filter(|(key, _)| !is_personal(key))
        .filter_map(|(key, attribute)| {
            let value = attribute.get("value")?;
            let typed = match attribute.get("type").and_then(JsonValue::as_str) {
                Some("integer") => value
                    .as_i64()
                    .or_else(|| value.as_str()?.parse().ok())
                    .map(any_value::Value::IntValue),
                Some("double") => value
                    .as_f64()
                    .or_else(|| value.as_str()?.parse().ok())
                    .map(any_value::Value::DoubleValue),
                _ => None,
            };
            Some(key_value(
                key.clone(),
                match typed {
                    Some(typed) => AnyValue { value: Some(typed) },
                    // Strings, booleans, arrays and types added later.
                    None => any_value(value),
                },
            ))
        })
        .collect()
}

fn any_value(value: &JsonValue) -> AnyValue {
    let value = match value {
        JsonValue::Null => None,
        JsonValue::Bool(value) => Some(any_value::Value::BoolValue(*value)),
        JsonValue::Number(number) => Some(match number.as_i64() {
            Some(int) => any_value::Value::IntValue(int),
            None => any_value::Value::DoubleValue(number.as_f64().unwrap_or_default()),
        }),
        JsonValue::String(value) => Some(any_value::Value::StringValue(value.clone())),
        JsonValue::Array(values) => Some(any_value::Value::ArrayValue(ArrayValue {
            values: values.iter().map(any_value).collect(),
        })),
        JsonValue::Object(values) => Some(any_value::Value::KvlistValue(KeyValueList {
            values: values
                .iter()
                .map(|(key, value)| key_value(key.clone(), any_value(value)))
                .collect(),
        })),
    };
    AnyValue { value }
}

fn key_value(key: String, value: AnyValue) -> KeyValue {
    KeyValue {
        key,
        value: Some(value),
        ..Default::default()
    }
}

fn string_attribute(key: &str, value: &str) -> KeyValue {
    key_value(key.to_string(), any_value(&json!(value)))
}

// Logs.
// <https://develop.sentry.dev/sdk/telemetry/logs/>

/// A `log` item entry as an OpenTelemetry log record. Sentry's levels are
/// OpenTelemetry's severity texts; they are stored upper-case, as the
/// collectors store theirs.
fn log_record(log: &Map<String, JsonValue>) -> Option<LogRecord> {
    let time = timestamp_nanos(log.get("timestamp")?)?;
    let level = str_field(log, "level").unwrap_or("info");
    let severity_number = log
        .get("severity_number")
        .and_then(JsonValue::as_i64)
        .and_then(|number| i32::try_from(number).ok())
        .unwrap_or(match level {
            "trace" => 1,
            "debug" => 5,
            "info" => 9,
            "warn" => 13,
            "error" => 17,
            "fatal" => 21,
            _ => 0,
        });
    let attributes = log.get("attributes");
    // SDKs before logs protocol 1.11.0 sent the span as an attribute.
    let span_id = hex_id(log.get("span_id"), 8).or_else(|| {
        hex_id(
            attributes?.get("sentry.trace.parent_span_id")?.get("value"),
            8,
        )
    });
    Some(LogRecord {
        time_unix_nano: time as u64,
        observed_time_unix_nano: time as u64,
        severity_number,
        severity_text: level.to_ascii_uppercase(),
        body: Some(AnyValue {
            value: Some(any_value::Value::StringValue(
                str_field(log, "body")?.to_string(),
            )),
        }),
        attributes: typed_attributes(attributes),
        trace_id: hex_id(log.get("trace_id"), 16).unwrap_or_default(),
        span_id: span_id.unwrap_or_default(),
        ..Default::default()
    })
}

// Spans.
// <https://develop.sentry.dev/sdk/telemetry/spans/span-protocol/>
// <https://develop.sentry.dev/sdk/data-model/event-payloads/transaction/>

/// The OpenTelemetry kind for the span operations that imply one.
fn span_kind(op: Option<&str>) -> SpanKind {
    match op {
        Some("http.server") => SpanKind::Server,
        Some("http.client") => SpanKind::Client,
        Some("queue.publish") => SpanKind::Producer,
        Some("queue.process") => SpanKind::Consumer,
        Some(op) if op == "db" || op.starts_with("db.") => SpanKind::Client,
        _ => SpanKind::Unspecified,
    }
}

/// Spans v2 statuses are `ok` and `error`; transaction spans use the gRPC
/// status names, every one of which but `ok` is a failure.
fn span_status(status: Option<&str>) -> Status {
    match status {
        None => Status::default(),
        Some("ok") => Status {
            code: SpanStatusCode::Ok as i32,
            message: String::new(),
        },
        Some(status) => Status {
            code: SpanStatusCode::Error as i32,
            message: if status == "error" {
                String::new()
            } else {
                status.to_string()
            },
        },
    }
}

/// A Spans v2 item entry.
fn stream_span(span: &Map<String, JsonValue>) -> Option<Span> {
    let start = timestamp_nanos(span.get("start_timestamp")?)?;
    let end = span
        .get("end_timestamp")
        .and_then(timestamp_nanos)
        .unwrap_or(start);
    let mut attributes = typed_attributes(span.get("attributes"));
    let op = span
        .get("attributes")
        .and_then(|attributes| attributes.get("sentry.op")?.get("value")?.as_str());
    if let Some(is_segment) = span.get("is_segment").and_then(JsonValue::as_bool) {
        attributes.push(key_value(
            "sentry.is_segment".to_string(),
            any_value(&json!(is_segment)),
        ));
    }
    let links = span
        .get("links")
        .and_then(JsonValue::as_array)
        .into_iter()
        .flatten()
        .filter_map(|link| {
            Some(Link {
                trace_id: hex_id(link.get("trace_id"), 16)?,
                span_id: hex_id(link.get("span_id"), 8)?,
                attributes: typed_attributes(link.get("attributes")),
                ..Default::default()
            })
        })
        .collect();
    let mut status = span_status(str_field(span, "status"));
    if status.code == SpanStatusCode::Error as i32
        && let Some(message) = span.get("attributes").and_then(|attributes| {
            attributes
                .get("sentry.status.message")?
                .get("value")?
                .as_str()
        })
    {
        status.message = message.to_string();
    }
    Some(Span {
        trace_id: hex_id(span.get("trace_id"), 16)?,
        span_id: hex_id(span.get("span_id"), 8)?,
        parent_span_id: hex_id(span.get("parent_span_id"), 8).unwrap_or_default(),
        name: str_field(span, "name").unwrap_or_default().to_string(),
        kind: span_kind(op) as i32,
        start_time_unix_nano: start as u64,
        end_time_unix_nano: end as u64,
        attributes,
        links,
        status: Some(status),
        ..Default::default()
    })
}

/// A transaction event's spans: the root from `contexts.trace` and its
/// children from `spans`. Their `data` and `tags` become attributes, under
/// the names Spans v2 uses for the operation, release, environment and
/// segment. Measurements, breakdowns and the rest of the event are dropped.
fn transaction_spans(transaction: &Map<String, JsonValue>) -> Vec<Span> {
    let Some(trace) = transaction
        .get("contexts")
        .and_then(|contexts| contexts.get("trace"))
        .and_then(JsonValue::as_object)
    else {
        return Vec::new();
    };
    let Some(trace_id) = hex_id(trace.get("trace_id"), 16) else {
        return Vec::new();
    };
    let segment = str_field(transaction, "transaction");
    let mut shared = Vec::new();
    for (key, field) in [
        ("sentry.release", "release"),
        ("sentry.environment", "environment"),
        ("sentry.platform", "platform"),
    ] {
        if let Some(value) = str_field(transaction, field) {
            shared.push(string_attribute(key, value));
        }
    }
    if let Some(segment) = segment {
        shared.push(string_attribute("sentry.segment.name", segment));
    }

    let root = TransactionSpan {
        span: trace,
        name: segment,
        start: transaction.get("start_timestamp"),
        end: transaction.get("timestamp"),
        tags: transaction.get("tags"),
        is_segment: true,
    };
    let children = transaction
        .get("spans")
        .and_then(JsonValue::as_array)
        .into_iter()
        .flatten()
        .filter_map(JsonValue::as_object)
        .map(|span| TransactionSpan {
            span,
            name: None,
            start: span.get("start_timestamp"),
            end: span.get("timestamp"),
            tags: span.get("tags"),
            is_segment: false,
        });
    std::iter::once(root)
        .chain(children)
        .filter_map(|span| span.to_otlp(&trace_id, &shared))
        .collect()
}

struct TransactionSpan<'a> {
    span: &'a Map<String, JsonValue>,
    name: Option<&'a str>,
    start: Option<&'a JsonValue>,
    end: Option<&'a JsonValue>,
    tags: Option<&'a JsonValue>,
    is_segment: bool,
}

impl TransactionSpan<'_> {
    fn to_otlp(&self, trace_id: &[u8], shared: &[KeyValue]) -> Option<Span> {
        let span = self.span;
        let start = timestamp_nanos(self.start?)?;
        let end = self.end.and_then(timestamp_nanos).unwrap_or(start);
        let op = str_field(span, "op");

        let mut attributes = BTreeMap::new();
        for values in [span.get("data"), self.tags] {
            for (key, value) in values.and_then(JsonValue::as_object).into_iter().flatten() {
                if !is_personal(key) && !value.is_null() {
                    attributes
                        .entry(key.clone())
                        .or_insert_with(|| any_value(value));
                }
            }
        }
        if let Some(op) = op {
            attributes.insert("sentry.op".to_string(), any_value(&json!(op)));
        }
        attributes.insert(
            "sentry.is_segment".to_string(),
            any_value(&json!(self.is_segment)),
        );
        for attribute in shared {
            attributes.insert(attribute.key.clone(), attribute.value.clone()?);
        }

        Some(Span {
            trace_id: hex_id(span.get("trace_id"), 16).unwrap_or_else(|| trace_id.to_vec()),
            span_id: hex_id(span.get("span_id"), 8)?,
            parent_span_id: hex_id(span.get("parent_span_id"), 8).unwrap_or_default(),
            name: self
                .name
                .or_else(|| str_field(span, "description"))
                .or(op)
                .unwrap_or_default()
                .to_string(),
            kind: span_kind(op) as i32,
            start_time_unix_nano: start as u64,
            end_time_unix_nano: end as u64,
            attributes: attributes
                .into_iter()
                .map(|(key, value)| key_value(key, value))
                .collect(),
            status: Some(span_status(str_field(span, "status"))),
            ..Default::default()
        })
    }
}

// Release health.
// <https://develop.sentry.dev/sdk/telemetry/sessions/>

/// A row of the `sessions` table: one session update, or one
/// pre-aggregated group of sessions. The counts split `sessions` by outcome,
/// so the healthy ones are `sessions - errored - crashed - abnormal -
/// unhandled`.
#[derive(Debug, PartialEq)]
struct SessionRow {
    /// When the session (or the aggregate's minute) started, in milliseconds.
    started: i64,
    release: String,
    environment: String,
    /// The session's `sid`, so readers group its updates. Aggregates
    /// get a unique `aggregate-<uuid>`, so they add up.
    session_id: String,
    /// Logical order, independent of ingestion order or frontend replica.
    seq: u64,
    updated: i64,
    /// The SDK's distinct ID (user or device), hashed.
    distinct_id: Option<String>,
    status: Option<String>,
    errors: Option<i64>,
    duration: Option<f64>,
    sessions: i64,
    /// Ended without a crash but with errors, or still running with errors.
    errored: i64,
    crashed: i64,
    abnormal: i64,
    unhandled: i64,
}

const SESSION_COLUMNS: [(&str, ColumnDataType, SemanticType); 16] = [
    (
        "started",
        ColumnDataType::TimestampMillisecond,
        SemanticType::Timestamp,
    ),
    ("service", ColumnDataType::String, SemanticType::Tag),
    ("release", ColumnDataType::String, SemanticType::Tag),
    ("environment", ColumnDataType::String, SemanticType::Tag),
    ("session_id", ColumnDataType::String, SemanticType::Tag),
    ("distinct_id", ColumnDataType::String, SemanticType::Field),
    ("status", ColumnDataType::String, SemanticType::Field),
    ("errors", ColumnDataType::Int64, SemanticType::Field),
    ("duration", ColumnDataType::Float64, SemanticType::Field),
    ("sessions", ColumnDataType::Int64, SemanticType::Field),
    ("errored", ColumnDataType::Int64, SemanticType::Field),
    ("crashed", ColumnDataType::Int64, SemanticType::Field),
    ("abnormal", ColumnDataType::Int64, SemanticType::Field),
    ("unhandled", ColumnDataType::Int64, SemanticType::Field),
    ("seq", ColumnDataType::Uint64, SemanticType::Field),
    (
        "updated",
        ColumnDataType::TimestampNanosecond,
        SemanticType::Field,
    ),
];

/// The session attributes every row carries. Sentry drops sessions without a
/// release, and so does Pulse.
fn session_attributes(payload: &Map<String, JsonValue>) -> Option<(String, String)> {
    let attributes = payload.get("attrs")?.as_object()?;
    let release = str_field(attributes, "release").filter(|release| !release.is_empty())?;
    let environment = str_field(attributes, "environment").unwrap_or_default();
    Some((release.to_string(), environment.to_string()))
}

/// The distinct ID, hashed as Sentry stores it: rates per user need only
/// equality.
fn distinct_id(payload: &Map<String, JsonValue>) -> Option<String> {
    let did = str_field(payload, "did").filter(|did| !did.is_empty())?;
    Some(hex::encode(&Sha256::digest(did.as_bytes())[..16]))
}

fn session_row(session: &Map<String, JsonValue>) -> Option<SessionRow> {
    let (release, environment) = session_attributes(session)?;
    let started = timestamp_nanos(session.get("started")?)? / 1_000_000;
    let received = chrono::Utc::now();
    let updated = match session.get("timestamp") {
        Some(timestamp) => timestamp_nanos(timestamp)?,
        None => received.timestamp_nanos_opt()?,
    };
    // Sentry defines init as sequence zero, even if the SDK sends a seq.
    // An omitted sequence defaults to receipt time in Unix milliseconds.
    let seq = if session.get("init").and_then(JsonValue::as_bool) == Some(true) {
        0
    } else {
        match session.get("seq") {
            Some(seq) => seq.as_u64()?,
            None => received.timestamp_millis() as u64,
        }
    };
    let status = str_field(session, "status").unwrap_or("ok");
    let errors = session
        .get("errors")
        .and_then(JsonValue::as_i64)
        .unwrap_or(0);
    let (errored, crashed, abnormal, unhandled) = match status {
        "crashed" => (0, 1, 0, 0),
        "abnormal" => (0, 0, 1, 0),
        "unhandled" => (0, 0, 0, 1),
        _ => (i64::from(errors > 0), 0, 0, 0),
    };
    Some(SessionRow {
        started,
        seq,
        updated,
        release,
        environment,
        // Only a session whose first update is its last may leave out `sid`.
        session_id: str_field(session, "sid")
            .map(String::from)
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
        distinct_id: distinct_id(session),
        status: Some(status.to_string()),
        errors: Some(errors),
        duration: session.get("duration").and_then(JsonValue::as_f64),
        sessions: 1,
        errored,
        crashed,
        abnormal,
        unhandled,
    })
}

fn aggregate_rows(payload: &Map<String, JsonValue>) -> Vec<SessionRow> {
    let Some((release, environment)) = session_attributes(payload) else {
        return Vec::new();
    };
    payload
        .get("aggregates")
        .and_then(JsonValue::as_array)
        .into_iter()
        .flatten()
        .filter_map(JsonValue::as_object)
        .filter_map(|group| {
            let started = timestamp_nanos(group.get("started")?)? / 1_000_000;
            let count = |key: &str| {
                group
                    .get(key)
                    .and_then(JsonValue::as_u64)
                    .map_or(0, |count| i64::try_from(count).unwrap_or(i64::MAX))
            };
            let (exited, errored, crashed, abnormal, unhandled) = (
                count("exited"),
                count("errored"),
                count("crashed"),
                count("abnormal"),
                count("unhandled"),
            );
            let sessions = exited
                .saturating_add(errored)
                .saturating_add(crashed)
                .saturating_add(abnormal)
                .saturating_add(unhandled);
            (sessions > 0).then(|| SessionRow {
                started,
                seq: 0,
                updated: started * 1_000_000,
                release: release.clone(),
                environment: environment.clone(),
                session_id: format!("aggregate-{}", uuid::Uuid::new_v4()),
                distinct_id: distinct_id(group),
                status: None,
                errors: None,
                duration: None,
                sessions,
                errored,
                crashed,
                abnormal,
                unhandled,
            })
        })
        .collect()
}

fn sessions_request(service: &str, sessions: Vec<SessionRow>) -> RowInsertRequests {
    let string = |value: Option<String>| PulseValue {
        value_data: value.map(ValueData::StringValue),
    };
    let int = |value: Option<i64>| PulseValue {
        value_data: value.map(ValueData::I64Value),
    };
    let rows = sessions
        .into_iter()
        .map(|session| Row {
            values: vec![
                PulseValue {
                    value_data: Some(ValueData::TimestampMillisecondValue(session.started)),
                },
                string(Some(service.to_string())),
                string(Some(session.release)),
                string(Some(session.environment)),
                string(Some(session.session_id)),
                string(session.distinct_id),
                string(session.status),
                int(session.errors),
                PulseValue {
                    value_data: session.duration.map(ValueData::F64Value),
                },
                int(Some(session.sessions)),
                int(Some(session.errored)),
                int(Some(session.crashed)),
                int(Some(session.abnormal)),
                int(Some(session.unhandled)),
                PulseValue {
                    value_data: Some(ValueData::U64Value(session.seq)),
                },
                PulseValue {
                    value_data: Some(ValueData::TimestampNanosecondValue(session.updated)),
                },
            ],
        })
        .collect();
    let schema = SESSION_COLUMNS
        .iter()
        .map(|(name, datatype, semantic_type)| ColumnSchema {
            column_name: name.to_string(),
            datatype: *datatype as i32,
            semantic_type: *semantic_type as i32,
            ..Default::default()
        })
        .collect();
    RowInsertRequests {
        inserts: vec![RowInsertRequest {
            table_name: SESSIONS_TABLE.to_string(),
            rows: Some(Rows { schema, rows }),
        }],
    }
}

#[cfg(test)]
mod tests {
    use axum::http::Request;

    use super::*;

    fn events(envelope: &Envelope) -> Vec<String> {
        envelope
            .events
            .iter()
            .map(|event| {
                event
                    .as_object()
                    .and_then(|event| event.get("message"))
                    .and_then(|message| message.as_str())
                    .map(|message| message.into_owned())
                    .unwrap_or_default()
            })
            .collect()
    }

    #[test]
    fn parses_items_by_length_and_by_newline() {
        // The first payload has a newline inside its declared length, the second
        // runs to the next newline, and the envelope ends without one.
        let body = concat!(
            "{\"event_id\":\"9ec79c33-ec99-42ab-8353-589fcb2e04dc\"}\n",
            "{\"type\":\"event\",\"length\":22}\n",
            "{\"message\":\"a\",\n\"x\":1}\n",
            "{\"type\":\"client_report\"}\n",
            "{\"discarded_events\":[]}\n",
            "{\"type\":\"event\"}\n",
            "{\"message\":\"b\"}",
        );
        let envelope = parse_envelope(body.as_bytes()).unwrap();
        assert_eq!(
            envelope.event_id.as_deref(),
            Some("9ec79c33-ec99-42ab-8353-589fcb2e04dc")
        );
        assert_eq!(events(&envelope), ["a", "b"]);
    }

    #[test]
    fn takes_the_event_id_from_the_event_and_skips_events_that_are_not_objects() {
        let body = concat!(
            "{}\n",
            "{\"type\":\"event\"}\n",
            "not json\n",
            "{\"type\":\"event\"}\n",
            "[1]\n",
            "{\"type\":\"event\",\"length\":35}\n",
            "{\"event_id\":\"abc\",\"message\":\"kept\"}\n",
        );
        let envelope = parse_envelope(body.as_bytes()).unwrap();
        assert_eq!(envelope.event_id.as_deref(), Some("abc"));
        assert_eq!(events(&envelope), ["kept"]);
    }

    #[test]
    fn rejects_malformed_envelopes() {
        for body in [
            "",
            "not json\n",
            "{}\nnot json\n{}",
            "{}\n{\"type\":\"event\",\"length\":100}\n{}",
            "{}\n{\"type\":\"event\",\"length\":-1}\n{}",
        ] {
            assert!(parse_envelope(body.as_bytes()).is_err(), "{body:?}");
        }
        // Items are optional, and trailing newlines are not an item.
        assert_eq!(parse_envelope(b"{}\n\n").unwrap(), Envelope::default());
        // Payloads that are not what their type says are dropped.
        for kind in ["log", "span", "transaction", "session", "sessions"] {
            let body = format!("{{}}\n{{\"type\":\"{kind}\"}}\n[1]\n");
            assert_eq!(
                parse_envelope(body.as_bytes()).unwrap(),
                Envelope::default(),
                "{kind}"
            );
        }
    }

    #[test]
    fn reads_timestamps_as_seconds_or_rfc_3339() {
        let expected = Some(1_795_247_458_998_597_000);
        assert_eq!(timestamp_nanos(&json!(1795247458.998597)), expected);
        assert_eq!(
            timestamp_nanos(&json!("2026-11-21T07:50:58.998597Z")),
            expected
        );
        assert_eq!(
            timestamp_nanos(&json!("2026-11-21T08:50:58.998597+01:00")),
            expected
        );
        // sentry-elixir leaves out the offset; it is UTC.
        assert_eq!(
            timestamp_nanos(&json!("2026-11-21T07:50:58.998597")),
            expected
        );
        for invalid in [json!(-1), json!("yesterday"), json!(null), json!(1e300)] {
            assert_eq!(timestamp_nanos(&invalid), None, "{invalid}");
        }
    }

    fn attribute(attributes: &[KeyValue], key: &str) -> Option<any_value::Value> {
        attributes
            .iter()
            .find(|attribute| attribute.key == key)
            .and_then(|attribute| attribute.value.clone()?.value)
    }

    fn string(value: &str) -> Option<any_value::Value> {
        Some(any_value::Value::StringValue(value.to_string()))
    }

    #[test]
    fn maps_log_items_to_log_records() {
        // From sentry-python 2.75.0, shortened.
        let body = concat!(
            "{\"sent_at\":\"2026-11-21T07:50:58.998818Z\"}\n",
            "{\"item_count\":3,\"type\":\"log\",\"content_type\":\"application/vnd.sentry.items.log+json\"}\n",
            "{\"version\":2,\"items\":[",
            "{\"timestamp\":1795247458.998597,\"level\":\"info\",\"body\":\"Charged order A-17\",",
            "\"attributes\":{\"cents\":{\"value\":1299,\"type\":\"integer\"},",
            "\"ratio\":{\"value\":\"0.5\",\"type\":\"double\"},",
            "\"retryable\":{\"value\":true,\"type\":\"boolean\"},",
            "\"user.email\":{\"value\":\"a@b.c\",\"type\":\"string\"},",
            "\"sentry.release\":{\"value\":\"shop@2.4.1\",\"type\":\"string\"}},",
            "\"trace_id\":\"2aae3f7272084d379c2597711d19d89e\",\"span_id\":\"9ece304c1838dc23\"},",
            // @sentry/node 11 sends the span as an attribute and its own severity.
            "{\"timestamp\":1795247481.1040776,\"level\":\"warn\",\"body\":\"Slow cart\",\"severity_number\":14,",
            "\"trace_id\":\"b13f96cb9ca34a43b74e4f43a312d08b\",",
            "\"attributes\":{\"sentry.trace.parent_span_id\":{\"value\":\"8bea92a3766fa4a2\",\"type\":\"string\"}}},",
            // No body: not a log.
            "{\"timestamp\":1795247481.2,\"level\":\"info\"}",
            "]}\n",
        );
        let logs = parse_envelope(body.as_bytes()).unwrap().logs;
        assert_eq!(logs.len(), 2);

        let info = &logs[0];
        assert_eq!(info.time_unix_nano, 1_795_247_458_998_597_000);
        assert_eq!(info.severity_text, "INFO");
        assert_eq!(info.severity_number, 9);
        assert_eq!(
            info.body.clone().unwrap().value,
            string("Charged order A-17")
        );
        assert_eq!(
            hex::encode(&info.trace_id),
            "2aae3f7272084d379c2597711d19d89e"
        );
        assert_eq!(hex::encode(&info.span_id), "9ece304c1838dc23");
        assert_eq!(
            attribute(&info.attributes, "cents"),
            Some(any_value::Value::IntValue(1299))
        );
        assert_eq!(
            attribute(&info.attributes, "ratio"),
            Some(any_value::Value::DoubleValue(0.5))
        );
        assert_eq!(
            attribute(&info.attributes, "retryable"),
            Some(any_value::Value::BoolValue(true))
        );
        assert_eq!(
            attribute(&info.attributes, "sentry.release"),
            string("shop@2.4.1")
        );
        assert_eq!(attribute(&info.attributes, "user.email"), None);

        let warn = &logs[1];
        assert_eq!(warn.severity_text, "WARN");
        assert_eq!(warn.severity_number, 14);
        assert_eq!(hex::encode(&warn.span_id), "8bea92a3766fa4a2");
    }

    #[test]
    fn maps_spans_v2_items_to_spans() {
        // From @sentry/node 11.16.0, shortened.
        let body = concat!(
            "{\"trace\":{\"trace_id\":\"b13f96cb9ca34a43b74e4f43a312d08b\"}}\n",
            "{\"type\":\"span\",\"item_count\":3,\"content_type\":\"application/vnd.sentry.items.span.v2+json\"}\n",
            "{\"version\":2,\"items\":[",
            "{\"name\":\"load cart\",\"span_id\":\"bfb1d5573b7b0721\",\"trace_id\":\"b13f96cb9ca34a43b74e4f43a312d08b\",",
            "\"parent_span_id\":\"8bea92a3766fa4a2\",\"start_timestamp\":1795247481.1044683,\"end_timestamp\":1795247481.1046152,",
            "\"is_segment\":false,\"status\":\"ok\",\"attributes\":{\"sentry.op\":{\"value\":\"db.query\",\"type\":\"string\"},",
            "\"client.address\":{\"value\":\"10.0.0.1\",\"type\":\"string\"}}},",
            "{\"name\":\"GET /cart\",\"span_id\":\"8bea92a3766fa4a2\",\"trace_id\":\"b13f96cb9ca34a43b74e4f43a312d08b\",",
            "\"start_timestamp\":1795247481.1,\"end_timestamp\":1795247481.2,\"is_segment\":true,\"status\":\"error\",",
            "\"attributes\":{\"sentry.op\":{\"value\":\"http.server\",\"type\":\"string\"},",
            "\"sentry.status.message\":{\"value\":\"internal_error\",\"type\":\"string\"}},",
            "\"links\":[{\"span_id\":\"6c71fc6b09b8b716\",\"trace_id\":\"627a2885119dcc8184fae7eef09438cb\",\"sampled\":true,",
            "\"attributes\":{\"sentry.link.type\":{\"type\":\"string\",\"value\":\"previous_trace\"}}}]},",
            // No span ID: not a span.
            "{\"name\":\"x\",\"trace_id\":\"b13f96cb9ca34a43b74e4f43a312d08b\",\"start_timestamp\":1795247481.1}",
            "]}\n",
        );
        let spans = parse_envelope(body.as_bytes()).unwrap().spans;
        assert_eq!(spans.len(), 2);

        let child = &spans[0];
        assert_eq!(child.name, "load cart");
        assert_eq!(
            hex::encode(&child.trace_id),
            "b13f96cb9ca34a43b74e4f43a312d08b"
        );
        assert_eq!(hex::encode(&child.parent_span_id), "8bea92a3766fa4a2");
        assert_eq!(child.kind, SpanKind::Client as i32);
        assert_eq!(child.start_time_unix_nano, 1_795_247_481_104_468_000);
        assert_eq!(child.end_time_unix_nano, 1_795_247_481_104_615_000);
        assert_eq!(
            child.status.as_ref().unwrap().code,
            SpanStatusCode::Ok as i32
        );
        assert_eq!(
            attribute(&child.attributes, "sentry.is_segment"),
            Some(any_value::Value::BoolValue(false))
        );
        assert_eq!(attribute(&child.attributes, "client.address"), None);

        let segment = &spans[1];
        assert!(segment.parent_span_id.is_empty());
        assert_eq!(segment.kind, SpanKind::Server as i32);
        assert_eq!(
            segment.status,
            Some(Status {
                code: SpanStatusCode::Error as i32,
                message: "internal_error".to_string()
            })
        );
        assert_eq!(segment.links.len(), 1);
        assert_eq!(hex::encode(&segment.links[0].span_id), "6c71fc6b09b8b716");
        assert_eq!(
            attribute(&segment.links[0].attributes, "sentry.link.type"),
            string("previous_trace")
        );
    }

    #[test]
    fn maps_transactions_to_spans() {
        // From sentry-python 2.75.0, shortened.
        let transaction = json!({
            "type": "transaction",
            "transaction": "POST /checkout",
            "contexts": {"trace": {
                "trace_id": "46f0c8c465dc45fc936149d4ad5c53b4",
                "span_id": "bed9b5e4058d1250",
                "parent_span_id": null,
                "op": "http.server",
                "data": {"thread.name": "MainThread", "region": "data"},
            }},
            "tags": {"region": "eu", "user.id": "42"},
            "timestamp": "2026-11-21T07:51:00.071601Z",
            "start_timestamp": "2026-11-21T07:51:00.071335Z",
            "release": "shop@2.4.1",
            "environment": "staging",
            "spans": [
                {
                    "trace_id": "46f0c8c465dc45fc936149d4ad5c53b4",
                    "span_id": "b2c9fd99646772ee",
                    "parent_span_id": "bed9b5e4058d1250",
                    "op": "db.query",
                    "description": "SELECT * FROM orders",
                    "start_timestamp": "2026-11-21T07:51:00.071569Z",
                    "timestamp": "2026-11-21T07:51:00.071579Z",
                    "data": {"db.system": "postgresql"},
                },
                {
                    "span_id": "9dc2f8e89839072e",
                    "parent_span_id": "bed9b5e4058d1250",
                    "op": "http.client",
                    "start_timestamp": 1795247460.071594,
                    "timestamp": 1795247460.0716,
                    "status": "deadline_exceeded",
                },
                {"span_id": "nope", "start_timestamp": 1795247460.0},
            ],
        });
        let body = format!("{{}}\n{{\"type\":\"transaction\"}}\n{transaction}\n");
        let envelope = parse_envelope(body.as_bytes()).unwrap();
        assert!(envelope.events.is_empty());
        let spans = envelope.spans;
        assert_eq!(spans.len(), 3);

        let root = &spans[0];
        assert_eq!(root.name, "POST /checkout");
        assert_eq!(hex::encode(&root.span_id), "bed9b5e4058d1250");
        assert!(root.parent_span_id.is_empty());
        assert_eq!(root.kind, SpanKind::Server as i32);
        assert_eq!(root.start_time_unix_nano, 1_795_247_460_071_335_000);
        assert_eq!(root.end_time_unix_nano, 1_795_247_460_071_601_000);
        assert_eq!(root.status, Some(Status::default()));
        // `data` wins over a tag of the same name; personal tags are dropped.
        assert_eq!(attribute(&root.attributes, "region"), string("data"));
        assert_eq!(attribute(&root.attributes, "user.id"), None);
        assert_eq!(
            attribute(&root.attributes, "sentry.op"),
            string("http.server")
        );
        assert_eq!(
            attribute(&root.attributes, "sentry.is_segment"),
            Some(any_value::Value::BoolValue(true))
        );

        let query = &spans[1];
        assert_eq!(query.name, "SELECT * FROM orders");
        assert_eq!(hex::encode(&query.parent_span_id), "bed9b5e4058d1250");
        assert_eq!(
            attribute(&query.attributes, "db.system"),
            string("postgresql")
        );
        assert_eq!(attribute(&query.attributes, "region"), None);
        for span in &spans {
            assert_eq!(
                attribute(&span.attributes, "sentry.release"),
                string("shop@2.4.1")
            );
            assert_eq!(
                attribute(&span.attributes, "sentry.segment.name"),
                string("POST /checkout")
            );
        }

        // A child without a trace ID or description takes the transaction's
        // trace and its operation's name; any status but `ok` is an error.
        let call = &spans[2];
        assert_eq!(
            hex::encode(&call.trace_id),
            "46f0c8c465dc45fc936149d4ad5c53b4"
        );
        assert_eq!(call.name, "http.client");
        assert_eq!(
            call.status,
            Some(Status {
                code: SpanStatusCode::Error as i32,
                message: "deadline_exceeded".to_string()
            })
        );
    }

    #[test]
    fn maps_sessions_to_rows() {
        let did = hex::encode(&Sha256::digest(b"user-42")[..16]);
        // From sentry-python 2.75.0: one crashed session, then server-mode
        // aggregates and @sentry/node 11.16.0's, which name zero counts.
        let body = concat!(
            "{}\n",
            "{\"type\":\"session\",\"content_type\":\"application/json\",\"length\":243}\n",
            "{\"sid\":\"c7f87317-a5a0-4940-8d2c-e011f8c7794e\",\"init\":true,\"started\":\"2026-11-21T07:51:02.212309Z\",",
            "\"timestamp\":\"2026-11-21T07:51:02.214534Z\",\"status\":\"crashed\",\"errors\":1,\"did\":\"user-42\",",
            "\"attrs\":{\"release\":\"shop@2.4.1\",\"environment\":\"staging\"}}\n",
            "{\"type\":\"session\"}\n",
            "{\"sid\":\"6b2c\",\"started\":\"2026-11-21T07:51:02Z\",\"status\":\"ok\",\"errors\":2,\"duration\":1.5,",
            "\"attrs\":{\"release\":\"shop@2.4.1\"}}\n",
            "{\"type\":\"session\"}\n",
            "{\"sid\":\"no-release\",\"started\":\"2026-11-21T07:51:02Z\",\"attrs\":{}}\n",
            "{\"type\":\"sessions\"}\n",
            "{\"attrs\":{\"environment\":\"staging\",\"release\":\"shop@2.4.1\"},",
            "\"aggregates\":[{\"started\":\"2026-11-21T07:51:00.000000Z\",\"exited\":2,\"errored\":1},",
            "{\"started\":\"2026-11-21T07:52:00Z\",\"did\":\"user-42\",\"crashed\":1,\"abnormal\":2,\"unhandled\":3},",
            "{\"started\":\"2026-11-21T07:53:00Z\",\"exited\":0}]}\n",
        );
        let mut rows = parse_envelope(body.as_bytes()).unwrap().sessions;
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[0].seq, 0);
        assert_eq!(rows[0].updated, 1_795_247_462_214_534_000);
        assert!(rows[1].seq > 0);
        assert!(rows[1].updated > 0);
        for row in &mut rows {
            row.seq = 0;
            row.updated = 0;
        }
        for row in &mut rows[2..] {
            assert!(row.session_id.starts_with("aggregate-"), "{row:?}");
            row.session_id = "aggregate".to_string();
        }
        let started = 1_795_247_462_212;
        let session = |status: &str, errors| SessionRow {
            started,
            seq: 0,
            updated: 0,
            release: "shop@2.4.1".to_string(),
            environment: "staging".to_string(),
            session_id: "c7f87317-a5a0-4940-8d2c-e011f8c7794e".to_string(),
            distinct_id: Some(did.clone()),
            status: Some(status.to_string()),
            errors: Some(errors),
            duration: None,
            sessions: 1,
            errored: 0,
            crashed: 0,
            abnormal: 0,
            unhandled: 0,
        };
        let aggregate = |started| SessionRow {
            started,
            session_id: "aggregate".to_string(),
            distinct_id: None,
            status: None,
            errors: None,
            ..session("", 0)
        };
        assert_eq!(
            rows,
            [
                SessionRow {
                    crashed: 1,
                    ..session("crashed", 1)
                },
                SessionRow {
                    started: 1_795_247_462_000,
                    environment: String::new(),
                    session_id: "6b2c".to_string(),
                    distinct_id: None,
                    duration: Some(1.5),
                    errored: 1,
                    ..session("ok", 2)
                },
                SessionRow {
                    sessions: 3,
                    errored: 1,
                    ..aggregate(1_795_247_460_000)
                },
                SessionRow {
                    distinct_id: Some(did.clone()),
                    sessions: 6,
                    crashed: 1,
                    abnormal: 2,
                    unhandled: 3,
                    ..aggregate(1_795_247_520_000)
                },
            ]
        );
    }

    #[test]
    fn limits_each_services_events_per_minute() {
        let limiter = EventLimiter::new(3);
        let start = Instant::now();
        assert_eq!(limiter.admit("kura", 2, start), (2, None));
        // Within the window, only what is left of the quota.
        assert_eq!(
            limiter.admit("kura", 2, start + Duration::from_millis(500)),
            (1, Some(60))
        );
        assert_eq!(
            limiter.admit("kura", 1, start + Duration::from_secs(45)),
            (0, Some(15))
        );
        // Envelopes without events are never limited.
        assert_eq!(
            limiter.admit("kura", 0, start + Duration::from_secs(45)),
            (0, None)
        );
        // Services have their own quota.
        assert_eq!(
            limiter.admit("server", 3, start + Duration::from_secs(45)),
            (3, None)
        );
        // The window resets a minute after it started.
        assert_eq!(
            limiter.admit("kura", 3, start + Duration::from_secs(60)),
            (3, None)
        );
        assert_eq!(
            limiter.admit("kura", 1, start + Duration::from_secs(119)),
            (0, Some(1))
        );
        // 0 disables the limit.
        assert_eq!(
            EventLimiter::new(0).admit("kura", 10_000, start),
            (10_000, None)
        );
    }

    #[test]
    fn answers_rate_limited_envelopes_as_relay_does() {
        let response = rate_limited(42);
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_eq!(response.headers()[header::RETRY_AFTER], "42");
        // `retry_after:categories:scope:reason_code`.
        assert_eq!(
            response.headers()[RATE_LIMITS_HEADER],
            "42:error;default:project:event_limit"
        );
    }

    fn request(header: Option<&str>, uri: &str) -> Request<()> {
        let mut builder = Request::builder().uri(uri);
        if let Some(header) = header {
            builder = builder.header("X-Sentry-Auth", header);
        }
        builder.body(()).unwrap()
    }

    fn user(req: &Request<()>) -> Option<(String, String)> {
        use common_base::secrets::ExposeSecret;
        credentials(req).map(|(key, secret)| (key, secret.expose_secret().clone()))
    }

    #[test]
    fn reads_the_key_and_secret() {
        let path = "/v1/sentry/server/api/1/envelope/";
        let both = Some(("tuist".to_string(), "p4ss=word".to_string()));
        // sentry-elixir
        assert_eq!(
            user(&request(
                Some(
                    "Sentry sentry_version=7, sentry_client=sentry-elixir/11.0.4, sentry_timestamp=1, sentry_key=tuist, sentry_secret=p4ss=word"
                ),
                path
            )),
            both
        );
        // sentry-rust
        assert_eq!(
            user(&request(
                Some(
                    "sentry sentry_key=tuist, sentry_secret=p4ss=word, sentry_version=7, sentry_client=sentry.rust/0.47.0"
                ),
                path
            )),
            both
        );
        assert_eq!(
            user(&request(
                None,
                &format!("{path}?sentry_key=tuist&sentry_secret=p4ss%3Dword")
            )),
            both
        );
        // A DSN without a secret has no Pulse password.
        assert_eq!(user(&request(Some("Sentry sentry_key=tuist"), path)), None);
        assert_eq!(user(&request(None, path)), None);
    }

    #[test]
    fn validates_the_service() {
        for service in ["server", "kura", "tuist-registry", "a.b_c"] {
            assert!(is_valid_service(service), "{service}");
        }
        for service in ["", "a b", "a/b", "ünïcode", &"a".repeat(65)] {
            assert!(!is_valid_service(service), "{service}");
        }
    }
}
