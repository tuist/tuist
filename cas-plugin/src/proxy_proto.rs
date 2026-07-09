//! Wire protocol between the plugin (inside compiler processes) and the
//! per-machine proxy, over a unix domain socket.
//!
//! One request per connection, length-prefixed:
//!   request  = u8 op | u16 cas_path_len | cas_path | u16 instance_len |
//!              instance | u16 payload_len | payload
//!   response = u8 status | u16 body_len | body
//!
//! `instance` is the `account/project` the connection's cache belongs to. It
//! routes the request to the right per-instance remote in the machine-wide
//! proxy. tuist-driven builds pass it (from the CLI's env); an empty instance
//! (an Xcode ⌘B build, which has no CLI env) tells the proxy to fall back to
//! the `cas_path -> instance` mapping a prior build primed.
//!
//! RESOLVE (op 1): payload = action key digest bytes. status 1 = hit (body =
//! value llcas digest, materialized into the local CAS before replying),
//! status 0 = definitive miss, status 2 = proxy error (treat as miss).
//! PUBLISH (op 2): payload = utf8 path of a write-ahead publication record.
//! status 1 = accepted (publication proceeds asynchronously).

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

/// Bumped on any incompatible change to the frame layout below. The proxy
/// rejects a mismatched version (→ the plugin degrades to a local miss) instead
/// of misparsing, so a stale proxy left running across a CLI upgrade can't
/// corrupt a build.
pub const PROTOCOL_VERSION: u8 = 1;

pub const OP_RESOLVE: u8 = 1;
pub const OP_PUBLISH: u8 = 2;
/// The on-disk CAS at `cas_path` was pruned/emptied in place (Xcode's size
/// management calls `llcas_cas_prune_ondisk_data`), removing objects without
/// recreating the directory. The proxy's directory-identity wipe check can't
/// see that, so the plugin tells it to drop the path's in-memory known-local /
/// resolved marks, which would otherwise skip re-fetching the pruned blobs.
pub const OP_INVALIDATE: u8 = 3;

pub const STATUS_MISS: u8 = 0;
pub const STATUS_HIT: u8 = 1;
pub const STATUS_ERROR: u8 = 2;

pub struct Request {
    pub version: u8,
    pub op: u8,
    pub cas_path: String,
    pub instance: String,
    pub payload: Vec<u8>,
}

fn read_u16_field(stream: &mut UnixStream) -> std::io::Result<Vec<u8>> {
    let mut len = [0u8; 2];
    stream.read_exact(&mut len)?;
    let mut field = vec![0u8; u16::from_be_bytes(len) as usize];
    stream.read_exact(&mut field)?;
    Ok(field)
}

pub fn write_request(stream: &mut UnixStream, request: &Request) -> std::io::Result<()> {
    let mut frame = Vec::with_capacity(
        8 + request.cas_path.len() + request.instance.len() + request.payload.len(),
    );
    frame.push(request.version);
    frame.push(request.op);
    frame.extend_from_slice(&(request.cas_path.len() as u16).to_be_bytes());
    frame.extend_from_slice(request.cas_path.as_bytes());
    frame.extend_from_slice(&(request.instance.len() as u16).to_be_bytes());
    frame.extend_from_slice(request.instance.as_bytes());
    frame.extend_from_slice(&(request.payload.len() as u16).to_be_bytes());
    frame.extend_from_slice(&request.payload);
    stream.write_all(&frame)
}

pub fn read_request(stream: &mut UnixStream) -> std::io::Result<Request> {
    let mut header = [0u8; 2];
    stream.read_exact(&mut header)?;
    let cas_path = read_u16_field(stream)?;
    let instance = read_u16_field(stream)?;
    let payload = read_u16_field(stream)?;
    Ok(Request {
        version: header[0],
        op: header[1],
        cas_path: String::from_utf8_lossy(&cas_path).into_owned(),
        instance: String::from_utf8_lossy(&instance).into_owned(),
        payload,
    })
}

pub fn write_response(stream: &mut UnixStream, status: u8, body: &[u8]) -> std::io::Result<()> {
    let mut frame = Vec::with_capacity(3 + body.len());
    frame.push(status);
    frame.extend_from_slice(&(body.len() as u16).to_be_bytes());
    frame.extend_from_slice(body);
    stream.write_all(&frame)
}

pub fn read_response(stream: &mut UnixStream) -> std::io::Result<(u8, Vec<u8>)> {
    let mut header = [0u8; 3];
    stream.read_exact(&mut header)?;
    let body_len = u16::from_be_bytes([header[1], header[2]]) as usize;
    let mut body = vec![0u8; body_len];
    stream.read_exact(&mut body)?;
    Ok((header[0], body))
}

pub enum Resolution {
    Hit(Vec<u8>),
    Miss,
}

/// Blocking client used inside compiler processes. One connection per
/// request keeps it stateless and robust; unix-socket connects are tens of
/// microseconds.
pub struct ProxyClient {
    pub socket_path: String,
}

impl ProxyClient {
    fn connect(&self) -> std::io::Result<UnixStream> {
        let stream = UnixStream::connect(&self.socket_path)?;
        stream.set_read_timeout(Some(Duration::from_secs(120)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;
        Ok(stream)
    }

    pub fn resolve(&self, cas_path: &str, instance: &str, key: &[u8]) -> Result<Resolution, String> {
        let mut stream = self.connect().map_err(|e| format!("proxy connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_RESOLVE,
                cas_path: cas_path.to_string(),
                instance: instance.to_string(),
                payload: key.to_vec(),
            },
        )
        .map_err(|e| format!("proxy send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("proxy recv: {e}"))?;
        match status {
            STATUS_HIT => Ok(Resolution::Hit(body)),
            STATUS_MISS => Ok(Resolution::Miss),
            _ => Err(format!("proxy error: {}", String::from_utf8_lossy(&body))),
        }
    }

    /// Best-effort notice that the on-disk CAS at `cas_path` was pruned in place,
    /// so the proxy should drop its in-memory marks for it. No instance is needed
    /// (invalidation is path-scoped); the proxy no-ops if it holds no state.
    pub fn invalidate(&self, cas_path: &str) -> Result<(), String> {
        let mut stream = self.connect().map_err(|e| format!("proxy connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_INVALIDATE,
                cas_path: cas_path.to_string(),
                instance: String::new(),
                payload: Vec::new(),
            },
        )
        .map_err(|e| format!("proxy send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("proxy recv: {e}"))?;
        if status == STATUS_HIT {
            Ok(())
        } else {
            Err(format!("proxy invalidate: {}", String::from_utf8_lossy(&body)))
        }
    }

    pub fn publish(&self, cas_path: &str, instance: &str, record_path: &str) -> Result<(), String> {
        let mut stream = self.connect().map_err(|e| format!("proxy connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_PUBLISH,
                cas_path: cas_path.to_string(),
                instance: instance.to_string(),
                payload: record_path.as_bytes().to_vec(),
            },
        )
        .map_err(|e| format!("proxy send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("proxy recv: {e}"))?;
        if status == STATUS_HIT {
            Ok(())
        } else {
            Err(format!("proxy publish: {}", String::from_utf8_lossy(&body)))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round_trip(request: &Request) -> Request {
        let (mut writer, mut reader) = UnixStream::pair().unwrap();
        write_request(&mut writer, request).unwrap();
        read_request(&mut reader).unwrap()
    }

    #[test]
    fn request_round_trips_with_declared_instance() {
        let read = round_trip(&Request {
            version: PROTOCOL_VERSION,
            op: OP_RESOLVE,
            cas_path: "/dd/App-abc/CompilationCache.noindex/plugin".to_string(),
            instance: "acme/app".to_string(),
            payload: vec![0xde, 0xad, 0xbe, 0xef],
        });
        assert_eq!(read.version, PROTOCOL_VERSION);
        assert_eq!(read.op, OP_RESOLVE);
        assert_eq!(read.cas_path, "/dd/App-abc/CompilationCache.noindex/plugin");
        assert_eq!(read.instance, "acme/app");
        assert_eq!(read.payload, vec![0xde, 0xad, 0xbe, 0xef]);
    }

    #[test]
    fn request_round_trips_with_empty_instance() {
        // The Xcode ⌘B case: no CLI env, so the plugin declares no instance and
        // the proxy must still parse the frame (and fall back to its registry).
        let read = round_trip(&Request {
            version: PROTOCOL_VERSION,
            op: OP_PUBLISH,
            cas_path: "/dd/App-abc".to_string(),
            instance: String::new(),
            payload: b"/spool/record".to_vec(),
        });
        assert_eq!(read.op, OP_PUBLISH);
        assert_eq!(read.cas_path, "/dd/App-abc");
        assert!(read.instance.is_empty());
        assert_eq!(read.payload, b"/spool/record");
    }
}
