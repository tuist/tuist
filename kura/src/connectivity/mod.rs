//! Fixed, unauthenticated network observations, isolated from serving lifecycle.

use std::{
    future::Future,
    io::{Read, Write},
    net::{IpAddr, SocketAddr, ToSocketAddrs},
    panic::{AssertUnwindSafe, catch_unwind},
    sync::Arc,
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use serde::Serialize;
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpStream,
    sync::{Semaphore, oneshot},
};

const INTERVAL: Duration = Duration::from_secs(60);
const OVERALL_TIMEOUT: Duration = Duration::from_secs(5);
const HEADER_LIMIT: usize = 8192;

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
    start(std::env::var("KURA_CONNECTIVITY_PROFILE").ok().as_deref())
}

fn profile_host(profile: &str) -> Option<&'static str> {
    match profile {
        "production" => Some("tuist-tuist-server.tuist.svc.cluster.local"),
        "staging" => Some("tuist-tuist-server.tuist-staging.svc.cluster.local"),
        "canary" => Some("tuist-tuist-server.tuist-canary.svc.cluster.local"),
        _ => None,
    }
}

fn start(profile: Option<&str>) -> Option<Diagnostics> {
    let profile = profile?;
    let host = profile_host(profile)?;
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
        runtime.block_on(until_stopped(stop, observe(host)));
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

async fn observe(host: &'static str) {
    let resolver = Resolver::default();
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
                |name| resolver.lookup(name),
                TcpStream::connect,
            )
            .await;
            emit(&sample);
        }
        tokio::time::sleep(INTERVAL).await;
    }
}

fn profile_samples(host: &str) -> [(String, Duration); 4] {
    [
        (host.to_owned(), Duration::from_secs(1)),
        (host.to_owned(), Duration::from_secs(3)),
        (format!("{host}."), Duration::from_secs(1)),
        (format!("{host}."), Duration::from_secs(3)),
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
    async fn lookup(&self, host: String) -> Result<Vec<SocketAddr>, ()> {
        self.lookup_using(host, |host| {
            (host.as_str(), 80)
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

fn allowed_address(address: &SocketAddr) -> bool {
    if address.port() != 80 {
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
    host: &str,
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
    let start = Instant::now();
    let mut sample = Sample {
        event: "kura.connectivity.sample",
        target: host.into(),
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
        let request = format!(
            "GET /ready HTTP/1.1\r\nHost: {host}\r\nUser-Agent: tuist-connectivity-probe/2\r\nConnection: close\r\n\r\n"
        );
        sample.outcome = "dns_error";
        let connect = async {
            let addresses = lookup(host.to_owned()).await?;
            sample.dns_ms = Some(elapsed(start));
            sample.outcome = "address_error";
            if addresses.is_empty()
                || addresses.len() > 16
                || !addresses.iter().all(allowed_address)
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
        // Read only a single bounded response header block. /ready returns an
        // empty response. Never follow redirects, drain a body, or loop over
        // informational responses from an unexpected endpoint.
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
