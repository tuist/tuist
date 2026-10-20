#[cfg(windows)]
use eyre::Context;
use eyre::Result;
use log::debug;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tuist_cargo_cache_core::CacheAgent;

#[cfg(unix)]
pub(super) const FIFO_ENDPOINT_PREFIX: &str = "fifo:";
#[cfg(unix)]
pub(super) const FIFO_CLIENT_PREFIX: &str = "client-";
#[cfg(unix)]
pub(super) const FIFO_READY: &str = "ready";
#[cfg(unix)]
pub(super) const FIFO_ACCEPTED: &str = "accepted";
#[cfg(unix)]
pub(super) const FIFO_REQUESTS: &str = "requests";
#[cfg(unix)]
pub(super) const FIFO_RESPONSES: &str = "responses";
#[cfg(unix)]
pub(super) const FIFO_CONNECT_DEADLINE: std::time::Duration = std::time::Duration::from_secs(10);

#[cfg(unix)]
#[derive(Debug)]
struct ListenerBindError {
    path: PathBuf,
    source: std::io::Error,
}

#[cfg(unix)]
#[derive(Debug)]
struct TransportUnavailable {
    socket: ListenerBindError,
    fifo: eyre::Report,
}

#[cfg(unix)]
impl std::fmt::Display for TransportUnavailable {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "{}; FIFO fallback also failed: {:#}",
            self.socket, self.fifo
        )
    }
}

#[cfg(unix)]
impl std::error::Error for TransportUnavailable {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.socket)
    }
}

#[cfg(unix)]
impl std::fmt::Display for ListenerBindError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "failed to bind cache session listener at {}: {}",
            self.path.display(),
            self.source
        )
    }
}

#[cfg(unix)]
impl std::error::Error for ListenerBindError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        Some(&self.source)
    }
}

#[cfg(unix)]
impl ListenerBindError {
    fn unavailable(&self) -> bool {
        matches!(
            self.source.kind(),
            std::io::ErrorKind::PermissionDenied | std::io::ErrorKind::Unsupported
        )
    }
}

/// Whether session startup failed because this environment cannot bind the
/// local listener the compiler shims need.
#[cfg(unix)]
pub(crate) fn listener_unavailable(error: &eyre::Report) -> bool {
    error.chain().any(|cause| {
        cause
            .downcast_ref::<ListenerBindError>()
            .is_some_and(ListenerBindError::unavailable)
            || cause.downcast_ref::<TransportUnavailable>().is_some()
    })
}

#[cfg(windows)]
pub(crate) fn listener_unavailable(_error: &eyre::Report) -> bool {
    false
}

#[cfg(unix)]
pub(super) async fn spawn_server(
    session_dir: &Path,
    agent: CacheAgent,
    task: Arc<super::SessionTask>,
    mut shutdown: oneshot::Receiver<()>,
) -> Result<(String, JoinHandle<Result<()>>)> {
    use std::os::unix::fs::PermissionsExt as _;

    let socket = session_dir.join("cache-agent.sock");
    let listener = match tokio::net::UnixListener::bind(&socket) {
        Ok(listener) => listener,
        Err(source) => {
            let socket_error = ListenerBindError {
                path: socket,
                source,
            };
            if !socket_error.unavailable() {
                return Err(socket_error.into());
            }
            super::note(&format!(
                "tuist_cargo_cache[warning]: Unix-domain cache session listener unavailable; using FIFO transport: {socket_error}"
            ));
            return spawn_fifo_server(session_dir, agent, task, shutdown)
                .map_err(|fifo| TransportUnavailable {
                    socket: socket_error,
                    fifo,
                })
                .map_err(Into::into);
        }
    };
    std::fs::set_permissions(&socket, std::fs::Permissions::from_mode(0o600))?;
    let endpoint = socket.to_string_lossy().into_owned();
    let server = tokio::spawn(async move {
        let _cleanup = SocketCleanup(socket);
        let mut connections = tokio::task::JoinSet::new();
        let outcome = loop {
            tokio::select! {
                accepted = listener.accept() => {
                    let (stream, _) = match accepted {
                        Ok(accepted) => accepted,
                        Err(error) => break Err(eyre::Report::from(error)),
                    };
                    let agent = agent.clone();
                    let task = Arc::clone(&task);
                    connections.spawn(async move {
                        task.connected.store(true, std::sync::atomic::Ordering::Relaxed);
                        if let Err(error) = agent.handle_connection(stream).await {
                            debug!("cache agent connection failed: {error}");
                        }
                    });
                    // A build makes one connection per compilation, so finished
                    // ones are reaped as they go rather than held until shutdown.
                    while connections.try_join_next().is_some() {}
                }
                _ = &mut shutdown => break Ok(()),
            }
        };
        // A connection answers requests, and a store request queues an upload,
        // so the session has not stopped accepting work until these are done.
        while connections.join_next().await.is_some() {}
        outcome
    });
    Ok((endpoint, server))
}

/// Serve compiler processes through filesystem FIFOs when socket syscalls are
/// prohibited. Each client owns a private request/response pair, so large
/// protocol messages and concurrent compilations never share framing.
#[cfg(unix)]
fn spawn_fifo_server(
    session_dir: &Path,
    agent: CacheAgent,
    task: Arc<super::SessionTask>,
    mut shutdown: oneshot::Receiver<()>,
) -> Result<(String, JoinHandle<Result<()>>)> {
    use std::collections::HashSet;

    let directory = prepare_fifo_directory(session_dir)?;
    let endpoint = format!("{FIFO_ENDPOINT_PREFIX}{}", directory.to_string_lossy());
    let server = tokio::spawn(async move {
        let _cleanup = FifoCleanup(directory.clone());
        let mut claimed = HashSet::new();
        let mut connections = tokio::task::JoinSet::new();
        let mut poll = tokio::time::interval(std::time::Duration::from_millis(2));
        let outcome = loop {
            tokio::select! {
                _ = poll.tick() => {
                    let entries = match std::fs::read_dir(&directory) {
                        Ok(entries) => entries,
                        Err(error) => break Err(eyre::Report::from(error)),
                    };
                    for entry in entries.filter_map(std::result::Result::ok) {
                        let path = entry.path();
                        if !entry.file_type().is_ok_and(|kind| kind.is_dir())
                            || !entry.file_name().to_string_lossy().starts_with(FIFO_CLIENT_PREFIX)
                            || !claimed.insert(path.clone())
                        {
                            continue;
                        }
                        let agent = agent.clone();
                        let task = Arc::clone(&task);
                        let runtime = tokio::runtime::Handle::current();
                        let connection_path = path.clone();
                        let (finished_tx, finished_rx) = oneshot::channel();
                        let thread = std::thread::Builder::new()
                            .name("tuist_cargo_cache-fifo-session".into())
                            .spawn(move || {
                                let _cleanup = FifoCleanup(connection_path.clone());
                                let result = (|| {
                                    let (reader, writer) = accept_fifo_client(&connection_path)?;
                                    runtime.block_on(async {
                                        task.connected.store(true, std::sync::atomic::Ordering::Relaxed);
                                        let stream = tokio::io::join(
                                            BlockingFifoReader(reader),
                                            BlockingFifoWriter(writer),
                                        );
                                        if let Err(error) = agent.handle_connection(stream).await {
                                            debug!("cache agent FIFO connection failed: {error}");
                                        }
                                        Ok::<(), eyre::Report>(())
                                    })
                                })();
                                let _ = finished_tx.send(result);
                            });
                        let thread = match thread {
                            Ok(thread) => thread,
                            Err(error) => {
                                let _cleanup = FifoCleanup(path.clone());
                                debug!(
                                    "failed to start cache agent FIFO connection thread: {error}"
                                );
                                continue;
                            }
                        };
                        connections.spawn(async move {
                            let result = finished_rx.await.map_err(eyre::Report::from)?;
                            thread
                                .join()
                                .map_err(|_| eyre::eyre!("cache agent FIFO thread panicked"))?;
                            result
                        });
                    }
                    while connections.try_join_next().is_some() {}
                }
                _ = &mut shutdown => break Ok(()),
            }
        };
        while let Some(connection) = connections.join_next().await {
            if let Ok(Err(error)) = connection {
                debug!("cache agent FIFO connection failed: {error}");
            }
        }
        outcome
    });
    Ok((endpoint, server))
}

/// Create and probe the private directory advertised as the FIFO endpoint.
#[cfg(unix)]
fn prepare_fifo_directory(session_dir: &Path) -> Result<PathBuf> {
    prepare_fifo_directory_with(session_dir, create_fifo)
}

/// Prepare a FIFO endpoint using an injectable creator for deterministic tests.
#[cfg(unix)]
fn prepare_fifo_directory_with(
    session_dir: &Path,
    make_fifo: impl FnOnce(&Path) -> std::io::Result<()>,
) -> Result<PathBuf> {
    use std::os::unix::fs::PermissionsExt as _;

    let directory = session_dir.join("cache-agent-fifo");
    std::fs::create_dir(&directory)?;
    let probe = directory.join(".probe");
    let result = (|| {
        std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700))?;
        make_fifo(&probe)?;
        std::fs::remove_file(&probe)?;
        Ok::<(), std::io::Error>(())
    })();
    if let Err(error) = result {
        let _ = std::fs::remove_file(&probe);
        let _ = std::fs::remove_dir(&directory);
        return Err(error.into());
    }
    Ok(directory)
}

/// Open one client's FIFO pair after its rendezvous handshake.
#[cfg(unix)]
fn accept_fifo_client(directory: &Path) -> Result<(std::fs::File, std::fs::File)> {
    use std::os::unix::fs::OpenOptionsExt as _;

    let requests = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(directory.join(FIFO_REQUESTS))?;
    let deadline = std::time::Instant::now() + FIFO_CONNECT_DEADLINE;
    while !directory.join(FIFO_READY).exists() {
        if std::time::Instant::now() >= deadline {
            eyre::bail!("timed out waiting for a FIFO cache client");
        }
        std::thread::sleep(std::time::Duration::from_millis(2));
    }
    let responses = std::fs::OpenOptions::new()
        .write(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(directory.join(FIFO_RESPONSES))?;
    std::fs::write(directory.join(FIFO_ACCEPTED), b"")?;
    set_blocking(&requests)?;
    set_blocking(&responses)?;
    Ok((requests, responses))
}

/// A blocking FIFO request stream polled only from its dedicated OS thread.
#[cfg(unix)]
struct BlockingFifoReader(std::fs::File);

#[cfg(unix)]
impl tokio::io::AsyncRead for BlockingFifoReader {
    fn poll_read(
        self: std::pin::Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
        buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        use std::io::Read as _;

        let read = self.get_mut().0.read(buffer.initialize_unfilled());
        match read {
            Ok(read) => {
                buffer.advance(read);
                std::task::Poll::Ready(Ok(()))
            }
            Err(error) => std::task::Poll::Ready(Err(error)),
        }
    }
}

/// A blocking FIFO response stream polled only from its dedicated OS thread.
#[cfg(unix)]
struct BlockingFifoWriter(std::fs::File);

#[cfg(unix)]
impl tokio::io::AsyncWrite for BlockingFifoWriter {
    fn poll_write(
        self: std::pin::Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
        buffer: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        use std::io::Write as _;

        std::task::Poll::Ready(self.get_mut().0.write(buffer))
    }

    fn poll_flush(
        self: std::pin::Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn poll_shutdown(
        self: std::pin::Pin<&mut Self>,
        _context: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::task::Poll::Ready(Ok(()))
    }
}

#[cfg(unix)]
pub(crate) fn create_fifo(path: &Path) -> std::io::Result<()> {
    use std::os::unix::ffi::OsStrExt as _;

    let path = std::ffi::CString::new(path.as_os_str().as_bytes()).map_err(|_| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "FIFO path contains a null byte",
        )
    })?;
    // SAFETY: `path` is a live, null-terminated C string and mode contains
    // only ordinary permission bits.
    if unsafe { libc::mkfifo(path.as_ptr(), 0o600) } == 0 {
        Ok(())
    } else {
        Err(std::io::Error::last_os_error())
    }
}

#[cfg(unix)]
pub(super) fn set_blocking(file: &std::fs::File) -> std::io::Result<()> {
    use std::os::fd::AsRawFd as _;

    // SAFETY: F_GETFL and F_SETFL do not retain the valid file descriptor.
    let flags = unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) };
    if flags == -1 {
        return Err(std::io::Error::last_os_error());
    }
    if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETFL, flags & !libc::O_NONBLOCK) } == -1 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(())
}

#[cfg(unix)]
struct FifoCleanup(PathBuf);

#[cfg(unix)]
impl Drop for FifoCleanup {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(self.0.join(FIFO_READY));
        let _ = std::fs::remove_file(self.0.join(FIFO_ACCEPTED));
        let _ = std::fs::remove_file(self.0.join(FIFO_REQUESTS));
        let _ = std::fs::remove_file(self.0.join(FIFO_RESPONSES));
        let _ = std::fs::remove_dir(&self.0);
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use tuist_cargo_cache_core::{AgentRequest, AgentResponse};

    #[test]
    fn permission_and_platform_rejections_mean_the_listener_is_unavailable() {
        for kind in [
            std::io::ErrorKind::PermissionDenied,
            std::io::ErrorKind::Unsupported,
        ] {
            let error = eyre::Report::from(ListenerBindError {
                path: "/tmp/cache-agent.sock".into(),
                source: std::io::Error::from(kind),
            });
            assert!(listener_unavailable(&error));
        }
    }

    #[test]
    fn an_address_collision_remains_a_startup_error() {
        let error = eyre::Report::from(ListenerBindError {
            path: "/tmp/cache-agent.sock".into(),
            source: std::io::Error::from(std::io::ErrorKind::AddrInUse),
        });
        assert!(!listener_unavailable(&error));
    }

    #[test]
    fn a_blocked_mkfifo_prevents_publishing_the_fifo_endpoint() {
        let session = tempfile::tempdir().unwrap();
        let error = prepare_fifo_directory_with(session.path(), |_| {
            Err(std::io::Error::from(std::io::ErrorKind::PermissionDenied))
        })
        .unwrap_err();
        assert_eq!(
            error.downcast_ref::<std::io::Error>().unwrap().kind(),
            std::io::ErrorKind::PermissionDenied
        );
        assert!(!session.path().join("cache-agent-fifo").exists());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn fifo_transport_serves_the_agent_protocol() {
        let directory = tempfile::tempdir().unwrap();
        let agent = CacheAgent::new(directory.path().join("store"), super::super::VERSION);
        let task = Arc::new(super::super::SessionTask {
            identity: std::sync::OnceLock::new(),
            initialized: tokio::sync::OnceCell::new(),
            connected: std::sync::atomic::AtomicBool::new(false),
        });
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (endpoint, server) =
            spawn_fifo_server(directory.path(), agent, task, shutdown_rx).unwrap();
        let responses = std::thread::spawn(move || {
            super::super::client::request_agent_at(
                &endpoint.into(),
                &[
                    AgentRequest::RecordWarning {
                        message: "x".repeat(128 * 1024),
                    },
                    AgentRequest::RecordUnconsulted,
                ],
            )
        })
        .join()
        .unwrap()
        .unwrap();
        assert!(
            matches!(
                responses.as_slice(),
                [
                    AgentResponse::Error { message },
                    AgentResponse::UnconsultedRecorded
                ] if message == "invalid shim warning"
            ),
            "unexpected FIFO responses: {responses:?}"
        );
        shutdown_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn fifo_transport_keeps_concurrent_clients_separate() {
        let directory = tempfile::tempdir().unwrap();
        let agent = CacheAgent::new(directory.path().join("store"), super::super::VERSION);
        let observed = agent.clone();
        let task = Arc::new(super::super::SessionTask {
            identity: std::sync::OnceLock::new(),
            initialized: tokio::sync::OnceCell::new(),
            connected: std::sync::atomic::AtomicBool::new(false),
        });
        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let (endpoint, server) =
            spawn_fifo_server(directory.path(), agent, task, shutdown_rx).unwrap();
        let clients = (0..8)
            .map(|_| {
                let endpoint = endpoint.clone();
                std::thread::spawn(move || {
                    super::super::client::request_agent_at(
                        &endpoint.into(),
                        &[AgentRequest::RecordUnconsulted],
                    )
                })
            })
            .collect::<Vec<_>>();
        for client in clients {
            let responses = client.join().unwrap().unwrap();
            assert!(matches!(
                responses.as_slice(),
                [AgentResponse::UnconsultedRecorded]
            ));
        }
        shutdown_tx.send(()).unwrap();
        server.await.unwrap().unwrap();
        assert_eq!(observed.stats().unconsulted, 8);
    }
}

#[cfg(unix)]
struct SocketCleanup(PathBuf);

#[cfg(unix)]
impl Drop for SocketCleanup {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

#[cfg(windows)]
pub(super) async fn spawn_server(
    _session_dir: &Path,
    agent: CacheAgent,
    task: Arc<super::SessionTask>,
    mut shutdown: oneshot::Receiver<()>,
) -> Result<(String, JoinHandle<Result<()>>)> {
    let endpoint = format!(
        r"\\.\pipe\tuist_cargo_cache-cache-{}-{}",
        std::process::id(),
        crate::util::random_string(12)
    );
    let first_server = create_named_pipe(&endpoint, true)?;
    let server_endpoint = endpoint.clone();
    let server = tokio::spawn(async move {
        let mut next_server = Some(first_server);
        let mut connections = tokio::task::JoinSet::new();
        let outcome = loop {
            let pipe = next_server
                .take()
                .expect("the next named-pipe server is always prepared");
            tokio::select! {
                connected = pipe.connect() => {
                    if let Err(error) = connected {
                        break Err(eyre::Report::from(error));
                    }
                    match create_named_pipe(&server_endpoint, false) {
                        Ok(prepared) => next_server = Some(prepared),
                        Err(error) => break Err(error),
                    }
                    let agent = agent.clone();
                    let task = Arc::clone(&task);
                    connections.spawn(async move {
                        task.connected.store(true, std::sync::atomic::Ordering::Relaxed);
                        if let Err(error) = agent.handle_connection(pipe).await {
                            debug!("cache agent connection failed: {error}");
                        }
                    });
                    // A build makes one connection per compilation, so finished
                    // ones are reaped as they go rather than held until shutdown.
                    while connections.try_join_next().is_some() {}
                }
                _ = &mut shutdown => break Ok(()),
            }
        };
        // A connection answers requests, and a store request queues an upload,
        // so the session has not stopped accepting work until these are done.
        while connections.join_next().await.is_some() {}
        outcome
    });
    Ok((endpoint, server))
}

pub(super) async fn initialize_task(agent: &CacheAgent, task: &super::SessionTask) {
    let Some(identity) = task.identity.get() else {
        return;
    };
    task.initialized
        .get_or_init(|| async {
            match agent.begin_session_task(identity).await {
                Ok(()) => true,
                Err(error) => {
                    log::warn!("build action manifest was not loaded: {error}");
                    false
                }
            }
        })
        .await;
}

#[cfg(windows)]
fn create_named_pipe(
    endpoint: &str,
    first_pipe_instance: bool,
) -> Result<tokio::net::windows::named_pipe::NamedPipeServer> {
    use std::mem::size_of;
    use windows_sys::Win32::Security::SECURITY_ATTRIBUTES;

    let security = CurrentUserSecurityDescriptor::new()?;
    let mut attributes = SECURITY_ATTRIBUTES {
        nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: security.0,
        bInheritHandle: 0,
    };
    let mut options = tokio::net::windows::named_pipe::ServerOptions::new();
    options.first_pipe_instance(first_pipe_instance);
    // SAFETY: `attributes` and its owned security descriptor remain valid for
    // the duration of CreateNamedPipeW, and the handle is not inheritable.
    unsafe {
        options
            .create_with_security_attributes_raw(endpoint, (&raw mut attributes).cast())
            .wrap_err("failed to create the current-user-only cache pipe")
    }
}

#[cfg(windows)]
struct CurrentUserSecurityDescriptor(windows_sys::Win32::Security::PSECURITY_DESCRIPTOR);

#[cfg(windows)]
impl CurrentUserSecurityDescriptor {
    fn new() -> Result<Self> {
        use std::mem::size_of;
        use std::ptr::null_mut;
        use windows_sys::Win32::Foundation::HANDLE;
        use windows_sys::Win32::Security::Authorization::{
            ConvertSidToStringSidW, ConvertStringSecurityDescriptorToSecurityDescriptorW,
            SDDL_REVISION_1,
        };
        use windows_sys::Win32::Security::{
            GetTokenInformation, TOKEN_QUERY, TOKEN_USER, TokenUser,
        };
        use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

        let mut token: HANDLE = null_mut();
        // SAFETY: `token` is a valid out pointer and the process pseudo-handle
        // is always valid in the calling process.
        if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw mut token) } == 0 {
            return Err(std::io::Error::last_os_error())
                .wrap_err("failed to open the current process token");
        }
        let token = OwnedWindowsHandle(token);

        let mut required = 0;
        // The first call intentionally obtains the required buffer size.
        // SAFETY: a null information pointer is required for this size query.
        unsafe {
            GetTokenInformation(token.0, TokenUser, null_mut(), 0, &raw mut required);
        }
        if required == 0 {
            return Err(std::io::Error::last_os_error())
                .wrap_err("failed to size the current process user token");
        }
        let word_count = (required as usize).div_ceil(size_of::<usize>());
        let mut token_information = vec![0usize; word_count];
        // SAFETY: the aligned buffer is at least `required` bytes long and the
        // API initializes it as TOKEN_USER on success.
        if unsafe {
            GetTokenInformation(
                token.0,
                TokenUser,
                token_information.as_mut_ptr().cast(),
                required,
                &raw mut required,
            )
        } == 0
        {
            return Err(std::io::Error::last_os_error())
                .wrap_err("failed to read the current process user token");
        }
        // SAFETY: GetTokenInformation successfully initialized the aligned
        // buffer as TOKEN_USER and its SID remains owned by that buffer.
        let user_sid = unsafe {
            (*(token_information.as_ptr().cast::<TOKEN_USER>()))
                .User
                .Sid
        };
        let mut sid_string = null_mut();
        // SAFETY: `user_sid` points into the live token-information buffer and
        // `sid_string` is a valid out pointer.
        if unsafe { ConvertSidToStringSidW(user_sid, &raw mut sid_string) } == 0 {
            return Err(std::io::Error::last_os_error())
                .wrap_err("failed to format the current process user SID");
        }
        let sid_string = LocalWindowsAllocation(sid_string.cast());
        // SAFETY: ConvertSidToStringSidW returned a valid NUL-terminated string
        // whose allocation remains live through `sid_string`.
        let sid = unsafe { nul_terminated_wide(sid_string.0.cast()) };

        let mut sddl: Vec<u16> = "D:P(A;;GA;;;".encode_utf16().collect();
        sddl.extend_from_slice(sid);
        sddl.extend([')' as u16, 0]);
        let mut descriptor = null_mut();
        // SAFETY: the SDDL is NUL-terminated, `descriptor` is a valid out
        // pointer, and the returned allocation is owned by LocalFree.
        if unsafe {
            ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl.as_ptr(),
                SDDL_REVISION_1,
                &raw mut descriptor,
                null_mut(),
            )
        } == 0
        {
            return Err(std::io::Error::last_os_error())
                .wrap_err("failed to restrict the cache pipe to the current user");
        }
        drop(token);
        drop(sid_string);
        debug_assert!(!descriptor.is_null());
        Ok(Self(descriptor))
    }
}

#[cfg(windows)]
impl Drop for CurrentUserSecurityDescriptor {
    fn drop(&mut self) {
        // SAFETY: this allocation came from
        // ConvertStringSecurityDescriptorToSecurityDescriptorW.
        unsafe {
            windows_sys::Win32::Foundation::LocalFree(self.0.cast());
        }
    }
}

#[cfg(windows)]
struct OwnedWindowsHandle(windows_sys::Win32::Foundation::HANDLE);

#[cfg(windows)]
impl Drop for OwnedWindowsHandle {
    fn drop(&mut self) {
        // SAFETY: this handle came from OpenProcessToken and is owned here.
        unsafe {
            windows_sys::Win32::Foundation::CloseHandle(self.0);
        }
    }
}

#[cfg(windows)]
struct LocalWindowsAllocation(windows_sys::Win32::Foundation::HLOCAL);

#[cfg(windows)]
impl Drop for LocalWindowsAllocation {
    fn drop(&mut self) {
        // SAFETY: this allocation came from a Win32 API documented to use
        // LocalAlloc and has not previously been freed.
        unsafe {
            windows_sys::Win32::Foundation::LocalFree(self.0);
        }
    }
}

#[cfg(windows)]
unsafe fn nul_terminated_wide<'a>(value: *const u16) -> &'a [u16] {
    let mut length = 0;
    // SAFETY: the caller guarantees that `value` points to a valid
    // NUL-terminated UTF-16 string.
    while unsafe { *value.add(length) } != 0 {
        length += 1;
    }
    // SAFETY: the scan above established the initialized string length.
    unsafe { std::slice::from_raw_parts(value, length) }
}
