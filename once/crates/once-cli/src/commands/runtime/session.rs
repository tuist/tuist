use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde_json::{json, Value};
use tokio::fs;

use super::query::{event_matches, log_matches, EventQuery, LogQuery};

#[derive(Clone)]
pub(super) struct RuntimeSession {
    dir: PathBuf,
}

impl RuntimeSession {
    pub(super) fn new(dir: &Path) -> Self {
        Self {
            dir: dir.to_path_buf(),
        }
    }

    pub(super) async fn describe(&self) -> Result<Value> {
        read_json_file(&self.dir.join("session.json")).await
    }

    pub(super) async fn events(&self, query: EventQuery) -> Result<Value> {
        let mut events = Vec::new();
        for event in read_ndjson(&self.dir.join("events.ndjson")).await? {
            if !event_matches(&event, &query) {
                continue;
            }
            events.push(event);
            if events.len() >= query.limit.unwrap_or(200) {
                break;
            }
        }
        Ok(json!({ "events": events }))
    }

    pub(super) async fn logs(&self, query: LogQuery) -> Result<Value> {
        let mut records = self.log_events(&query).await?;
        if records.is_empty() {
            records = self.log_files(&query).await?;
        }
        records.truncate(query.limit.unwrap_or(200));
        Ok(json!({ "records": records }))
    }

    pub(super) async fn log_files(&self, query: &LogQuery) -> Result<Vec<Value>> {
        let mut out = Vec::new();
        for source in ["stdout", "stderr"] {
            if query.source.as_deref().is_some_and(|want| want != source) {
                continue;
            }
            let path = self.dir.join(format!("{source}.log"));
            let Ok(content) = fs::read_to_string(&path).await else {
                continue;
            };
            out.extend(content.lines().enumerate().filter_map(|(idx, line)| {
                let record = json!({
                    "cursor": format!("{source}:{idx:012}"),
                    "source": source,
                    "level": if source == "stderr" { "error" } else { "info" },
                    "message": line,
                    "fields": {}
                });
                log_matches(&record, query).then_some(record)
            }));
        }
        Ok(out)
    }

    async fn log_events(&self, query: &LogQuery) -> Result<Vec<Value>> {
        let records = read_ndjson(&self.dir.join("events.ndjson"))
            .await?
            .into_iter()
            .filter(|event| event.get("domain").and_then(Value::as_str) == Some("logs"))
            .filter(|event| event_is_after_cursor(event, query.cursor.as_deref()))
            .map(|event| event.get("payload").cloned().unwrap_or(event))
            .filter(|record| log_matches(record, query))
            .collect();
        Ok(records)
    }
}

fn event_is_after_cursor(event: &Value, cursor: Option<&str>) -> bool {
    let Some(cursor) = cursor else {
        return true;
    };
    event
        .get("cursor")
        .and_then(Value::as_str)
        .is_none_or(|event_cursor| event_cursor > cursor)
}

async fn read_json_file(path: &Path) -> Result<Value> {
    let raw = fs::read_to_string(path)
        .await
        .with_context(|| format!("reading {}", path.display()))?;
    serde_json::from_str(&raw).with_context(|| format!("parsing {}", path.display()))
}

async fn read_ndjson(path: &Path) -> Result<Vec<Value>> {
    let Ok(raw) = fs::read_to_string(path).await else {
        return Ok(Vec::new());
    };
    raw.lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str::<Value>(line).context("parsing runtime event"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[tokio::test]
    async fn describe_reads_session_json() {
        let tmp = TempDir::new().unwrap();
        fs::write(
            tmp.path().join("session.json"),
            r#"{"sessionId":"s1","runtime":{"kind":"test"}}"#,
        )
        .await
        .unwrap();
        let value = RuntimeSession::new(tmp.path()).describe().await.unwrap();
        assert_eq!(value["sessionId"], "s1");
        assert_eq!(value["runtime"]["kind"], "test");
    }

    #[tokio::test]
    async fn logs_query_filters_stdout_log() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("stdout.log"), "ready\nwarning: slow\n")
            .await
            .unwrap();
        let value = RuntimeSession::new(tmp.path())
            .logs(LogQuery {
                text: Some("slow".to_string()),
                ..LogQuery::default()
            })
            .await
            .unwrap();
        assert_eq!(value["records"].as_array().unwrap().len(), 1);
        assert_eq!(value["records"][0]["message"], "warning: slow");
    }

    #[tokio::test]
    async fn events_query_filters_domain_and_cursor() {
        let tmp = TempDir::new().unwrap();
        fs::write(
            tmp.path().join("events.ndjson"),
            concat!(
                r#"{"cursor":"0001","domain":"logs","kind":"record"}"#,
                "\n",
                r#"{"cursor":"0002","domain":"ui","kind":"snapshot"}"#,
                "\n",
                r#"{"cursor":"0003","domain":"logs","kind":"record"}"#,
                "\n"
            ),
        )
        .await
        .unwrap();
        let value = RuntimeSession::new(tmp.path())
            .events(EventQuery {
                cursor: Some("0001".to_string()),
                domain: Some("logs".to_string()),
                ..EventQuery::default()
            })
            .await
            .unwrap();
        assert_eq!(value["events"].as_array().unwrap().len(), 1);
        assert_eq!(value["events"][0]["cursor"], "0003");
    }
}
