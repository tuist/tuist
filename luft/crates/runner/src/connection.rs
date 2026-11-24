//! The daemon's connection to Tuist: it long-polls
//! `POST <server>/api/thread-runner/poll` with what it allows, runs each
//! operation it receives on its own thread, and posts the answer to
//! `/api/thread-runner/requests/<id>/response`.
//!
//! HTTPS goes through the system `curl` (macOS, most Linux distributions and
//! Windows 10 and later ship it), which uses the platform's trust store and
//! keeps the daemon free of a TLS stack. The secret is in a private curl
//! config file, never on a command line other processes can read.
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use crate::config::Config;
use crate::ops;

const POLL_WAIT_MS: u64 = 25_000;

/// The requests this daemon received and hasn't delivered an answer for yet.
/// Each poll lists them, so the server hands out again only what it claimed
/// for a poll that never arrived (the network dropped, the Mac slept), never a
/// request that ran and whose answer is still on its way.
static IN_FLIGHT: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());

fn in_flight() -> std::sync::MutexGuard<'static, Vec<String>> {
    IN_FLIGHT
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
}

/// The same list on disk, so a restarted daemon knows what its predecessor
/// was running: it answers those with an error instead of letting the server
/// hand them out again, because running a command twice is worse than
/// reporting it lost.
fn journal_file(state: &Path) -> PathBuf {
    state.join("in-flight.json")
}

fn track(state: &Path, id: &str, running: bool) {
    let mut list = in_flight();
    if running {
        list.push(id.to_string());
    } else if let Some(index) = list.iter().position(|other| other == id) {
        list.swap_remove(index);
    }
    // Written under the lock, so concurrent changes land in order.
    let bytes = serde_json::to_vec(&*list).unwrap_or_default();
    if let Err(error) = write_private(&journal_file(state), &bytes) {
        eprintln!("Could not record the running requests: {error}");
    }
}

/// Requests a previous daemon received and never answered.
fn orphaned(state: &Path) -> Vec<String> {
    std::fs::read(journal_file(state))
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<String>>(&bytes).ok())
        .unwrap_or_default()
        .into_iter()
        .filter(|id| valid_id(id))
        .collect()
}

fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-')
}

/// Whether an operation is running, for the status's `busy`.
pub fn busy() -> bool {
    !in_flight().is_empty()
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Connection {
    /// The Tuist server, such as `https://tuist.dev`.
    pub server: String,
    /// The runner's ID on that server.
    pub runner_id: String,
}

fn connection_file(state: &Path) -> PathBuf {
    state.join("connection.json")
}

fn curl_config(state: &Path) -> PathBuf {
    state.join("connection.curlrc")
}

impl Connection {
    pub fn load(state: &Path) -> Option<Self> {
        let bytes = std::fs::read(connection_file(state)).ok()?;
        let connection: Self = serde_json::from_slice(&bytes).ok()?;
        curl_config(state).exists().then_some(connection)
    }

    /// Saves the connection and its secret, readable only by this user.
    pub fn save(&self, state: &Path, token: &str) -> Result<(), String> {
        let server = validate_server(&self.server)?;
        let (secret, wrapped) = if let Some(secret) = token.strip_prefix("luft_runner_") {
            (secret, true)
        } else {
            (
                token.strip_prefix("tgr_").ok_or("Invalid runner secret")?,
                false,
            )
        };
        // Luft's opaque Phoenix envelope includes dots as well as base64url.
        // Neither format may escape the quoted curl header below.
        if secret.is_empty()
            || !secret.bytes().all(|b| {
                b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || (wrapped && b == b'.')
            })
        {
            return Err("Invalid runner secret".into());
        }
        std::fs::create_dir_all(state).map_err(|error| error.to_string())?;
        write_private(
            &curl_config(state),
            format!("header = \"Authorization: Bearer {token}\"\n").as_bytes(),
        )?;
        let connection = Self {
            server,
            runner_id: self.runner_id.clone(),
        };
        write_private(
            &connection_file(state),
            &serde_json::to_vec(&connection).map_err(|error| error.to_string())?,
        )
    }

    pub fn remove(state: &Path) -> Result<(), String> {
        for path in [connection_file(state), curl_config(state)] {
            match std::fs::remove_file(&path) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.to_string()),
            }
        }
        Ok(())
    }
}

fn write_private(path: &Path, contents: &[u8]) -> Result<(), String> {
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&temporary)
        .map_err(|error| error.to_string())?;
    file.write_all(contents)
        .map_err(|error| error.to_string())?;
    drop(file);
    std::fs::rename(&temporary, path).map_err(|error| error.to_string())
}

/// HTTPS only, except a loopback server for local development.
pub fn validate_server(server: &str) -> Result<String, String> {
    let server = server.trim().trim_end_matches('/');
    let rest = server
        .strip_prefix("https://")
        .or_else(|| {
            server
                .strip_prefix("http://")
                .filter(|rest| is_loopback(rest))
        })
        .ok_or("Use an HTTPS server URL")?;
    if rest.is_empty() || rest.contains(['"', '\\', ' ', '?', '#', '@']) {
        return Err("Invalid server URL".into());
    }
    Ok(server.to_string())
}

fn is_loopback(rest: &str) -> bool {
    let host = rest.split(['/', ':']).next().unwrap_or("");
    matches!(host, "localhost" | "127.0.0.1")
}

/// What the connection last did, for `status.json`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum State {
    NotConnected,
    Connecting,
    Connected,
    Offline,
    /// The server refused the secret: the runner was removed, or its owner
    /// lost access. Registering it again from Luft fixes it.
    Unauthorized,
}

impl State {
    pub fn id(self) -> &'static str {
        match self {
            Self::NotConnected => "not_connected",
            Self::Connecting => "connecting",
            Self::Connected => "connected",
            Self::Offline => "offline",
            Self::Unauthorized => "unauthorized",
        }
    }
}

struct Response {
    status: u16,
    body: Vec<u8>,
}

fn post(state: &Path, url: &str, body: &[u8], timeout: Duration) -> Result<Response, String> {
    let mut child = Command::new(if cfg!(windows) { "curl.exe" } else { "curl" })
        // `-q` must come first: it stops curl reading the person's own
        // `~/.curlrc`, whose proxy or `insecure` settings aren't the runner's.
        .args([
            "-q",
            "--silent",
            "--show-error",
            "--proto",
            "=https,http",
            "--max-time",
        ])
        .arg(timeout.as_secs().to_string())
        .arg("--config")
        .arg(curl_config(state))
        .args([
            "--header",
            "Content-Type: application/json",
            "--request",
            "POST",
            "--data-binary",
            "@-",
        ])
        .args(["--write-out", "\n%{http_code}", url])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|error| format!("Could not run curl: {error}"))?;
    child
        .stdin
        .take()
        .ok_or("No stdin")?
        .write_all(body)
        .map_err(|error| error.to_string())?;
    let output = child
        .wait_with_output()
        .map_err(|error| error.to_string())?;
    let split = output
        .stdout
        .iter()
        .rposition(|byte| *byte == b'\n')
        .ok_or("No response")?;
    let status = std::str::from_utf8(&output.stdout[split + 1..])
        .ok()
        .and_then(|code| code.trim().parse().ok())
        .filter(|code| *code != 0)
        .ok_or("The server could not be reached")?;
    Ok(Response {
        status,
        body: output.stdout[..split].to_vec(),
    })
}

/// One long poll: reports what the runner allows and returns the operations it received.
fn poll(
    state: &Path,
    connection: &Connection,
    config: &Config,
    wait_ms: u64,
) -> Result<Vec<Value>, State> {
    let mut info = ops::handle(state, config, &json!({"op":"info"}))["result"].clone();
    info["version"] = json!(crate::VERSION);
    info["in_flight"] = json!(*in_flight());
    let url = format!(
        "{}/api/thread-runner/poll?wait_ms={wait_ms}",
        connection.server
    );
    let timeout = Duration::from_millis(wait_ms + 15_000);
    match post(state, &url, info.to_string().as_bytes(), timeout) {
        Ok(Response { status: 200, body }) => serde_json::from_slice::<Value>(&body)
            .ok()
            .and_then(|value| value["requests"].as_array().cloned())
            .ok_or(State::Offline),
        Ok(Response { status: 401, .. }) => Err(State::Unauthorized),
        _ => Err(State::Offline),
    }
}

fn answer(state: &Path, connection: &Connection, id: &str, request: &Value) {
    // Read the settings again: the person may have narrowed them since the poll.
    let config = Config::load_for_serving(state);
    let mut response = ops::handle(state, &config, request);
    if let Some(object) = response.as_object_mut() {
        object.remove("id");
    }
    deliver(state, connection, id, &response);
}

/// How long an answer is retried: past the longest operation's timeout, after
/// which the server has stopped waiting for it anyway.
const DELIVERY_LIMIT: Duration = Duration::from_secs(40 * 60);

/// Posts an answer until the server takes it (2xx), says nobody is waiting
/// for it any more (410), or refuses it for good (another 4xx). A failure that
/// may clear up (no network, a 5xx during a deploy) is retried with backoff,
/// while the request stays in flight, so it is never handed out again.
fn deliver(state: &Path, connection: &Connection, id: &str, response: &Value) {
    let url = format!(
        "{}/api/thread-runner/requests/{id}/response",
        connection.server
    );
    let body = response.to_string();
    let started = std::time::Instant::now();
    let mut wait = Duration::from_secs(1);
    loop {
        match post(state, &url, body.as_bytes(), Duration::from_secs(120)) {
            Ok(Response { status, .. }) if !retryable(status) => return,
            Ok(Response { status, .. }) => {
                eprintln!("Could not answer request {id}: HTTP {status}");
            }
            Err(error) => eprintln!("Could not answer request {id}: {error}"),
        }
        if started.elapsed() >= DELIVERY_LIMIT || Connection::load(state).is_none() {
            eprintln!("Gave up answering request {id}");
            return;
        }
        std::thread::sleep(wait);
        wait = (wait * 2).min(Duration::from_secs(30));
    }
}

fn retryable(status: u16) -> bool {
    status >= 500 || matches!(status, 408 | 429)
}

/// Runs `work` for request `id` on its own thread, tracked in flight until
/// its answer is delivered.
fn spawn_tracked(state: &Path, id: String, work: impl FnOnce(&Path, &str) + Send + 'static) {
    track(state, &id, true);
    let state = state.to_path_buf();
    std::thread::spawn(move || {
        work(&state, &id);
        track(&state, &id, false);
    });
}

/// Keeps the connection while the daemon runs, calling `report` with each
/// state change. Operations run on their own threads, so a long command does
/// not hold up the next poll.
pub fn run(state: PathBuf, report: impl Fn(State) + Send + 'static) {
    let lost = orphaned(&state);
    if let Some(connection) = Connection::load(&state) {
        for id in lost {
            let connection = connection.clone();
            spawn_tracked(&state, id, move |state, id| {
                let lost = json!({
                    "ok": false,
                    "error": "The runner restarted while this was running, so its result was lost. It was not run again.",
                });
                deliver(state, &connection, id, &lost);
            });
        }
    } else {
        let _ = std::fs::remove_file(journal_file(&state));
    }
    std::thread::spawn(move || {
        let mut backoff = Duration::from_secs(1);
        // Until a poll succeeds, poll without waiting, so the status says
        // `connected` as soon as the server answers rather than after a long poll.
        let mut connected = false;
        loop {
            let Some(connection) = Connection::load(&state) else {
                connected = false;
                report(State::NotConnected);
                std::thread::sleep(Duration::from_secs(5));
                continue;
            };
            let config = Config::load_for_serving(&state);
            let wait = if connected { POLL_WAIT_MS } else { 0 };
            match poll(&state, &connection, &config, wait) {
                Ok(requests) => {
                    connected = true;
                    report(State::Connected);
                    backoff = Duration::from_secs(1);
                    for request in requests {
                        let Some(id) = request["id"].as_str().filter(|id| valid_id(id)) else {
                            continue;
                        };
                        // Listed before the next poll, removed only once the answer is delivered.
                        let id = id.to_string();
                        let connection = connection.clone();
                        spawn_tracked(&state, id, move |state, id| {
                            answer(state, &connection, id, &request);
                        });
                    }
                }
                Err(failure) => {
                    connected = false;
                    report(failure);
                    // A refused secret will not start working by itself; check rarely.
                    let wait = if failure == State::Unauthorized {
                        Duration::from_secs(60)
                    } else {
                        backoff
                    };
                    std::thread::sleep(wait);
                    backoff = (backoff * 2).min(Duration::from_secs(30));
                }
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A server on localhost that answers each request with the next status.
    fn server(statuses: Vec<u16>) -> (String, std::sync::mpsc::Receiver<String>) {
        use std::io::{BufRead, BufReader, Read};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let address = format!("http://localhost:{}", listener.local_addr().unwrap().port());
        let (sent, received) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for status in statuses {
                let (stream, _) = listener.accept().unwrap();
                let mut reader = BufReader::new(stream);
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                let mut length = 0;
                let mut headers = String::new();
                loop {
                    let mut header = String::new();
                    reader.read_line(&mut header).unwrap();
                    if let Some(value) = header.to_ascii_lowercase().strip_prefix("content-length:")
                    {
                        length = value.trim().parse().unwrap();
                    }
                    if header.trim().is_empty() {
                        break;
                    }
                    headers.push_str(&header);
                }
                let mut body = vec![0; length];
                reader.read_exact(&mut body).unwrap();
                sent.send(format!(
                    "{} {}\n{}",
                    line.trim(),
                    String::from_utf8(body).unwrap(),
                    headers
                ))
                .unwrap();
                let mut stream = reader.into_inner();
                let body = if status == 200 {
                    r#"{"requests":[]}"#
                } else {
                    ""
                };
                write!(
                    stream,
                    "HTTP/1.1 {status} X\r\ncontent-length: {}\r\nconnection: close\r\n\r\n{body}",
                    body.len()
                )
                .unwrap();
            }
        });
        (address, received)
    }

    #[test]
    fn an_answer_is_retried_and_its_request_stays_in_flight_until_delivered() {
        let state = std::env::temp_dir().join(format!("runner-deliver-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        let (address, received) = server(vec![502, 204]);
        let connection = Connection {
            server: address,
            runner_id: "r".into(),
        };
        connection.save(&state, "tgr_secret").unwrap();
        let id = "0f0e0d0c-0000-4000-8000-000000000001".to_string();
        let (done, finished) = std::sync::mpsc::channel();
        let connection = Connection::load(&state).unwrap();
        spawn_tracked(&state, id.clone(), move |state, id| {
            deliver(state, &connection, id, &json!({"ok":true,"result":1}));
            done.send(()).unwrap();
        });

        let first = received.recv_timeout(Duration::from_secs(10)).unwrap();
        assert!(
            first.contains(&format!("/requests/{id}/response")),
            "{first}"
        );
        // The 502 didn't take it off the list the next poll reports.
        assert!(in_flight().contains(&id));
        assert_eq!(
            orphaned(&state),
            std::slice::from_ref(&id),
            "a restart would know about it"
        );

        let second = received.recv_timeout(Duration::from_secs(10)).unwrap();
        assert_eq!(first, second, "the same answer, sent again");
        finished.recv_timeout(Duration::from_secs(10)).unwrap();
        std::thread::sleep(Duration::from_millis(50));
        assert!(!in_flight().contains(&id));
        assert!(orphaned(&state).is_empty());
    }

    #[test]
    fn servers_are_https_or_loopback() {
        assert_eq!(
            validate_server("https://tuist.dev/").unwrap(),
            "https://tuist.dev"
        );
        assert_eq!(
            validate_server("http://localhost:8180").unwrap(),
            "http://localhost:8180"
        );
        assert!(validate_server("http://tuist.dev").is_err());
        assert!(
            validate_server("http://localhost.evil.com").is_err(),
            "only the loopback host itself"
        );
        assert!(validate_server("https://tuist.dev\" -o /etc/x").is_err());
        assert!(validate_server("file:///etc/passwd").is_err());
    }

    #[test]
    fn luft_credentials_survive_save_reload_poll_and_response() {
        let state = std::env::temp_dir().join(format!("runner-luft-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        // Phoenix.Token encrypts with an XCP. prefix and unpadded base64url.
        let token = "luft_runner_XCP.AbC09-_encrypted";
        let (address, received) = server(vec![200, 204]);
        let connection = Connection {
            server: address,
            runner_id: "r".into(),
        };
        connection.save(&state, token).unwrap();
        let loaded = Connection::load(&state).unwrap();
        assert_eq!(loaded, connection);
        assert!(
            poll(&state, &loaded, &Config::default(), 0)
                .unwrap()
                .is_empty()
        );
        deliver(&state, &loaded, "abc-123", &json!({"ok": true}));

        for path in [
            "/api/thread-runner/poll?wait_ms=0",
            "/api/thread-runner/requests/abc-123/response",
        ] {
            let request = received.recv_timeout(Duration::from_secs(10)).unwrap();
            assert!(
                request.starts_with(&format!("POST {path} HTTP/1.1")),
                "{request}"
            );
            assert!(
                request.contains(&format!("\r\nAuthorization: Bearer {token}\r\n")),
                "{request}"
            );
        }
        Connection::remove(&state).unwrap();
        std::fs::remove_dir_all(state).unwrap();
    }

    #[test]
    fn the_secret_is_private_and_well_formed() {
        let state = std::env::temp_dir().join(format!("runner-connection-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&state);
        let connection = Connection {
            server: "https://tuist.dev/".into(),
            runner_id: "r".into(),
        };
        for token in [
            "tgr_abc\"\nheader = x",
            "luft_runner_XCP.abc\"\nheader = x",
            "luft_runner_XCP.abc\\def",
            "luft_runner_XCP.abc\r\nheader=x",
            "luft_runner_XCP.abc def",
            "luft_runner_XCP.abc\0def",
            "luft_runner_",
            "tgr_",
            "unknown_secret",
        ] {
            assert!(
                connection.save(&state, token).is_err(),
                "accepted {token:?}"
            );
            assert!(Connection::load(&state).is_none());
        }
        connection.save(&state, "tgr_abc-_9").unwrap();
        assert_eq!(
            Connection::load(&state).unwrap().server,
            "https://tuist.dev"
        );
        assert_eq!(
            std::fs::read_to_string(curl_config(&state)).unwrap(),
            "header = \"Authorization: Bearer tgr_abc-_9\"\n"
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(curl_config(&state))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o600);
        }
        Connection::remove(&state).unwrap();
        assert!(Connection::load(&state).is_none());
    }
}
