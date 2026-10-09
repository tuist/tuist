use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::io::AsyncWriteExt;

#[derive(Debug, Deserialize)]
pub(super) struct Request {
    #[serde(default)]
    pub(super) jsonrpc: Option<String>,
    pub(super) id: Option<Value>,
    pub(super) method: String,
    #[serde(default)]
    pub(super) params: Value,
}

#[derive(Debug, Serialize)]
pub(super) struct Response {
    jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<RpcError>,
}

#[derive(Debug, Serialize)]
struct RpcError {
    code: i32,
    message: String,
}

pub(super) fn success_response(id: Option<Value>, result: Value) -> Response {
    Response {
        jsonrpc: "2.0",
        id,
        result: Some(result),
        error: None,
    }
}

pub(super) fn error_response(id: Option<Value>, code: i32, message: &str) -> Response {
    Response {
        jsonrpc: "2.0",
        id,
        result: None,
        error: Some(RpcError {
            code,
            message: message.to_string(),
        }),
    }
}

pub(super) fn parse_error(message: &str) -> Response {
    error_response(None, -32700, message)
}

pub(super) async fn write_response<W>(write: &mut W, response: Response) -> Result<()>
where
    W: AsyncWriteExt + Unpin,
{
    write_json_line(write, &response).await
}

pub(super) async fn write_json_line<W, T>(write: &mut W, value: &T) -> Result<()>
where
    W: AsyncWriteExt + Unpin,
    T: Serialize,
{
    let mut line = serde_json::to_vec(value)?;
    line.push(b'\n');
    write.write_all(&line).await?;
    write.flush().await?;
    Ok(())
}
