use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
pub(super) struct EventQuery {
    pub(super) cursor: Option<String>,
    pub(super) domain: Option<String>,
    pub(super) kind: Option<String>,
    pub(super) limit: Option<usize>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(default)]
pub(super) struct LogQuery {
    pub(super) cursor: Option<String>,
    pub(super) source: Option<String>,
    pub(super) text: Option<String>,
    pub(super) levels: Vec<String>,
    pub(super) limit: Option<usize>,
}

pub(super) fn event_matches(event: &Value, query: &EventQuery) -> bool {
    if let Some(cursor) = &query.cursor {
        if event
            .get("cursor")
            .and_then(Value::as_str)
            .is_some_and(|c| c <= cursor.as_str())
        {
            return false;
        }
    }
    if let Some(domain) = &query.domain {
        if event.get("domain").and_then(Value::as_str) != Some(domain.as_str()) {
            return false;
        }
    }
    if let Some(kind) = &query.kind {
        if event.get("kind").and_then(Value::as_str) != Some(kind.as_str()) {
            return false;
        }
    }
    true
}

pub(super) fn log_matches(record: &Value, query: &LogQuery) -> bool {
    if let Some(source) = &query.source {
        if record.get("source").and_then(Value::as_str) != Some(source.as_str()) {
            return false;
        }
    }
    if !query.levels.is_empty() {
        let level = record.get("level").and_then(Value::as_str);
        if level.is_none_or(|level| !query.levels.iter().any(|want| want == level)) {
            return false;
        }
    }
    if let Some(text) = &query.text {
        let message = record.get("message").and_then(Value::as_str).unwrap_or("");
        if !message.contains(text) {
            return false;
        }
    }
    true
}
