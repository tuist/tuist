use std::io::{ErrorKind, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use url::Url;

use crate::Error;

const PATH: &str = "/callback";
const POLL_INTERVAL: Duration = Duration::from_millis(50);
const MAX_REQUEST_BYTES: usize = 16 * 1024;

/// A one-shot HTTP listener on 127.0.0.1 that receives the authorization
/// redirect (RFC 8252 §7.3). The port is chosen by the operating system and
/// registered with the server for this sign-in only.
pub struct LoopbackCallback {
    listener: TcpListener,
}

impl LoopbackCallback {
    pub fn bind() -> Result<Self, Error> {
        let listener =
            TcpListener::bind(("127.0.0.1", 0)).map_err(|error| Error::Io(error.to_string()))?;
        listener
            .set_nonblocking(true)
            .map_err(|error| Error::Io(error.to_string()))?;
        Ok(Self { listener })
    }

    pub fn redirect_uri(&self) -> String {
        let port = self
            .listener
            .local_addr()
            .map(|address| address.port())
            .unwrap_or_default();
        format!("http://127.0.0.1:{port}{PATH}")
    }

    /// Waits for the redirect carrying `state` and returns its code. Requests
    /// for other paths, such as a browser's favicon fetch, are answered and ignored.
    pub fn wait(
        &self,
        state: &str,
        cancelled: &AtomicBool,
        timeout: Duration,
    ) -> Result<String, Error> {
        let deadline = Instant::now() + timeout;
        loop {
            if cancelled.load(Ordering::Relaxed) {
                return Err(Error::Cancelled);
            }
            if Instant::now() >= deadline {
                return Err(Error::TimedOut);
            }
            match self.listener.accept() {
                Ok((stream, _)) => {
                    if let Some(result) = handle(stream, state) {
                        return result;
                    }
                }
                Err(error) if error.kind() == ErrorKind::WouldBlock => thread::sleep(POLL_INTERVAL),
                Err(error) => return Err(Error::Io(error.to_string())),
            }
        }
    }
}

/// `None` for requests that are not the callback.
fn handle(mut stream: TcpStream, state: &str) -> Option<Result<String, Error>> {
    let _ = stream.set_nonblocking(false);
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let Some(target) = request_target(&mut stream) else {
        respond(
            &mut stream,
            "400 Bad Request",
            "The request could not be read.",
        );
        return None;
    };
    let url = Url::parse(&format!("http://127.0.0.1{target}")).ok()?;
    if url.path() != PATH {
        respond(&mut stream, "404 Not Found", "Not found.");
        return None;
    }
    let result = callback_result(&url, state);
    match &result {
        Ok(_) => respond(
            &mut stream,
            "200 OK",
            "You're signed in to Tuist. You can close this tab and return to the app.",
        ),
        Err(error) => respond(
            &mut stream,
            "400 Bad Request",
            &format!("Sign-in failed: {error}. Return to the app and try again."),
        ),
    }
    Some(result)
}

fn callback_result(url: &Url, state: &str) -> Result<String, Error> {
    let parameter = |name: &str| {
        url.query_pairs()
            .find(|(key, _)| key == name)
            .map(|(_, value)| value.into_owned())
    };
    if parameter("state").as_deref() != Some(state) {
        return Err(Error::StateMismatch);
    }
    if let Some(error) = parameter("error") {
        return Err(Error::Denied(
            parameter("error_description").unwrap_or(error),
        ));
    }
    parameter("code")
        .filter(|code| !code.is_empty())
        .ok_or(Error::InvalidResponse)
}

/// Reads the request head and returns the target of a `GET` request line.
fn request_target(stream: &mut TcpStream) -> Option<String> {
    let mut head = Vec::new();
    let mut buffer = [0; 1024];
    while !head.windows(4).any(|window| window == b"\r\n\r\n") {
        let read = stream.read(&mut buffer).ok().filter(|read| *read > 0)?;
        head.extend_from_slice(&buffer[..read]);
        if head.len() > MAX_REQUEST_BYTES {
            return None;
        }
    }
    let line = String::from_utf8_lossy(&head).lines().next()?.to_string();
    let mut parts = line.split(' ');
    match (parts.next(), parts.next()) {
        (Some("GET"), Some(target)) if target.starts_with('/') => Some(target.to_string()),
        _ => None,
    }
}

fn respond(stream: &mut TcpStream, status: &str, message: &str) {
    let body = format!(
        "<!doctype html><html><head><meta charset=\"utf-8\"><title>Tuist</title></head>\
         <body style=\"font-family: system-ui, sans-serif; display: grid; place-items: center; height: 100vh; margin: 0\">\
         <p>{}</p></body></html>",
        message.replace('&', "&amp;").replace('<', "&lt;")
    );
    let _ = write!(
        stream,
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn get(redirect_uri: &str, target: &str) -> String {
        let port = Url::parse(redirect_uri).unwrap().port().unwrap();
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(stream, "GET {target} HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n").unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        response
    }

    #[test]
    fn ignores_other_paths_then_returns_the_code_for_the_matching_state() {
        let callback = LoopbackCallback::bind().unwrap();
        let redirect_uri = callback.redirect_uri();
        let client = thread::spawn(move || {
            let favicon = get(&redirect_uri, "/favicon.ico");
            let callback = get(&redirect_uri, "/callback?code=abc%2B1&state=s1");
            (favicon, callback)
        });
        let code = callback
            .wait("s1", &AtomicBool::new(false), Duration::from_secs(5))
            .unwrap();
        let (favicon, response) = client.join().unwrap();
        assert_eq!(code, "abc+1");
        assert!(favicon.starts_with("HTTP/1.1 404"));
        assert!(response.starts_with("HTTP/1.1 200"));
    }

    #[test]
    fn rejects_a_forged_state_even_with_a_code() {
        let callback = LoopbackCallback::bind().unwrap();
        let redirect_uri = callback.redirect_uri();
        let client = thread::spawn(move || get(&redirect_uri, "/callback?code=abc&state=other"));
        let result = callback.wait("s1", &AtomicBool::new(false), Duration::from_secs(5));
        assert_eq!(result, Err(Error::StateMismatch));
        assert!(client.join().unwrap().starts_with("HTTP/1.1 400"));
    }

    #[test]
    fn cancelling_stops_waiting() {
        let callback = LoopbackCallback::bind().unwrap();
        let cancelled = Arc::new(AtomicBool::new(true));
        assert_eq!(
            callback.wait("s1", &cancelled, Duration::from_secs(5)),
            Err(Error::Cancelled)
        );
    }
}
