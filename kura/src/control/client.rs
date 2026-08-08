//! Finds the node to talk to, and talks to it.
//!
//! The data directory (from `--data-dir` or `KURA_DATA_DIR`) names a runtime
//! file, which names the control socket. That is what makes
//! `kubectl exec ... -- kura runtime inspect` work with no arguments: the pod
//! spec already exports `KURA_DATA_DIR`.
//!
//! Note that reading the environment is *not* sufficient on its own, which is
//! why the runtime file exists. Enrollment calls `set_var` after startup to
//! inject the tenant and peer list into the server process, so a freshly
//! exec'd shell sees the pre-enrollment values. Only the running process knows
//! what it actually resolved.

use std::path::{Path, PathBuf};

use http_body_util::BodyExt as _;
use hyper::{Request, StatusCode};
use hyper_util::rt::TokioIo;
use serde::de::DeserializeOwned;
use tokio::net::UnixStream;

use crate::control::runtime_file::RuntimeInfo;

#[derive(Debug)]
pub struct Target {
    socket_path: PathBuf,
}

impl Target {
    pub fn resolve(data_dir: Option<&Path>) -> Result<Self, String> {
        let data_dir = data_dir.ok_or_else(|| {
            "no data directory given: pass --data-dir or set KURA_DATA_DIR to the \
             data directory of the node to inspect"
                .to_string()
        })?;

        let info = RuntimeInfo::load(data_dir)?;
        Ok(Self {
            socket_path: info.control_socket_path,
        })
    }
}

/// Issues a GET against the control surface and decodes the response.
pub async fn get<T: DeserializeOwned>(target: &Target, path: &str) -> Result<T, String> {
    let body = get_over_socket(&target.socket_path, path).await?;
    serde_json::from_slice(&body)
        .map_err(|error| format!("failed to decode response from {path}: {error}"))
}

/// Issues a GET and returns the response as untyped JSON, for payloads the CLI
/// forwards rather than interprets.
pub async fn get_json(target: &Target, path: &str) -> Result<serde_json::Value, String> {
    get(target, path).await
}

/// Issues a mutating request, carrying the grant that authorizes it.
///
/// The grant is sent as a header rather than in the body or the path so it
/// stays out of anything that logs a request line.
pub async fn mutate<T: DeserializeOwned>(
    target: &Target,
    method: &str,
    path: &str,
    grant: Option<&str>,
    body: Option<serde_json::Value>,
) -> Result<T, String> {
    let grant = grant.ok_or_else(|| {
        "this command changes state and needs a grant: pass --grant or set KURA_GRANT".to_string()
    })?;
    let body = request(&target.socket_path, method, path, Some(grant), body).await?;
    serde_json::from_slice(&body)
        .map_err(|error| format!("failed to decode response from {path}: {error}"))
}

async fn get_over_socket(socket_path: &Path, path: &str) -> Result<Vec<u8>, String> {
    request(socket_path, "GET", path, None, None).await
}

async fn request(
    socket_path: &Path,
    method: &str,
    path: &str,
    grant: Option<&str>,
    body: Option<serde_json::Value>,
) -> Result<Vec<u8>, String> {
    let stream = UnixStream::connect(socket_path).await.map_err(|error| {
        // A socket that exists but refuses connections is the signature of a
        // node that died without cleaning up. Say so, rather than surfacing a
        // bare ECONNREFUSED.
        if error.kind() == std::io::ErrorKind::ConnectionRefused {
            format!(
                "{} exists but nothing is listening on it. \
                 The node that created it is no longer running.",
                socket_path.display()
            )
        } else if error.kind() == std::io::ErrorKind::NotFound {
            format!(
                "{} does not exist. The node is not running, or it shut down cleanly.",
                socket_path.display()
            )
        } else {
            format!("failed to connect to {}: {error}", socket_path.display())
        }
    })?;

    let (mut sender, connection) = hyper::client::conn::http1::handshake(TokioIo::new(stream))
        .await
        .map_err(|error| format!("control handshake failed: {error}"))?;

    let connection = tokio::spawn(async move {
        if let Err(error) = connection.await {
            tracing::debug!("control connection closed: {error}");
        }
    });

    // The authority is ignored by the server but has to be syntactically valid.
    let mut builder = Request::builder()
        .method(method)
        .uri(path)
        .header(hyper::header::HOST, "kura.local");
    if let Some(grant) = grant {
        builder = builder.header(crate::control::server::GRANT_HEADER, grant);
    }
    let payload = match body {
        Some(body) => {
            builder = builder.header(hyper::header::CONTENT_TYPE, "application/json");
            axum::body::Body::from(
                serde_json::to_vec(&body)
                    .map_err(|error| format!("failed to encode request: {error}"))?,
            )
        }
        None => axum::body::Body::empty(),
    };
    let request = builder
        .body(payload)
        .map_err(|error| format!("failed to build control request: {error}"))?;

    let response = sender
        .send_request(request)
        .await
        .map_err(|error| format!("control request failed: {error}"))?;

    let status = response.status();
    let body = response
        .into_body()
        .collect()
        .await
        .map_err(|error| format!("failed to read control response: {error}"))?
        .to_bytes();
    connection.abort();

    if status == StatusCode::NOT_FOUND && method == "GET" {
        return Err(format!(
            "the node does not serve {path}. \
             The CLI is newer than the node it is talking to."
        ));
    }
    if !status.is_success() {
        let message = serde_json::from_slice::<serde_json::Value>(&body)
            .ok()
            .and_then(|value| value.get("error")?.as_str().map(str::to_string))
            .unwrap_or_else(|| String::from_utf8_lossy(&body).to_string());
        return Err(format!("control request failed ({status}): {message}"));
    }

    Ok(body.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_data_directory_says_how_to_supply_one() {
        let error = Target::resolve(None).expect_err("should not resolve");
        assert!(error.contains("--data-dir"), "{error}");
        assert!(error.contains("KURA_DATA_DIR"), "{error}");
    }

    #[tokio::test]
    async fn absent_socket_is_reported_as_a_stopped_node() {
        let dir = tempfile::tempdir().expect("temp dir");
        let error = get_over_socket(&dir.path().join("missing.sock"), "/v1/runtime")
            .await
            .expect_err("should fail to connect");
        assert!(error.contains("not running"), "{error}");
    }
}
