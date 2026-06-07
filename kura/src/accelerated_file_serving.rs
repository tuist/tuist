use std::{
    collections::HashMap,
    io::{Read, Write},
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};

#[cfg(target_os = "linux")]
use std::os::fd::AsRawFd;

use tokio::{
    runtime::Handle,
    sync::{Semaphore, watch},
};
use tracing::info;

use crate::{
    artifact::producer::ArtifactProducer,
    config::{AcceleratedFileServingConfig, AcceleratedFileServingMode},
    runtime::HttpTrafficClass,
    state::SharedState,
    store::AcceleratedArtifactFile,
    utils::{blob_key, module_key},
};

const MAX_HEADER_BYTES: usize = 16 * 1024;
const IO_TIMEOUT: Duration = Duration::from_secs(120);
const NX_NAMESPACE_ID: &str = "nx";
const METRO_NAMESPACE_ID: &str = "metro";
const TENANT_SCOPE_NAMESPACE_ID: &str = "";

pub async fn serve(
    address: SocketAddr,
    config: AcceleratedFileServingConfig,
    state: SharedState,
    mut shutdown_rx: watch::Receiver<bool>,
) -> Result<(), String> {
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .map_err(|error| format!("failed to bind accelerated file serving listener: {error}"))?;
    let semaphore = Arc::new(Semaphore::new(config.max_concurrent));
    info!(
        mode = config.mode.as_str(),
        max_concurrent = config.max_concurrent,
        chunk_bytes = config.chunk_bytes,
        "Kura accelerated HTTP/1 file serving listening on {address}"
    );

    loop {
        tokio::select! {
            result = listener.accept() => {
                let (stream, _) = match result {
                    Ok(stream) => stream,
                    Err(error) => {
                        tracing::warn!("accelerated file serving accept failed: {error}");
                        continue;
                    }
                };
                let Ok(permit) = semaphore.clone().try_acquire_owned() else {
                    tokio::spawn(async move {
                        if let Ok(mut stream) = stream.into_std() {
                            let _ = stream.set_nonblocking(false);
                            let _ = write_response(&mut stream, 503, "Service Unavailable", "text/plain", b"accelerated file serving is at capacity");
                        }
                    });
                    continue;
                };
                let state = state.clone();
                let config = config.clone();
                tokio::task::spawn_blocking(move || {
                    let _permit = permit;
                    match stream.into_std() {
                        Ok(mut stream) => {
                            let _ = stream.set_nonblocking(false);
                            if let Err(error) = serve_connection(&mut stream, &config, state) {
                                tracing::debug!("accelerated file serving connection failed: {error}");
                            }
                        }
                        Err(error) => tracing::debug!("failed to convert accelerated stream: {error}"),
                    }
                });
            }
            changed = shutdown_rx.changed() => {
                if changed.is_err() || *shutdown_rx.borrow() {
                    return Ok(());
                }
            }
        }
    }
}

fn serve_connection(
    stream: &mut std::net::TcpStream,
    config: &AcceleratedFileServingConfig,
    state: SharedState,
) -> std::io::Result<()> {
    stream.set_read_timeout(Some(IO_TIMEOUT))?;
    stream.set_write_timeout(Some(IO_TIMEOUT))?;
    let started_at = Instant::now();
    let Some(request) = read_request(stream)? else {
        return Ok(());
    };

    if request.method != "GET" {
        return write_response(
            stream,
            405,
            "Method Not Allowed",
            "text/plain",
            b"method is not supported by accelerated file serving",
        );
    }
    if state.runtime.is_draining() {
        return write_response(
            stream,
            503,
            "Service Unavailable",
            "text/plain",
            b"server is draining",
        );
    }

    let Some(artifact) = artifact_request(&request.target, &state.config.tenant_id) else {
        return write_response(
            stream,
            404,
            "Not Found",
            "text/plain",
            b"accelerated file serving route not found",
        );
    };

    let _request_guard = state.start_http_request(HttpTrafficClass::Public);
    let runtime = Handle::current();
    match runtime.block_on(state.store.fetch_artifact_for_serving(
        artifact.producer,
        &artifact.namespace_id,
        &artifact.key,
    )) {
        Ok(Some(manifest)) => match runtime
            .block_on(state.store.open_accelerated_artifact_file(&manifest))
        {
            Ok(Some(file)) => {
                write_headers(stream, 200, "OK", &file.content_type, file.size)?;
                let result = transfer_file(stream, &file, config.mode, config.chunk_bytes);
                match result {
                    Ok(bytes) => {
                        state
                            .metrics
                            .record_artifact_read(artifact.producer, "ok", manifest.size);
                        state.metrics.record_artifact_egress(
                            file.producer,
                            "ok",
                            bytes,
                            started_at.elapsed(),
                        );
                        Ok(())
                    }
                    Err(error) => {
                        state
                            .metrics
                            .record_artifact_read(artifact.producer, "error", 0);
                        state.metrics.record_artifact_egress(
                            file.producer,
                            "error",
                            0,
                            started_at.elapsed(),
                        );
                        Err(error)
                    }
                }
            }
            Ok(None) => write_response(
                stream,
                409,
                "Conflict",
                "text/plain",
                b"artifact is not eligible for accelerated file serving",
            ),
            Err(error) => write_response_string(
                stream,
                503,
                "Service Unavailable",
                "text/plain",
                format!("failed to open artifact file: {error}"),
            ),
        },
        Ok(None) => {
            state
                .metrics
                .record_artifact_read(artifact.producer, "not_found", 0);
            write_response(
                stream,
                404,
                "Not Found",
                "text/plain",
                b"artifact not found",
            )
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_read(artifact.producer, "error", 0);
            write_response_string(
                stream,
                503,
                "Service Unavailable",
                "text/plain",
                format!("failed to fetch artifact: {error}"),
            )
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
struct RequestLine {
    method: String,
    target: String,
}

#[derive(Debug, PartialEq, Eq)]
struct ArtifactRequest {
    producer: ArtifactProducer,
    namespace_id: String,
    key: String,
}

fn read_request(stream: &mut std::net::TcpStream) -> std::io::Result<Option<RequestLine>> {
    let mut bytes = Vec::with_capacity(1024);
    let mut buffer = [0_u8; 1024];
    loop {
        let read = stream.read(&mut buffer)?;
        if read == 0 {
            return Ok(None);
        }
        bytes.extend_from_slice(&buffer[..read]);
        if bytes.windows(4).any(|window| window == b"\r\n\r\n") {
            break;
        }
        if bytes.len() > MAX_HEADER_BYTES {
            write_response(
                stream,
                431,
                "Request Header Fields Too Large",
                "text/plain",
                b"request headers are too large",
            )?;
            return Ok(None);
        }
    }

    let request = String::from_utf8_lossy(&bytes);
    let Some(line) = request.lines().next() else {
        return Ok(None);
    };
    let mut parts = line.split_whitespace();
    let Some(method) = parts.next() else {
        return Ok(None);
    };
    let Some(target) = parts.next() else {
        return Ok(None);
    };

    Ok(Some(RequestLine {
        method: method.to_owned(),
        target: target.to_owned(),
    }))
}

fn artifact_request(target: &str, tenant_id: &str) -> Option<ArtifactRequest> {
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    let params = parse_query_map(query);
    if let Some(hash) = one_segment_after(path, "/v1/cache/") {
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Nx,
            namespace_id: NX_NAMESPACE_ID.to_owned(),
            key: hash.to_owned(),
        });
    }
    if let Some(cache_key) = one_segment_after(path, "/api/metro/cache/") {
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Metro,
            namespace_id: METRO_NAMESPACE_ID.to_owned(),
            key: cache_key.to_owned(),
        });
    }
    if let Some(id) = one_segment_after(path, "/api/cache/cas/") {
        let namespace_id = namespace_id_from_params(&params, tenant_id)?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Xcode,
            namespace_id,
            key: blob_key(id),
        });
    }
    if let Some(cache_key) = one_segment_after(path, "/api/cache/gradle/") {
        let namespace_id = namespace_id_from_params(&params, tenant_id)?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Gradle,
            namespace_id,
            key: cache_key.to_owned(),
        });
    }
    if one_segment_after(path, "/api/cache/module/").is_some() {
        let namespace_id = namespace_id_from_params(&params, tenant_id)?;
        let category = params
            .get("cache_category")
            .cloned()
            .unwrap_or_else(|| "builds".to_owned());
        let hash = non_empty_param(&params, "hash")?;
        let name = non_empty_param(&params, "name")?;
        return Some(ArtifactRequest {
            producer: ArtifactProducer::Module,
            namespace_id,
            key: module_key(&category, hash, name),
        });
    }
    None
}

fn one_segment_after<'a>(path: &'a str, prefix: &str) -> Option<&'a str> {
    path.strip_prefix(prefix)
        .filter(|segment| !segment.is_empty() && !segment.contains('/'))
}

fn namespace_id_from_params(params: &HashMap<String, String>, tenant_id: &str) -> Option<String> {
    let request_tenant_id = param_with_aliases(params, "tenant_id", &["account_handle"])?;
    if request_tenant_id != tenant_id {
        return None;
    }
    Some(
        param_with_aliases(params, "namespace_id", &["project_handle"])
            .cloned()
            .unwrap_or_else(|| TENANT_SCOPE_NAMESPACE_ID.to_owned()),
    )
}

fn non_empty_param<'a>(params: &'a HashMap<String, String>, key: &str) -> Option<&'a String> {
    params.get(key).filter(|value| !value.is_empty())
}

fn param_with_aliases<'a>(
    params: &'a HashMap<String, String>,
    key: &str,
    aliases: &[&str],
) -> Option<&'a String> {
    params
        .get(key)
        .or_else(|| aliases.iter().find_map(|alias| params.get(*alias)))
        .filter(|value| !value.is_empty())
}

fn parse_query_map(query: &str) -> HashMap<String, String> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| match pair.split_once('=') {
            Some((key, value)) => (key.to_owned(), value.to_owned()),
            None => (pair.to_owned(), String::new()),
        })
        .collect()
}

fn write_response(
    stream: &mut std::net::TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    body: &[u8],
) -> std::io::Result<()> {
    write_headers(stream, status, reason, content_type, body.len() as u64)?;
    stream.write_all(body)
}

fn write_response_string(
    stream: &mut std::net::TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    body: String,
) -> std::io::Result<()> {
    write_response(stream, status, reason, content_type, body.as_bytes())
}

fn write_headers(
    stream: &mut std::net::TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    content_length: u64,
) -> std::io::Result<()> {
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\ncontent-length: {content_length}\r\ncontent-type: {content_type}\r\nconnection: close\r\n\r\n"
    )
}

#[cfg(target_os = "linux")]
fn transfer_file(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    mode: AcceleratedFileServingMode,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    match mode {
        AcceleratedFileServingMode::Sendfile => transfer_sendfile(stream, file, chunk_bytes),
        AcceleratedFileServingMode::Splice => transfer_splice(stream, file, chunk_bytes),
    }
}

#[cfg(not(target_os = "linux"))]
fn transfer_file(
    _stream: &mut std::net::TcpStream,
    _file: &AcceleratedArtifactFile,
    _mode: AcceleratedFileServingMode,
    _chunk_bytes: usize,
) -> std::io::Result<u64> {
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "accelerated file serving requires Linux",
    ))
}

#[cfg(target_os = "linux")]
fn transfer_sendfile(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let mut offset = file.offset as libc::off_t;
    let end = file.offset.saturating_add(file.size);
    let mut sent_total = 0_u64;
    while (offset as u64) < end {
        let remaining = end - offset as u64;
        let chunk = remaining.min(chunk_bytes as u64) as usize;
        let sent = unsafe { libc::sendfile(out_fd, in_fd, &mut offset, chunk) };
        if sent < 0 {
            let error = std::io::Error::last_os_error();
            if error.kind() == std::io::ErrorKind::Interrupted {
                continue;
            }
            return Err(error);
        }
        if sent == 0 {
            break;
        }
        sent_total += sent as u64;
    }
    if sent_total == file.size {
        Ok(sent_total)
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            format!(
                "sendfile transferred {sent_total} bytes but expected {}",
                file.size
            ),
        ))
    }
}

#[cfg(target_os = "linux")]
fn transfer_splice(
    stream: &mut std::net::TcpStream,
    file: &AcceleratedArtifactFile,
    chunk_bytes: usize,
) -> std::io::Result<u64> {
    let in_fd = file.handle.as_std().as_raw_fd();
    let out_fd = stream.as_raw_fd();
    let mut pipe_fds = [0_i32; 2];
    if unsafe { libc::pipe(pipe_fds.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error());
    }

    let result = (|| {
        let mut offset = file.offset as libc::off_t;
        let end = file.offset.saturating_add(file.size);
        let mut sent_total = 0_u64;
        while (offset as u64) < end {
            let remaining = end - offset as u64;
            let chunk = remaining.min(chunk_bytes as u64) as usize;
            let spliced_in = unsafe {
                libc::splice(
                    in_fd,
                    &mut offset,
                    pipe_fds[1],
                    std::ptr::null_mut(),
                    chunk,
                    0,
                )
            };
            if spliced_in < 0 {
                let error = std::io::Error::last_os_error();
                if error.kind() == std::io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if spliced_in == 0 {
                break;
            }

            let mut pending = spliced_in as usize;
            while pending > 0 {
                let spliced_out = unsafe {
                    libc::splice(
                        pipe_fds[0],
                        std::ptr::null_mut(),
                        out_fd,
                        std::ptr::null_mut(),
                        pending,
                        0,
                    )
                };
                if spliced_out < 0 {
                    let error = std::io::Error::last_os_error();
                    if error.kind() == std::io::ErrorKind::Interrupted {
                        continue;
                    }
                    return Err(error);
                }
                if spliced_out == 0 {
                    break;
                }
                pending -= spliced_out as usize;
                sent_total += spliced_out as u64;
            }
        }
        if sent_total == file.size {
            Ok(sent_total)
        } else {
            Err(std::io::Error::new(
                std::io::ErrorKind::UnexpectedEof,
                format!(
                    "splice transferred {sent_total} bytes but expected {}",
                    file.size
                ),
            ))
        }
    })();

    unsafe {
        libc::close(pipe_fds[0]);
        libc::close(pipe_fds[1]);
    }
    result
}

#[cfg(test)]
mod tests {
    use crate::artifact::producer::ArtifactProducer;

    use super::artifact_request;

    #[test]
    fn parses_xcode_artifact_request() {
        let request = artifact_request(
            "/api/cache/cas/hash?account_handle=acme&project_handle=ios",
            "acme",
        )
        .expect("request should parse");

        assert_eq!(request.producer, ArtifactProducer::Xcode);
        assert_eq!(request.namespace_id, "ios");
        assert_eq!(request.key, "blob/hash");
    }

    #[test]
    fn parses_module_artifact_request() {
        let request = artifact_request(
            "/api/cache/module/cache?tenant_id=acme&namespace_id=ios&cache_category=builds&hash=abc&name=App",
            "acme",
        )
        .expect("request should parse");

        assert_eq!(request.producer, ArtifactProducer::Module);
        assert_eq!(request.namespace_id, "ios");
        assert_eq!(request.key, "builds/abc/App");
    }

    #[test]
    fn rejects_cross_tenant_requests() {
        assert!(artifact_request("/api/cache/gradle/cache?tenant_id=other", "acme").is_none());
    }
}
