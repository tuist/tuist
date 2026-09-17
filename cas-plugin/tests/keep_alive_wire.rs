//! A local-hits report arriving on the proxy's socket leaves as a keep-alive on
//! a recording ActionCache server that answers the way kura does.

use std::net::TcpListener as StdTcpListener;
use std::os::unix::net::UnixListener;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::action_cache_server::{ActionCache, ActionCacheServer};
use sha2::{Digest as _, Sha256};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::proxy::Proxy;
use tuist_cas_plugin::proxy_proto::ProxyClient;
use tuist_cas_plugin::token::TokenProvider;

#[derive(Clone, Default)]
struct RecordingActionCache {
    requests: Arc<Mutex<Vec<reapi::GetActionResultRequest>>>,
    predates_keep_alive: Arc<AtomicBool>,
}

#[tonic::async_trait]
impl ActionCache for RecordingActionCache {
    async fn get_action_result(
        &self,
        request: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        let request = request.into_inner();
        let hints = request.inline_output_files.len();
        self.requests.lock().unwrap().push(request);
        if self.predates_keep_alive.load(Ordering::SeqCst) {
            return Err(Status::not_found("action result not found"));
        }
        Ok(Response::new(reapi::ActionResult {
            stdout_raw: format!("found={hints} missing=0 evicted=0").into_bytes(),
            ..Default::default()
        }))
    }

    async fn update_action_result(
        &self,
        _: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        Err(Status::unimplemented("test server"))
    }
}

impl RecordingActionCache {
    fn requests(&self) -> Vec<reapi::GetActionResultRequest> {
        self.requests.lock().unwrap().clone()
    }

    fn wait_for_requests(&self, count: usize) -> Vec<reapi::GetActionResultRequest> {
        let deadline = Instant::now() + Duration::from_secs(10);
        while self.requests.lock().unwrap().len() < count && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(10));
        }
        self.requests()
    }
}

fn spawn_server(server: RecordingActionCache) -> std::net::SocketAddr {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            let listener =
                tokio::net::TcpListener::from_std(listener).expect("adopt bound listener");
            tonic::transport::Server::builder()
                .add_service(ActionCacheServer::new(server))
                .serve_with_incoming(tonic::transport::server::TcpIncoming::from(listener))
                .await
                .expect("serve");
        });
    });
    addr
}

struct Harness {
    server: RecordingActionCache,
    client: ProxyClient,
    cas_path: String,
    dir: std::path::PathBuf,
}

impl Harness {
    fn new(name: &str) -> Self {
        let dir = std::path::PathBuf::from("/tmp")
            .join(format!("tuist-keep-alive-{name}-{}", std::process::id()));
        std::fs::remove_dir_all(&dir).ok();
        std::fs::create_dir_all(&dir).expect("temp dir");
        let server = RecordingActionCache::default();
        let addr = spawn_server(server.clone());
        let socket_path = dir.join("proxy.sock").to_string_lossy().into_owned();
        let listener = UnixListener::bind(&socket_path).expect("bind");
        let proxy = Proxy::new(
            format!("http://{addr}"),
            TokenProvider::from_env(),
            String::new(),
            Some(dir.join("registry")),
            None,
        );
        std::thread::spawn(move || proxy.serve(listener));
        Self {
            server,
            client: ProxyClient { socket_path },
            cas_path: dir.join("cas").to_string_lossy().into_owned(),
            dir,
        }
    }

    fn report(&self, keys: &[Vec<u8>]) {
        self.client
            .report_local_hits(&self.cas_path, "acme/app", keys)
            .expect("the proxy accepts the report");
    }
}

impl Drop for Harness {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.dir).ok();
    }
}

fn keys(label: &str, count: usize) -> Vec<Vec<u8>> {
    (0..count)
        .map(|index| Sha256::digest(format!("{label}-{index}")).to_vec())
        .collect()
}

fn hint(key: &[u8]) -> String {
    format!(
        "tuist-keep-alive:{}/{}",
        hex(&Sha256::digest(key)),
        key.len()
    )
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn reported_hits_leave_the_proxy_as_a_keep_alive_on_the_reserved_key() {
    let harness = Harness::new("reaches");
    let reported = keys("reaches", 300);
    harness.report(&reported);

    let deadline = Instant::now() + Duration::from_secs(10);
    let expected: std::collections::HashSet<String> =
        reported.iter().map(|key| hint(key)).collect();
    let mut hinted = std::collections::HashSet::new();
    while hinted != expected && Instant::now() < deadline {
        hinted = harness
            .server
            .requests()
            .iter()
            .flat_map(|request| request.inline_output_files.clone())
            .collect();
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(
        hinted, expected,
        "every reported action is named by its action digest"
    );

    let requests = harness.server.requests();
    let reserved = b"tuist-actioncache-keep-alive/v1";
    for request in &requests {
        let digest = request.action_digest.as_ref().expect("an action digest");
        assert_eq!(digest.hash, hex(&Sha256::digest(reserved)));
        assert_eq!(digest.size_bytes, reserved.len() as i64);
        assert_eq!(
            request.instance_name, "app",
            "the project segment, as every other RPC sends it"
        );
    }
}

#[test]
fn actions_already_kept_alive_are_not_sent_again_by_the_same_proxy() {
    let harness = Harness::new("memo");
    let reported = keys("memo", 10);
    harness.report(&reported);
    let first = harness.server.wait_for_requests(1).len();
    assert_eq!(first, 1);

    harness.report(&reported);
    std::thread::sleep(Duration::from_millis(500));
    assert_eq!(harness.server.requests().len(), 1);

    harness.report(&keys("memo-new", 1));
    assert_eq!(
        harness.server.wait_for_requests(2).len(),
        2,
        "a new action still goes out"
    );
}

#[test]
fn a_server_that_predates_keep_alive_is_asked_once() {
    let harness = Harness::new("old-server");
    harness
        .server
        .predates_keep_alive
        .store(true, Ordering::SeqCst);

    harness.report(&keys("old-server-a", 10));
    assert_eq!(harness.server.wait_for_requests(1).len(), 1);
    harness.report(&keys("old-server-b", 10));
    std::thread::sleep(Duration::from_millis(500));

    assert_eq!(
        harness.server.requests().len(),
        1,
        "the reserved key is an unknown action there; asking again only adds lookups"
    );
}
