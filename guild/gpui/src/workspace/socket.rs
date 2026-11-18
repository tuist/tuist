//! The presence WebSocket the core's `Presence` drives. Each connection runs
//! on its own thread, which buffers text frames and writes queued ones, so
//! neither the UI thread nor a poll ever waits on the network.
use std::io::ErrorKind;
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex, PoisonError};
use std::thread;
use std::time::Duration;

use tuist_app_core::Socket;
use tungstenite::client::IntoClientRequest;
use tungstenite::handshake::client::Request;
use tungstenite::http::HeaderValue;
use tungstenite::stream::MaybeTlsStream;
use tungstenite::{Message, WebSocket as Connection};
use url::Url;

const CLOSED: &str = "The connection closed";
/// Connecting and the handshake give up after this long.
const CONNECT: Duration = Duration::from_secs(10);
/// How long a read waits before the thread writes what is queued.
const TICK: Duration = Duration::from_millis(50);

#[derive(Default)]
struct Inbox {
    frames: Vec<String>,
    closed: bool,
}

struct Open {
    outbox: Sender<String>,
    inbox: Arc<Mutex<Inbox>>,
}

/// At most one connection at a time; opening another, closing or dropping
/// it ends the previous one's thread.
#[derive(Default)]
pub struct WebSocket {
    open: Option<Open>,
}

impl Socket for WebSocket {
    fn open(&mut self, url: &Url, protocols: &[String]) -> Result<(), &'static str> {
        self.close();
        let mut request = url
            .as_str()
            .into_client_request()
            .map_err(|_| "Invalid server")?;
        // The second protocol is the bearer token: never log the request.
        if !protocols.is_empty() {
            let protocols =
                HeaderValue::from_str(&protocols.join(", ")).map_err(|_| "Invalid credentials")?;
            request
                .headers_mut()
                .insert("Sec-WebSocket-Protocol", protocols);
        }
        let (outbox, outgoing) = mpsc::channel();
        let inbox = Arc::new(Mutex::new(Inbox::default()));
        let shared = inbox.clone();
        thread::Builder::new()
            .name("presence-socket".into())
            .spawn(move || {
                run(request, &outgoing, &shared);
                lock(&shared).closed = true;
            })
            .map_err(|_| "Couldn't connect")?;
        self.open = Some(Open { outbox, inbox });
        Ok(())
    }

    /// Queues `text`; it is written once the connection is up.
    fn send(&mut self, text: &str) -> Result<(), &'static str> {
        let open = self.open.as_ref().ok_or(CLOSED)?;
        if lock(&open.inbox).closed {
            return Err(CLOSED);
        }
        open.outbox.send(text.to_owned()).map_err(|_| CLOSED)
    }

    fn read(&mut self) -> Result<(Vec<String>, bool), &'static str> {
        let Some(open) = &self.open else {
            return Ok((Vec::new(), true));
        };
        let mut inbox = lock(&open.inbox);
        Ok((std::mem::take(&mut inbox.frames), inbox.closed))
    }

    /// Dropping the queue tells the thread to say goodbye and stop.
    fn close(&mut self) {
        self.open = None;
    }
}

fn lock(inbox: &Mutex<Inbox>) -> std::sync::MutexGuard<'_, Inbox> {
    inbox.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Connects, then alternates between reading with a short timeout and
/// writing what was queued, until either side closes.
fn run(request: Request, outgoing: &Receiver<String>, inbox: &Mutex<Inbox>) -> Option<()> {
    let uri = request.uri();
    let host = uri.host()?.trim_start_matches('[').trim_end_matches(']');
    let port = uri
        .port_u16()
        .unwrap_or(if uri.scheme_str() == Some("wss") {
            443
        } else {
            80
        });
    let stream = (host, port)
        .to_socket_addrs()
        .ok()?
        .find_map(|address| TcpStream::connect_timeout(&address, CONNECT).ok())?;
    stream.set_read_timeout(Some(CONNECT)).ok()?;
    stream.set_write_timeout(Some(CONNECT)).ok()?;
    let (mut socket, _) = tungstenite::client_tls_with_config(request, stream, None, None).ok()?;
    tcp(&socket)?.set_read_timeout(Some(TICK)).ok()?;
    loop {
        loop {
            match outgoing.try_recv() {
                Ok(text) => socket.send(Message::text(text)).ok()?,
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    let _ = socket.close(None);
                    let _ = socket.flush();
                    return None;
                }
            }
        }
        match socket.read() {
            Ok(Message::Text(text)) => lock(inbox).frames.push(text.to_string()),
            Ok(_) => {}
            Err(tungstenite::Error::Io(error))
                if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) =>
            {
                // Sends replies to pings the read queued.
                let _ = socket.flush();
            }
            Err(_) => return None,
        }
    }
}

fn tcp(socket: &Connection<MaybeTlsStream<TcpStream>>) -> Option<&TcpStream> {
    match socket.get_ref() {
        MaybeTlsStream::Plain(stream) => Some(stream),
        MaybeTlsStream::Rustls(stream) => Some(&stream.sock),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::time::Instant;
    use tungstenite::handshake::server::{Request as Upgrade, Response};

    /// Reads until `done` holds or a few seconds pass.
    fn read_until(
        socket: &mut WebSocket,
        mut done: impl FnMut(&[String], bool) -> bool,
    ) -> (Vec<String>, bool) {
        let (mut frames, deadline) = (Vec::new(), Instant::now() + Duration::from_secs(5));
        loop {
            let (more, closed) = socket.read().unwrap();
            frames.extend(more);
            if done(&frames, closed) || Instant::now() > deadline {
                return (frames, closed);
            }
            thread::sleep(Duration::from_millis(10));
        }
    }

    #[test]
    fn offers_the_protocols_and_exchanges_text_frames_without_blocking() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut offered = String::new();
            // tungstenite's callback signature fixes the error type.
            #[allow(clippy::result_large_err)]
            let callback = |request: &Upgrade, mut response: Response| {
                offered = request.headers()["Sec-WebSocket-Protocol"]
                    .to_str()
                    .unwrap()
                    .to_owned();
                response.headers_mut().insert(
                    "Sec-WebSocket-Protocol",
                    HeaderValue::from_static("phoenix"),
                );
                Ok(response)
            };
            let mut socket = tungstenite::accept_hdr(stream, callback).unwrap();
            socket.send(Message::text("one")).unwrap();
            socket.send(Message::binary(vec![1, 2])).unwrap();
            socket.send(Message::text("two")).unwrap();
            let received = socket.read().unwrap();
            socket.close(None).unwrap();
            while socket.read().is_ok() {}
            (offered, received)
        });

        let mut socket = WebSocket::default();
        let url = Url::parse(&format!("ws://127.0.0.1:{port}/socket/websocket")).unwrap();
        let protocols = [
            "phoenix".to_owned(),
            "base64url.bearer.phx.c2VjcmV0".to_owned(),
        ];
        socket.open(&url, &protocols).unwrap();
        // Queued before the handshake finishes, written after it.
        socket
            .send(r#"["1","1","presence:tuist","phx_join",{}]"#)
            .unwrap();

        let (frames, closed) = read_until(&mut socket, |_, closed| closed);
        assert_eq!(frames, ["one", "two"], "binary frames are skipped");
        assert!(closed);
        assert!(socket.send("late").is_err());

        let (offered, received) = server.join().unwrap();
        assert_eq!(offered, "phoenix, base64url.bearer.phx.c2VjcmV0");
        assert_eq!(
            received,
            Message::text(r#"["1","1","presence:tuist","phx_join",{}]"#)
        );
    }

    #[test]
    fn closing_says_goodbye_to_the_server() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let server = thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut socket = tungstenite::accept(stream).unwrap();
            socket.read().unwrap()
        });

        let mut socket = WebSocket::default();
        let url = Url::parse(&format!("ws://127.0.0.1:{port}/")).unwrap();
        socket.open(&url, &[]).unwrap();
        socket.close();
        assert!(matches!(server.join().unwrap(), Message::Close(_)));
        assert_eq!(socket.read().unwrap(), (Vec::new(), true));
    }

    #[test]
    fn a_refused_connection_reads_as_closed() {
        let port = TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let mut socket = WebSocket::default();
        let url = Url::parse(&format!("ws://127.0.0.1:{port}/")).unwrap();
        socket.open(&url, &["phoenix".to_owned()]).unwrap();
        let (frames, closed) = read_until(&mut socket, |_, closed| closed);
        assert!(frames.is_empty() && closed);
    }
}
