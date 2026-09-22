use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result};
use serde_json::{json, Value};
use tokio::fs;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::time::sleep;

use super::protocol::{
    error_response, parse_error, success_response, write_json_line, write_response, Request,
};
use super::query::{EventQuery, LogQuery};
use super::session::RuntimeSession;

pub async fn rpc(session_dir: &Path, socket: Option<&Path>) -> Result<()> {
    let session = RuntimeSession::new(session_dir);
    session
        .describe()
        .await
        .with_context(|| format!("loading runtime session {}", session_dir.display()))?;
    fs::create_dir_all(session_dir).await.with_context(|| {
        format!(
            "creating runtime session directory {}",
            session_dir.display()
        )
    })?;

    let socket = socket.map_or_else(|| session_dir.join("control.sock"), Path::to_path_buf);
    remove_stale_socket(&socket).await?;
    let listener = UnixListener::bind(&socket)
        .with_context(|| format!("binding runtime RPC socket {}", socket.display()))?;
    eprintln!("once: runtime rpc listening on {}", socket.display());

    loop {
        let (stream, _) = listener.accept().await.context("accepting RPC client")?;
        let session = session.clone();
        tokio::spawn(async move {
            if let Err(err) = handle_client(stream, session).await {
                tracing::warn!("runtime RPC client failed: {err:#}");
            }
        });
    }
}

async fn remove_stale_socket(socket: &Path) -> Result<()> {
    if fs::try_exists(socket).await.unwrap_or(false) {
        fs::remove_file(socket)
            .await
            .with_context(|| format!("removing stale socket {}", socket.display()))?;
    }
    Ok(())
}

async fn handle_client(stream: UnixStream, session: RuntimeSession) -> Result<()> {
    let (read, mut write) = stream.into_split();
    let mut lines = BufReader::new(read).lines();
    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }
        let request = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(err) => {
                write_response(&mut write, parse_error(&err.to_string())).await?;
                continue;
            }
        };
        if let Some(response) = validate_jsonrpc(&request) {
            write_response(&mut write, response).await?;
            continue;
        }
        if request.method == "logs.stream" {
            stream_logs(&mut write, &session, request).await?;
            continue;
        }
        let id = request.id.clone();
        let response = match dispatch(&session, request).await {
            Ok(result) => success_response(id, result),
            Err(err) => error_response(id, -32000, &err.to_string()),
        };
        write_response(&mut write, response).await?;
    }
    Ok(())
}

fn validate_jsonrpc(request: &Request) -> Option<super::protocol::Response> {
    request
        .jsonrpc
        .as_deref()
        .is_some_and(|version| version != "2.0")
        .then(|| error_response(request.id.clone(), -32600, "expected jsonrpc version 2.0"))
}

async fn dispatch(session: &RuntimeSession, request: Request) -> Result<Value> {
    match request.method.as_str() {
        "runtime.describe" => session.describe().await,
        "events.query" => {
            let query = serde_json::from_value::<EventQuery>(request.params)
                .context("invalid events.query params")?;
            session.events(query).await
        }
        "logs.query" => {
            let query = serde_json::from_value::<LogQuery>(request.params)
                .context("invalid logs.query params")?;
            session.logs(query).await
        }
        other => anyhow::bail!("unknown runtime RPC method `{other}`"),
    }
}

async fn stream_logs<W>(write: &mut W, session: &RuntimeSession, request: Request) -> Result<()>
where
    W: AsyncWriteExt + Unpin,
{
    let query =
        serde_json::from_value::<LogQuery>(request.params).context("invalid logs.stream params")?;
    write_response(
        write,
        success_response(request.id, json!({ "subscribed": true })),
    )
    .await?;
    let mut seen = 0usize;
    loop {
        let records = session.log_files(&query).await?;
        for record in records.iter().skip(seen) {
            let notification = json!({
                "jsonrpc": "2.0",
                "method": "logs.record",
                "params": record
            });
            write_json_line(write, &notification).await?;
        }
        seen = records.len();
        sleep(Duration::from_millis(250)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

    #[tokio::test]
    async fn json_rpc_connection_serves_log_query() {
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("session.json"), "{}")
            .await
            .unwrap();
        fs::write(tmp.path().join("stdout.log"), "ready\n")
            .await
            .unwrap();
        let (client, server) = UnixStream::pair().unwrap();
        let session = RuntimeSession::new(tmp.path());
        let server_task = tokio::spawn(async move { handle_client(server, session).await });
        let (read, mut write) = client.into_split();
        write
            .write_all(
                br#"{"jsonrpc":"2.0","id":7,"method":"logs.query","params":{"source":"stdout"}}"#,
            )
            .await
            .unwrap();
        write.write_all(b"\n").await.unwrap();
        let mut lines = BufReader::new(read).lines();
        let line = lines.next_line().await.unwrap().unwrap();
        let response: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(response["id"], 7);
        assert_eq!(response["result"]["records"][0]["message"], "ready");
        drop(write);
        server_task.await.unwrap().unwrap();
    }
}
