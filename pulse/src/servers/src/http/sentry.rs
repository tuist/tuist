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

//! Sentry's envelope ingest API, so Sentry SDKs report errors to Pulse.
//!
//! An SDK configured with the DSN
//! `http://<user>:<password>@<pulse>/v1/sentry/<service>/1` posts envelopes to
//! `/v1/sentry/<service>/api/1/envelope/` with the DSN's key and secret in
//! `X-Sentry-Auth`; [`credentials`] reads them as a Pulse user's name and
//! password. The service names the producer, and the project number is ignored:
//! SDKs require a numeric one.
//!
//! Each `event` item becomes a `{"service", "event"}` row for the
//! `sentry_errors` pipeline, which groups, scrubs and writes it to the `errors`
//! table (`infra/helm/pulse`). Other items, such as sessions,
//! transactions and client reports, are accepted and dropped, and so are event
//! items that are not JSON objects, as Atlas does.

use std::collections::BTreeMap;
use std::sync::Arc;

use axum::Extension;
use axum::body::Bytes;
use axum::extract::{Path, Request, State};
use axum::response::{IntoResponse, Response};
use common_base::secrets::SecretString;
use pipeline::{PipelineDefinition, PulsePipelineParams};
use serde_json::json;
use session::context::{Channel, QueryContext};
use snafu::{ResultExt, ensure};
use vrl::value::{KeyString, Value as VrlValue};

use crate::error::{InvalidParameterSnafu, PipelineSnafu, Result};
use crate::http::HttpResponse;
use crate::http::event::{LogState, PipelineIngestRequest, ingest_logs_inner};
use crate::interceptor::LogIngestInterceptor;

pub const SENTRY_PATH_PREFIX: &str = "/v1/sentry/";
/// The largest envelope accepted once decompressed: Sentry's limit for an
/// event item, which the Tuist server's account Sentry endpoint also applies
/// before forwarding envelopes here.
pub const ENVELOPE_LIMIT: usize = 1024 * 1024;
const PIPELINE: &str = "sentry_errors";
const TABLE: &str = "errors";
const AUTH_HEADER: &str = "x-sentry-auth";

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

#[axum_macros::debug_handler]
pub async fn envelope(
    State(log_state): State<LogState>,
    Path((service, _project)): Path<(String, String)>,
    Extension(mut query_ctx): Extension<QueryContext>,
    payload: Bytes,
) -> Result<Response> {
    ensure!(
        is_valid_service(&service),
        InvalidParameterSnafu {
            reason: "the service in a Sentry DSN path has 1 to 64 letters, digits, '.', '_' or '-'",
        }
    );
    let Envelope { event_id, events } = parse_envelope(&payload)?;
    let body = match event_id {
        Some(id) => json!({ "id": id.replace('-', "") }),
        None => json!({}),
    };
    if events.is_empty() {
        return Ok(axum::Json(body).into_response());
    }

    let rows = events
        .into_iter()
        .map(|event| {
            VrlValue::Object(BTreeMap::from([
                (
                    KeyString::from("service"),
                    VrlValue::Bytes(Bytes::from(service.clone())),
                ),
                (KeyString::from("event"), event),
            ]))
        })
        .collect();

    query_ctx.set_channel(Channel::Log);
    let query_ctx = Arc::new(query_ctx);
    let rows = log_state
        .ingest_interceptor
        .as_ref()
        .pre_pipeline(rows, query_ctx.clone())?;
    let pipeline = PipelineDefinition::from_name(PIPELINE, None, None).context(PipelineSnafu)?;
    let response = ingest_logs_inner(
        log_state.log_handler,
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
        HttpResponse::Error(error) => error.into_response(),
        _ => axum::Json(body).into_response(),
    })
}

fn is_valid_service(service: &str) -> bool {
    (1..=64).contains(&service.len())
        && service
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

#[derive(Debug, Default, PartialEq)]
struct Envelope {
    event_id: Option<String>,
    events: Vec<VrlValue>,
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
        events: Vec::new(),
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

        if item_header.get("type").and_then(|t| t.as_str()) == Some("event")
            && let Ok(event @ VrlValue::Object(_)) = serde_json::from_slice::<VrlValue>(payload)
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

    Ok(envelope)
}

fn split_line(bytes: &[u8]) -> (&[u8], &[u8]) {
    match bytes.iter().position(|b| *b == b'\n') {
        Some(at) => (&bytes[..at], &bytes[at + 1..]),
        None => (bytes, &[]),
    }
}

fn parse_header(line: &[u8]) -> Result<serde_json::Map<String, serde_json::Value>> {
    match serde_json::from_slice(line) {
        Ok(serde_json::Value::Object(header)) => Ok(header),
        _ => Err(invalid("an envelope header is not a JSON object")),
    }
}

fn invalid(reason: &str) -> crate::error::Error {
    InvalidParameterSnafu { reason }.build()
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
            "{\"type\":\"session\"}\n",
            "{\"started\":\"2020-02-07T14:16:00Z\"}\n",
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
