//! Fixed, unauthenticated network observations, isolated from serving lifecycle.

use std::{
    future::Future,
    io::{Read, Write},
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    panic::{AssertUnwindSafe, catch_unwind},
    path::Path,
    sync::Arc,
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    sync::{Semaphore, oneshot},
};

const INTERVAL: Duration = Duration::from_secs(60);
const OVERALL_TIMEOUT: Duration = Duration::from_secs(5);
const HEADER_LIMIT: usize = 8192;
const CONFIG_FILE: &str = "/etc/kura/connectivity/selection.json";
const CONFIG_POLL: Duration = Duration::from_secs(5);
const MAX_WINDOW: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Selection {
    profile: String,
    expires_at_unix_seconds: u64,
}

impl Selection {
    fn remaining(&self, now: SystemTime) -> Option<Duration> {
        profile_host(&self.profile)?;
        let expiry = UNIX_EPOCH.checked_add(Duration::from_secs(self.expires_at_unix_seconds))?;
        let remaining = expiry.duration_since(now).ok()?;
        (!remaining.is_zero() && remaining <= MAX_WINDOW).then_some(remaining)
    }
}

fn read_selection(path: &Path) -> Option<Selection> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .ok()?
        .take(513)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > 512 {
        return None;
    }
    serde_json::from_slice(&bytes).ok()
}

pub(crate) struct Diagnostics {
    stop: Option<oneshot::Sender<()>>,
    // Dropping a JoinHandle detaches: diagnostics must never delay shutdown.
    _thread: Option<JoinHandle<()>>,
}

impl Drop for Diagnostics {
    fn drop(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
    }
}

pub(crate) fn start_from_env() -> Option<Diagnostics> {
    start(
        std::env::var("KURA_CONNECTIVITY_CONFIG_FILE")
            .ok()
            .as_deref(),
    )
}

fn profile_host(profile: &str) -> Option<&'static str> {
    match profile {
        "production" => Some("tuist-tuist-server.tuist.svc.cluster.local"),
        "staging" => Some("tuist-tuist-server.tuist-staging.svc.cluster.local"),
        "canary" => Some("tuist-tuist-server.tuist-canary.svc.cluster.local"),
        _ => None,
    }
}

fn start(config_file: Option<&str>) -> Option<Diagnostics> {
    if config_file != Some(CONFIG_FILE) {
        return None;
    }
    spawn_worker(move |stop| {
        let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .max_blocking_threads(1)
            .build()
        else {
            emit(
                &serde_json::json!({"event.name": "kura.connectivity.disabled", "outcome": "runtime_error"}),
            );
            return;
        };
        let resolver = Resolver::default();
        runtime.block_on(until_stopped(
            stop,
            watch_selection(
                || read_selection(Path::new(CONFIG_FILE)),
                SystemTime::now,
                |host| observe(host, &resolver),
            ),
        ));
        // libc DNS cannot be cancelled. One outstanding lookup is permitted,
        // and even that lookup must not hold application shutdown hostage.
        runtime.shutdown_background();
    })
}

fn spawn_worker(work: impl FnOnce(oneshot::Receiver<()>) + Send + 'static) -> Option<Diagnostics> {
    let (stop, receiver) = oneshot::channel();
    match std::thread::Builder::new().name("kura-connectivity".into()).spawn(move || {
        if catch_unwind(AssertUnwindSafe(|| work(receiver))).is_err() {
            emit(&serde_json::json!({"event.name": "kura.connectivity.disabled", "outcome": "worker_panicked"}));
        }
    }) {
        Ok(thread) => Some(Diagnostics { stop: Some(stop), _thread: Some(thread) }),
        Err(_) => None
    }
}

async fn until_stopped(stop: oneshot::Receiver<()>, work: impl Future<Output = ()>) {
    tokio::select! {
        biased;
        _ = stop => {},
        _ = work => {},
    }
}

async fn watch_selection<F: Future<Output = ()>>(
    read: impl Fn() -> Option<Selection>,
    now: impl Fn() -> SystemTime,
    work: impl Fn(&'static str) -> F,
) {
    // Carry time forward even while selection is absent or malformed. A wall
    // clock rollback must not extend an accepted window or rearm an expired one.
    let mut wall = now();
    let mut at = tokio::time::Instant::now();
    let mut monotonic_now = || {
        let current = tokio::time::Instant::now();
        wall = now().max(wall + current.duration_since(at));
        at = current;
        wall
    };
    let mut next_cycle = tokio::time::Instant::now();
    loop {
        if let Some(selection) = read()
            && let Some(remaining) = selection.remaining(monotonic_now())
        {
            let deadline = tokio::time::Instant::now() + remaining;
            let host = profile_host(&selection.profile).expect("validated fixed profile");
            tokio::select! {
                biased;
                _ = tokio::time::sleep_until(deadline) => {},
                _ = async {
                    loop {
                        tokio::time::sleep(CONFIG_POLL).await;
                        if selection.remaining(monotonic_now()).is_none()
                            || read().as_ref() != Some(&selection) {
                            break;
                        }
                    }
                } => {},
                _ = async {
                    tokio::time::sleep_until(next_cycle).await;
                    work(host).await;
                } => {},
            }
            // Config churn cannot bypass the normal pause, including when a
            // selection cancels an in-progress cycle rather than its sleep.
            next_cycle = tokio::time::Instant::now() + INTERVAL;
        }
        tokio::time::sleep(CONFIG_POLL).await;
    }
}

fn emit(record: &impl Serialize) {
    let mut output = std::io::stdout().lock();
    if serde_json::to_writer(&mut output, record).is_ok() {
        let _ = output.write_all(b"\n");
    }
}

#[derive(Default)]
struct ResolverRecord {
    previous: Option<(String, bool)>,
}

impl ResolverRecord {
    fn changed(&mut self, config: String, readable: bool) -> bool {
        if self
            .previous
            .as_ref()
            .is_some_and(|last| last.0 == config && last.1 == readable)
        {
            return false;
        }
        self.previous = Some((config, readable));
        true
    }
}

fn resolver_config() -> (String, bool) {
    let mut bytes = Vec::new();
    let readable = std::fs::File::open("/etc/resolv.conf")
        .and_then(|file| file.take(4096).read_to_end(&mut bytes))
        .is_ok();
    (String::from_utf8_lossy(&bytes).into_owned(), readable)
}

async fn observe(host: &'static str, resolver: &Resolver) {
    let mut record = ResolverRecord::default();
    loop {
        let (config, readable) = resolver_config();
        if record.changed(config.clone(), readable) {
            emit(
                &serde_json::json!({"event.name": "kura.connectivity.resolver", "resolver_config": config, "readable": readable}),
            );
        }
        for (target, budget) in profile_samples(host) {
            let sample = measure(
                &target,
                budget,
                OVERALL_TIMEOUT,
                |name| resolver.lookup(name, target.port),
                TcpStream::connect,
            )
            .await;
            emit(&sample);
        }
        tokio::time::sleep(INTERVAL).await;
    }
}

#[derive(Clone)]
struct Target {
    host: String,
    port: u16,
    path: &'static str,
}

fn profile_samples(host: &str) -> [(Target, Duration); 6] {
    let server = Target {
        host: host.to_owned(),
        port: 80,
        path: "/ready",
    };
    let absolute_server = Target {
        host: format!("{host}."),
        ..server.clone()
    };
    let alloy = Target {
        host: "k8s-monitoring-alloy-receiver.observability.svc.cluster.local".into(),
        port: 4318,
        path: "/v1/traces",
    };
    [
        (server.clone(), Duration::from_secs(1)),
        (server, Duration::from_secs(3)),
        (absolute_server.clone(), Duration::from_secs(1)),
        (absolute_server, Duration::from_secs(3)),
        (alloy.clone(), Duration::from_secs(3)),
        (
            Target {
                host: format!("{}.", alloy.host),
                ..alloy
            },
            Duration::from_secs(3),
        ),
    ]
}

struct Resolver {
    in_flight: Arc<Semaphore>,
}

impl Default for Resolver {
    fn default() -> Self {
        Self {
            in_flight: Arc::new(Semaphore::new(1)),
        }
    }
}

impl Resolver {
    async fn lookup(&self, host: String, port: u16) -> Result<Vec<SocketAddr>, ()> {
        self.lookup_using(host, move |host| {
            (host.as_str(), port)
                .to_socket_addrs()
                .map(|addresses| addresses.take(17).collect())
                .map_err(|_| ())
        })
        .await
    }

    async fn lookup_using(
        &self,
        host: String,
        resolve: impl FnOnce(String) -> Result<Vec<SocketAddr>, ()> + Send + 'static,
    ) -> Result<Vec<SocketAddr>, ()> {
        let permit = self.in_flight.clone().try_acquire_owned().map_err(|_| ())?;
        tokio::task::spawn_blocking(move || {
            let _permit = permit;
            resolve(host)
        })
        .await
        .map_err(|_| ())?
    }
}

#[derive(Serialize)]
struct Sample {
    #[serde(rename = "event.name")]
    event: &'static str,
    target: String,
    port: u16,
    path: &'static str,
    started_at_unix_ms: u128,
    connect_budget_ms: u128,
    #[serde(skip_serializing_if = "Option::is_none")]
    dns_ms: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    connect_ms: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    first_byte_ms: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    headers_ms: Option<f64>,
    total_ms: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    status: Option<u16>,
    outcome: &'static str,
}

fn elapsed(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

fn allowed_address(address: &SocketAddr, port: u16) -> bool {
    if address.port() != port {
        return false;
    }
    if let SocketAddr::V6(address) = address
        && address.scope_id() != 0
    {
        return false;
    }
    match address.ip() {
        IpAddr::V4(ip) => ip.is_private(),
        IpAddr::V6(ip) => ip
            .to_ipv4_mapped()
            .map_or_else(|| ip.is_unique_local(), |ip| ip.is_private()),
    }
}

async fn measure<L, LF, D, DF>(
    target: &Target,
    budget: Duration,
    overall: Duration,
    lookup: L,
    dial: D,
) -> Sample
where
    L: FnOnce(String) -> LF,
    LF: Future<Output = Result<Vec<SocketAddr>, ()>>,
    D: FnOnce(SocketAddr) -> DF,
    DF: Future<Output = std::io::Result<TcpStream>>,
{
    let host = target.host.as_str();
    let start = Instant::now();
    let mut sample = Sample {
        event: "kura.connectivity.sample",
        target: host.into(),
        port: target.port,
        path: target.path,
        started_at_unix_ms: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis(),
        connect_budget_ms: budget.as_millis(),
        dns_ms: None,
        connect_ms: None,
        first_byte_ms: None,
        headers_ms: None,
        total_ms: 0.0,
        status: None,
        outcome: "request_error",
    };
    let operation = async {
        if host.is_empty()
            || host.len() > 253
            || !host
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'.' || byte == b'-')
        {
            return Err(());
        }
        let authority = if target.port == 80 {
            host.to_owned()
        } else {
            format!("{host}:{}", target.port)
        };
        let request = format!(
            "GET {} HTTP/1.1\r\nHost: {authority}\r\nUser-Agent: tuist-connectivity-probe/2\r\nConnection: close\r\n\r\n",
            target.path
        );
        sample.outcome = "dns_error";
        let connect = async {
            let addresses = lookup(host.to_owned()).await?;
            sample.dns_ms = Some(elapsed(start));
            sample.outcome = "address_error";
            if addresses.is_empty()
                || addresses.len() > 16
                || !addresses
                    .iter()
                    .all(|address| allowed_address(address, target.port))
            {
                return Err(());
            }
            sample.outcome = "connect_error";
            let stream = dial(addresses[0]).await.map_err(|_| ())?;
            sample.connect_ms = Some(elapsed(start));
            Ok(stream)
        };
        let mut stream = tokio::time::timeout(budget, connect)
            .await
            .map_err(|_| ())??;
        sample.outcome = "http_error";
        stream.write_all(request.as_bytes()).await.map_err(|_| ())?;
        // Read only a single bounded response header block. Never follow
        // redirects, drain a body, or loop over informational responses.
        let mut buffer = [0u8; HEADER_LIMIT];
        let mut used = 0;
        loop {
            if used == buffer.len() {
                return Err(());
            }
            let read = stream.read(&mut buffer[used..]).await.map_err(|_| ())?;
            if read == 0 {
                return Err(());
            }
            if used == 0 {
                sample.first_byte_ms = Some(elapsed(start));
            }
            used += read;
            let mut headers = [httparse::EMPTY_HEADER; 64];
            let mut response = httparse::Response::new(&mut headers);
            if response
                .parse(&buffer[..used])
                .map_err(|_| ())?
                .is_complete()
            {
                let status = response.code.ok_or(())?;
                sample.headers_ms = Some(elapsed(start));
                sample.status = Some(status);
                sample.outcome = if status < 200 {
                    "informational_response"
                } else {
                    "ok"
                };
                break;
            }
        }
        Ok::<(), ()>(())
    };
    let _ = tokio::time::timeout(overall, operation).await;
    sample.total_ms = elapsed(start);
    sample
}

#[cfg(test)]
mod tests;
