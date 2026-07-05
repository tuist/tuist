//! Wire protocol between the plugin (inside compiler processes) and the
//! per-machine broker, over a unix domain socket.
//!
//! One request per connection, length-prefixed:
//!   request  = u8 op | u16 cas_path_len | cas_path | u16 payload_len | payload
//!   response = u8 status | u16 body_len | body
//!
//! RESOLVE (op 1): payload = action key digest bytes. status 1 = hit (body =
//! value llcas digest, materialized into the local CAS before replying),
//! status 0 = definitive miss, status 2 = broker error (treat as miss).
//! PUBLISH (op 2): payload = utf8 path of a write-ahead publication record.
//! status 1 = accepted (publication proceeds asynchronously).

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

pub const OP_RESOLVE: u8 = 1;
pub const OP_PUBLISH: u8 = 2;

pub const STATUS_MISS: u8 = 0;
pub const STATUS_HIT: u8 = 1;
pub const STATUS_ERROR: u8 = 2;

pub struct Request {
    pub op: u8,
    pub cas_path: String,
    pub payload: Vec<u8>,
}

pub fn write_request(stream: &mut UnixStream, request: &Request) -> std::io::Result<()> {
    let mut frame = Vec::with_capacity(5 + request.cas_path.len() + request.payload.len());
    frame.push(request.op);
    frame.extend_from_slice(&(request.cas_path.len() as u16).to_be_bytes());
    frame.extend_from_slice(request.cas_path.as_bytes());
    frame.extend_from_slice(&(request.payload.len() as u16).to_be_bytes());
    frame.extend_from_slice(&request.payload);
    stream.write_all(&frame)
}

pub fn read_request(stream: &mut UnixStream) -> std::io::Result<Request> {
    let mut header = [0u8; 3];
    stream.read_exact(&mut header)?;
    let op = header[0];
    let path_len = u16::from_be_bytes([header[1], header[2]]) as usize;
    let mut path = vec![0u8; path_len];
    stream.read_exact(&mut path)?;
    let mut len = [0u8; 2];
    stream.read_exact(&mut len)?;
    let payload_len = u16::from_be_bytes(len) as usize;
    let mut payload = vec![0u8; payload_len];
    stream.read_exact(&mut payload)?;
    Ok(Request {
        op,
        cas_path: String::from_utf8_lossy(&path).into_owned(),
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
pub struct BrokerClient {
    pub socket_path: String,
}

impl BrokerClient {
    fn connect(&self) -> std::io::Result<UnixStream> {
        let stream = UnixStream::connect(&self.socket_path)?;
        stream.set_read_timeout(Some(Duration::from_secs(120)))?;
        stream.set_write_timeout(Some(Duration::from_secs(10)))?;
        Ok(stream)
    }

    pub fn resolve(&self, cas_path: &str, key: &[u8]) -> Result<Resolution, String> {
        let mut stream = self.connect().map_err(|e| format!("broker connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                op: OP_RESOLVE,
                cas_path: cas_path.to_string(),
                payload: key.to_vec(),
            },
        )
        .map_err(|e| format!("broker send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("broker recv: {e}"))?;
        match status {
            STATUS_HIT => Ok(Resolution::Hit(body)),
            STATUS_MISS => Ok(Resolution::Miss),
            _ => Err(format!("broker error: {}", String::from_utf8_lossy(&body))),
        }
    }

    pub fn publish(&self, cas_path: &str, record_path: &str) -> Result<(), String> {
        let mut stream = self.connect().map_err(|e| format!("broker connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                op: OP_PUBLISH,
                cas_path: cas_path.to_string(),
                payload: record_path.as_bytes().to_vec(),
            },
        )
        .map_err(|e| format!("broker send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("broker recv: {e}"))?;
        if status == STATUS_HIT {
            Ok(())
        } else {
            Err(format!("broker publish: {}", String::from_utf8_lossy(&body)))
        }
    }
}
