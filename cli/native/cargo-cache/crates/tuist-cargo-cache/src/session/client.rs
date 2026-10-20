use super::VERSION;
use crate::config::Config;
use eyre::{Context, Result, bail};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::OsString;
#[cfg(any(unix, windows))]
use std::io::{BufRead, BufReader, Write};
#[cfg(unix)]
use std::path::{Path, PathBuf};
use tuist_cargo_cache_core::{AGENT_PROTOCOL_VERSION, AgentRequest, AgentResponse, CacheAgent};

/// Serve a persistent Cargo wrapper directly from the local store.
///
/// There is deliberately no remote access here: the short-lived process has
/// no trusted session policy or opportunity to batch transfers. Prediction
/// manifests are still persisted after every successful record so the many
/// wrapper processes in one Cargo build, and later builds, share what they
/// learn without a daemon.
pub(super) fn request_standalone_agent(requests: &[AgentRequest]) -> Result<Vec<AgentResponse>> {
    thread_local! {
        static STANDALONE_AGENT: RefCell<Option<StandaloneAgent>> = const { RefCell::new(None) };
    }

    STANDALONE_AGENT.with(|slot| {
        let mut slot = slot.borrow_mut();
        if slot.is_none() {
            let config = Config::load()?;
            let runtime = tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()?;
            *slot = Some(StandaloneAgent {
                agent: CacheAgent::new(config.store_dir(), VERSION),
                runtime,
                runs: BTreeMap::new(),
            });
        }
        let standalone = slot.as_mut().expect("standalone agent was initialized");
        let StandaloneAgent {
            agent,
            runtime,
            runs,
        } = standalone;
        runtime.block_on(async {
            let mut responses = Vec::with_capacity(requests.len());
            for request in requests.iter().cloned() {
                let (request, run_to_commit) = match request {
                    AgentRequest::FindActionPrediction { task, invocation } => {
                        let run = match runs.get(&task) {
                            Some(run) => run.clone(),
                            None => {
                                let run = agent.begin_task(&task).await?;
                                runs.insert(task.clone(), run.clone());
                                run
                            }
                        };
                        (
                            AgentRequest::FindActionPrediction {
                                task: run,
                                invocation,
                            },
                            None,
                        )
                    }
                    AgentRequest::RecordActionPrediction { task, prediction } => {
                        let run = match runs.remove(&task) {
                            Some(run) => run,
                            None => agent.begin_task(&task).await?,
                        };
                        (
                            AgentRequest::RecordActionPrediction {
                                task: run.clone(),
                                prediction,
                            },
                            Some(run),
                        )
                    }
                    request => (request, None),
                };
                let response = agent
                    .handle_requests(std::iter::once(request))
                    .await
                    .into_iter()
                    .next()
                    .expect("one request returns one response");
                let succeeded = !matches!(response, AgentResponse::Error { .. });
                responses.push(response);
                if succeeded && let Some(run) = run_to_commit {
                    agent.commit_task(&run).await?;
                }
            }
            Ok(responses)
        })
    })
}

struct StandaloneAgent {
    agent: CacheAgent,
    runtime: tokio::runtime::Runtime,
    runs: BTreeMap<String, String>,
}

#[cfg(unix)]
pub(super) fn request_agent_at(
    socket: &OsString,
    requests: &[AgentRequest],
) -> Result<Vec<AgentResponse>> {
    // One compilation asks the agent several separate questions, and paying a
    // connect plus a handshake round trip for each adds up across a warm
    // build. The protocol is strict request-response, so a connection held for
    // the life of this shim process serves them all.
    thread_local! {
        static CONNECTION: RefCell<Option<(OsString, SessionStream)>> =
            const { RefCell::new(None) };
    }
    CONNECTION.with(|slot| {
        let mut slot = slot.borrow_mut();
        if slot.as_ref().is_none_or(|(known, _)| known != socket) {
            let endpoint = socket.to_string_lossy();
            let mut stream = match endpoint.strip_prefix(super::server::FIFO_ENDPOINT_PREFIX) {
                Some(directory) => SessionStream::Fifo(connect_fifo(Path::new(directory))?),
                None => SessionStream::Socket(
                    std::os::unix::net::UnixStream::connect(Path::new(socket))
                        .wrap_err("failed to connect to the cache session")?,
                ),
            };
            sync_handshake(&mut stream)?;
            *slot = Some((socket.clone(), stream));
        }
        let (_, stream) = slot.as_mut().expect("the connection was just established");
        let responses = requests
            .iter()
            .map(|request| sync_request(stream, request))
            .collect::<Result<Vec<_>>>();
        if responses.is_err() {
            // A failed exchange leaves the stream in an unknown protocol
            // state, so the next request starts over on a fresh connection.
            *slot = None;
        }
        responses
    })
}

#[cfg(unix)]
enum SessionStream {
    Socket(std::os::unix::net::UnixStream),
    Fifo(FifoClientStream),
}

#[cfg(unix)]
impl std::io::Read for SessionStream {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Self::Socket(stream) => stream.read(buffer),
            Self::Fifo(stream) => stream.read(buffer),
        }
    }
}

#[cfg(unix)]
impl std::io::Write for SessionStream {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        match self {
            Self::Socket(stream) => stream.write(buffer),
            Self::Fifo(stream) => stream.write(buffer),
        }
    }

    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Self::Socket(stream) => stream.flush(),
            Self::Fifo(stream) => stream.flush(),
        }
    }
}

#[cfg(unix)]
struct FifoClientStream {
    reader: std::fs::File,
    writer: std::fs::File,
    directory: PathBuf,
}

#[cfg(unix)]
impl std::io::Read for FifoClientStream {
    fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
        self.reader.read(buffer)
    }
}

#[cfg(unix)]
impl std::io::Write for FifoClientStream {
    fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
        self.writer.write(buffer)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.writer.flush()
    }
}

#[cfg(unix)]
impl Drop for FifoClientStream {
    fn drop(&mut self) {
        cleanup_fifo_client(&self.directory);
    }
}

#[cfg(unix)]
fn connect_fifo(server: &Path) -> Result<FifoClientStream> {
    use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};

    let name = format!(
        "{}{}-{}",
        super::server::FIFO_CLIENT_PREFIX,
        std::process::id(),
        crate::util::random_string(12)
    );
    let preparing = server.join(format!(".{name}"));
    let directory = server.join(name);
    std::fs::create_dir(&preparing)?;
    std::fs::set_permissions(&preparing, std::fs::Permissions::from_mode(0o700))?;
    let requests = preparing.join(super::server::FIFO_REQUESTS);
    let responses = preparing.join(super::server::FIFO_RESPONSES);
    if let Err(error) =
        super::server::create_fifo(&requests).and_then(|()| super::server::create_fifo(&responses))
    {
        cleanup_fifo_client(&preparing);
        return Err(error).wrap_err("failed to create FIFO cache session channels");
    }
    let reader = match std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(&responses)
    {
        Ok(reader) => reader,
        Err(error) => {
            cleanup_fifo_client(&preparing);
            return Err(error).wrap_err("failed to open the FIFO cache response channel");
        }
    };
    if let Err(error) = std::fs::rename(&preparing, &directory) {
        cleanup_fifo_client(&preparing);
        return Err(error).wrap_err("failed to publish FIFO cache session channels");
    }

    let deadline = std::time::Instant::now() + super::server::FIFO_CONNECT_DEADLINE;
    let writer = loop {
        match std::fs::OpenOptions::new()
            .write(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(directory.join(super::server::FIFO_REQUESTS))
        {
            Ok(writer) => break writer,
            Err(error)
                if std::time::Instant::now() < deadline
                    && (error.kind() == std::io::ErrorKind::NotFound
                        || error.raw_os_error() == Some(libc::ENXIO)) =>
            {
                std::thread::sleep(std::time::Duration::from_millis(2));
            }
            Err(error) => {
                cleanup_fifo_client(&directory);
                return Err(error).wrap_err("failed to open the FIFO cache request channel");
            }
        }
    };
    if let Err(error) = std::fs::write(directory.join(super::server::FIFO_READY), b"") {
        cleanup_fifo_client(&directory);
        return Err(error).wrap_err("failed to finish the FIFO cache session handshake");
    }
    while !directory.join(super::server::FIFO_ACCEPTED).exists() {
        if std::time::Instant::now() >= deadline {
            cleanup_fifo_client(&directory);
            eyre::bail!("timed out waiting for the FIFO cache session");
        }
        std::thread::sleep(std::time::Duration::from_millis(2));
    }
    if let Err(error) =
        super::server::set_blocking(&reader).and_then(|()| super::server::set_blocking(&writer))
    {
        cleanup_fifo_client(&directory);
        return Err(error).wrap_err("failed to configure FIFO cache session channels");
    }
    Ok(FifoClientStream {
        reader,
        writer,
        directory,
    })
}

#[cfg(unix)]
fn cleanup_fifo_client(directory: &Path) {
    let _ = std::fs::remove_file(directory.join(super::server::FIFO_READY));
    let _ = std::fs::remove_file(directory.join(super::server::FIFO_ACCEPTED));
    let _ = std::fs::remove_file(directory.join(super::server::FIFO_REQUESTS));
    let _ = std::fs::remove_file(directory.join(super::server::FIFO_RESPONSES));
    let _ = std::fs::remove_dir(directory);
}

#[cfg(windows)]
pub(super) fn request_agent_at(
    socket: &OsString,
    requests: &[AgentRequest],
) -> Result<Vec<AgentResponse>> {
    // Match Unix: one compiler invocation asks several separate questions,
    // and reconnecting to the named pipe plus rebuilding a Tokio runtime and
    // repeating the handshake for every one is particularly expensive on
    // Windows. A thread-local connection lives for this short-lived shim
    // process and is discarded after any failed exchange.
    thread_local! {
        static CONNECTION: RefCell<Option<(OsString, WindowsConnection)>> =
            const { RefCell::new(None) };
    }
    CONNECTION.with(|slot| {
        let mut slot = slot.borrow_mut();
        if slot.as_ref().is_none_or(|(known, _)| known != socket) {
            *slot = Some((socket.clone(), WindowsConnection::connect(socket)?));
        }
        let (_, connection) = slot.as_mut().expect("the connection was just established");
        let responses = requests
            .iter()
            .map(|request| connection.request(request))
            .collect::<Result<Vec<_>>>();
        if responses.is_err() {
            // A failed exchange leaves the stream in an unknown protocol
            // state, so the next request starts over on a fresh connection.
            *slot = None;
        }
        responses
    })
}

#[cfg(windows)]
struct WindowsConnection {
    stream: std::fs::File,
}

#[cfg(windows)]
impl WindowsConnection {
    fn connect(socket: &OsString) -> Result<Self> {
        let endpoint = socket.to_string_lossy().into_owned();
        let mut stream = connect_pipe(&endpoint)?;
        sync_handshake(&mut stream)?;
        Ok(Self { stream })
    }

    fn request(&mut self, request: &AgentRequest) -> Result<AgentResponse> {
        sync_request(&mut self.stream, request)
    }
}

/// Open the agent's pipe, waiting out the instances that are already busy.
///
/// The agent keeps one spare instance and creates the next only after accepting,
/// so the rustc processes cargo runs in parallel routinely arrive to a busy
/// pipe. Without this they would fall back to uncached compiles.
#[cfg(windows)]
fn connect_pipe(endpoint: &str) -> Result<std::fs::File> {
    use std::time::Instant;
    use windows_sys::Win32::Foundation::ERROR_PIPE_BUSY;

    const RETRY_DEADLINE: std::time::Duration = std::time::Duration::from_secs(10);
    const RETRY_DELAY: std::time::Duration = std::time::Duration::from_millis(5);

    let deadline = Instant::now() + RETRY_DEADLINE;
    loop {
        match std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(endpoint)
        {
            Ok(client) => return Ok(client),
            Err(error)
                if error.raw_os_error() == Some(ERROR_PIPE_BUSY as i32)
                    && Instant::now() < deadline => {}
            Err(error) => {
                return Err(error).wrap_err("failed to connect to the cache session");
            }
        }
        std::thread::sleep(RETRY_DELAY);
    }
}

#[cfg(any(unix, windows))]
fn sync_handshake(stream: &mut (impl std::io::Read + Write)) -> Result<()> {
    let request = AgentRequest::Hello {
        protocol: AGENT_PROTOCOL_VERSION,
        client_version: VERSION.into(),
    };
    write_request_line(stream, &request)?;
    let mut response = String::new();
    BufReader::new(&mut *stream).read_line(&mut response)?;
    validate_handshake_response(&response)
}

#[cfg(any(unix, windows))]
fn sync_request(
    stream: &mut (impl std::io::Read + Write),
    request: &AgentRequest,
) -> Result<AgentResponse> {
    write_request_line(stream, request)?;
    let mut response = String::new();
    BufReader::new(&mut *stream).read_line(&mut response)?;
    Ok(serde_json::from_str(&response)?)
}

/// Send one request as a single write.
///
/// Serializing straight onto the socket emits a syscall per JSON fragment,
/// and a prediction payload has thousands of them, each waking the agent's
/// reader. The encoded line is assembled first so the kernel sees it once.
#[cfg(any(unix, windows))]
fn write_request_line(stream: &mut impl Write, request: &AgentRequest) -> Result<()> {
    let mut encoded = serde_json::to_vec(request)?;
    encoded.push(b'\n');
    stream.write_all(&encoded)?;
    stream.flush()?;
    Ok(())
}

pub(super) fn validate_handshake_response(response: &str) -> Result<()> {
    match serde_json::from_str(response)? {
        AgentResponse::Hello {
            protocol,
            agent_version,
        } if protocol == AGENT_PROTOCOL_VERSION && agent_version == VERSION => Ok(()),
        AgentResponse::Error { message } => bail!(message),
        _ => bail!("the cache agent returned an incompatible handshake"),
    }
}
