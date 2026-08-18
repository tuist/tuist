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
//! value llcas digest; the value graph materializes into the local CAS in the
//! background — a consumer's demand load that outruns it self-heals through
//! FETCH_OBJECT), status 0 = definitive miss, status 2 = proxy error (treat
//! as miss).
//! PUBLISH (op 2): payload = utf8 path of a write-ahead publication record.
//! status 1 = accepted (publication proceeds asynchronously).
//! FETCH_OBJECT (op 4): payload = llcas object digest bytes. Blocks until the
//! object is on disk (fetching it from the remote if the background
//! materializer has not stored it yet). status 1 = present, status 0 = the
//! proxy has no way to produce it (treat as not found).
//! DRAIN (op 5): payload = u32 big-endian milliseconds the caller will wait
//! (absent/zero = the proxy's default). Blocks until every publication this
//! machine recorded for `cas_path` has reached the remote. status 1 = drained,
//! status 0 = records remain (body = how many), status 2 = the proxy could not
//! run it. Asked by a runner's teardown before the CAS store it covers is
//! promoted as an account's cache master; see `Proxy::drain_publications`.
//! BACKED (op 6): payload = action key digest bytes. Asks whether the proxy
//! can produce the key's whole closure, for a hit the plugin already has
//! locally. status 1 = yes (fetch instructions are now registered), status 0 =
//! the remote definitively does not hold this key, status 2 = cannot tell.
//! Only 0 is actionable; the plugin serves the local hit on 1 and on 2, so a
//! proxy that predates this op (its dispatch answers `bad op` with status 2)
//! leaves behaviour unchanged. That is why adding it needs no version bump:
//! the frame layout is untouched and the new op degrades to the old answer.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

/// Bumped on any incompatible change to the frame layout below — or to its
/// semantics: v2 resolves reply before the value graph is materialized, which
/// is only safe with a client that self-heals demand loads via FETCH_OBJECT.
/// The proxy rejects a mismatched version (→ the plugin degrades to a local
/// miss) instead of misparsing, so a stale proxy left running across a CLI
/// upgrade can't corrupt a build.
pub const PROTOCOL_VERSION: u8 = 2;

pub const OP_RESOLVE: u8 = 1;
pub const OP_PUBLISH: u8 = 2;
/// The on-disk CAS at `cas_path` was pruned/emptied in place (Xcode's size
/// management calls `llcas_cas_prune_ondisk_data`), removing objects without
/// recreating the directory. The proxy's directory-identity wipe check can't
/// see that, so the plugin tells it to drop the path's in-memory known-local /
/// resolved marks, which would otherwise skip re-fetching the pruned blobs.
pub const OP_INVALIDATE: u8 = 3;
/// Demand fetch of one llcas object the background materializer has not stored
/// yet (or that a prune removed). Runs on compiler worker threads, never on the
/// build engine's serial task-setup path, so it may block on the remote.
pub const OP_FETCH_OBJECT: u8 = 4;
/// Wait for this path's spooled publications to reach the remote. Added WITHOUT
/// a `PROTOCOL_VERSION` bump, deliberately: the frame layout is untouched, and a
/// proxy that predates the op answers `bad op` through the STATUS_ERROR its
/// caller already has to handle — which the caller reads as "cannot ask" and
/// falls back to watching the spool directory itself. Bumping the version
/// instead would make a stale launchd proxy reject every request, from every
/// build on the machine, until it restarts.
pub const OP_DRAIN: u8 = 5;
/// Backing check for an action-cache hit the plugin found in the local store.
/// Runs on the build engine's serial task-setup path, so the proxy answers it
/// from the instance snapshot wherever it can and only pays a per-key lookup
/// for keys the snapshot lacks.
///
/// 6 rather than 5: DRAIN landed on main first and shipped with that number.
/// Two additive ops sharing a value is the one merge outcome the `bad op`
/// fallback cannot save — a proxy would read one as the other and answer with
/// a status the caller trusts, so the numbers must stay distinct even though
/// neither op needed a version bump on its own.
pub const OP_BACKED: u8 = 6;

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

/// Whether the proxy can produce the closure behind a local action-cache hit.
///
/// `Unknown` is the safe answer and covers every case where the proxy has not
/// actually looked: no routable instance, no snapshot to make an absence mean
/// anything, a transport failure, or a proxy too old to know the op. Only
/// `Unbacked` — the remote answering a definitive miss for the key — is
/// evidence, and it is the only variant that changes what the plugin serves.
///
/// `Backed` carries the value digest the remote holds, because the instructions
/// the check registered describe THAT graph. A remote value that differs from
/// the local association's (a recompile that was not byte-reproducible) backs a
/// different closure than the one about to be served, so the caller compares
/// rather than trusting the verdict alone.
pub enum Backing {
    Backed(Vec<u8>),
    Unbacked,
    Unknown,
}

/// Blocking client used inside compiler processes. One connection per
/// request keeps it stateless and robust; unix-socket connects are tens of
/// microseconds.
pub struct ProxyClient {
    pub socket_path: String,
}

/// How much longer than the drain it asked for a client waits on the reply, so
/// a proxy that spends its whole budget still gets to answer instead of the
/// read timing out on a drain that IS running.
const DRAIN_READ_GRACE: Duration = Duration::from_secs(30);

impl ProxyClient {
    fn connect(&self) -> std::io::Result<UnixStream> {
        self.connect_with_read_timeout(Duration::from_secs(120))
    }

    fn connect_with_read_timeout(&self, read_timeout: Duration) -> std::io::Result<UnixStream> {
        let stream = UnixStream::connect(&self.socket_path)?;
        stream.set_read_timeout(Some(read_timeout))?;
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

    /// Asks whether the proxy can produce the closure named by `key`, for an
    /// association the local store already holds. Never fails: anything short
    /// of a definitive remote miss reads as `Unknown`, because this decides
    /// whether a cache hit is served and a proxy hiccup must never cost a
    /// recompile.
    pub fn backed(&self, cas_path: &str, instance: &str, key: &[u8]) -> Backing {
        let Ok(mut stream) = self.connect() else {
            return Backing::Unknown;
        };
        let sent = write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_BACKED,
                cas_path: cas_path.to_string(),
                instance: instance.to_string(),
                payload: key.to_vec(),
            },
        );
        if sent.is_err() {
            return Backing::Unknown;
        }
        match read_response(&mut stream) {
            Ok((STATUS_HIT, value)) => Backing::Backed(value),
            Ok((STATUS_MISS, _)) => Backing::Unbacked,
            _ => Backing::Unknown,
        }
    }

    /// Blocks until the proxy has `digest`'s object in the local CAS (present,
    /// mid-materialization, or fetched on demand). Hit = present now; Miss =
    /// the proxy cannot produce it.
    pub fn fetch_object(
        &self,
        cas_path: &str,
        instance: &str,
        digest: &[u8],
    ) -> Result<bool, String> {
        let mut stream = self.connect().map_err(|e| format!("proxy connect: {e}"))?;
        write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_FETCH_OBJECT,
                cas_path: cas_path.to_string(),
                instance: instance.to_string(),
                payload: digest.to_vec(),
            },
        )
        .map_err(|e| format!("proxy send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("proxy recv: {e}"))?;
        match status {
            STATUS_HIT => Ok(true),
            STATUS_MISS => Ok(false),
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

    /// Blocks until the proxy reports every publication it holds for `cas_path`
    /// has reached the remote, or until it gives up at `timeout`.
    ///
    /// `Ok(0)` is drained; `Ok(n)` is n records the remote never received; an
    /// `Err` is a proxy that could not answer at all (nothing listening, or one
    /// old enough not to know the op). The caller must keep those three apart:
    /// only the first says the local store's associations are backed.
    pub fn drain(
        &self,
        cas_path: &str,
        instance: &str,
        timeout: Duration,
    ) -> Result<usize, String> {
        let mut stream = self
            .connect_with_read_timeout(timeout + DRAIN_READ_GRACE)
            .map_err(|e| format!("proxy connect: {e}"))?;
        let millis = u32::try_from(timeout.as_millis()).unwrap_or(u32::MAX);
        write_request(
            &mut stream,
            &Request {
                version: PROTOCOL_VERSION,
                op: OP_DRAIN,
                cas_path: cas_path.to_string(),
                instance: instance.to_string(),
                payload: millis.to_be_bytes().to_vec(),
            },
        )
        .map_err(|e| format!("proxy send: {e}"))?;
        let (status, body) = read_response(&mut stream).map_err(|e| format!("proxy recv: {e}"))?;
        match status {
            STATUS_HIT => Ok(0),
            // An unparseable count still means something is owed, so it must not
            // round down to drained.
            STATUS_MISS => Ok(String::from_utf8_lossy(&body).parse().unwrap_or(1)),
            _ => Err(format!("proxy error: {}", String::from_utf8_lossy(&body))),
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

    /// Every op must have its own number, and this is not the pedantry it looks
    /// like: DRAIN and BACKED were written on separate branches, both reasoned
    /// correctly that a purely additive op needs no `PROTOCOL_VERSION` bump, and
    /// both took 5. The merge that brought them together auto-resolved cleanly —
    /// two constants with different names on different lines — and compiled.
    ///
    /// That is the one collision the `bad op` fallback cannot absorb. A proxy
    /// reads the number, not the name, so it would have answered a BACKED with a
    /// DRAIN's result and vice versa, both through a status the caller trusts.
    /// The version byte would not have caught it either, since neither op
    /// changed the frame layout. So the guard belongs here, in a test, rather
    /// than in the reviewer's attention.
    #[test]
    fn every_op_has_a_distinct_number() {
        let ops = [
            ("RESOLVE", OP_RESOLVE),
            ("PUBLISH", OP_PUBLISH),
            ("INVALIDATE", OP_INVALIDATE),
            ("FETCH_OBJECT", OP_FETCH_OBJECT),
            ("DRAIN", OP_DRAIN),
            ("BACKED", OP_BACKED),
        ];
        for (i, (name, op)) in ops.iter().enumerate() {
            for (other_name, other_op) in &ops[i + 1..] {
                assert_ne!(
                    op, other_op,
                    "{name} and {other_name} share op {op}: a proxy dispatches on the \
                     number, so one would be served as the other"
                );
            }
        }
    }

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

    /// The drain rides the SAME frame layout every other op uses, which is what
    /// let it be added without a `PROTOCOL_VERSION` bump: a proxy that does not
    /// know op 5 parses the request fine and answers `bad op`.
    #[test]
    fn a_drain_request_is_an_ordinary_frame_carrying_its_budget() {
        let read = round_trip(&Request {
            version: PROTOCOL_VERSION,
            op: OP_DRAIN,
            cas_path: "/Volumes/cache/CompilationCache.noindex/plugin".to_string(),
            instance: "acme/app".to_string(),
            payload: 120_000u32.to_be_bytes().to_vec(),
        });
        assert_eq!(read.op, OP_DRAIN);
        assert_eq!(
            read.cas_path,
            "/Volumes/cache/CompilationCache.noindex/plugin"
        );
        assert_eq!(read.payload, vec![0x00, 0x01, 0xD4, 0xC0]);
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
