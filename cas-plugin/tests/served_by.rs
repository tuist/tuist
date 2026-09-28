//! Who answered, over a real wire.
//!
//! Kura names its region and node on every REAPI response. The proxy has to
//! pick that up from answers and from not-found statuses alike (a miss is
//! still a round trip to a region), stamp when the connection carrying it
//! opened, and open a new connection when asked to renew, because a build
//! report built on these values blames the customer's network for anything
//! stale on our side.

use std::net::TcpListener as StdTcpListener;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use futures_util::stream;
use reapi::action_cache_server::{ActionCache, ActionCacheServer};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

struct NamedActionCache;

fn name(metadata: &mut tonic::metadata::MetadataMap) {
    metadata.insert("x-kura-region", "us-central".parse().unwrap());
    metadata.insert("x-kura-node", "acme-us-central-0".parse().unwrap());
}

#[tonic::async_trait]
impl ActionCache for NamedActionCache {
    async fn get_action_result(
        &self,
        request: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        let size = request
            .get_ref()
            .action_digest
            .as_ref()
            .map_or(0, |digest| digest.size_bytes);
        // One-byte keys miss.
        if size == 1 {
            let mut status = Status::not_found("miss");
            name(status.metadata_mut());
            return Err(status);
        }
        let mut response = Response::new(reapi::ActionResult::default());
        name(response.metadata_mut());
        Ok(response)
    }

    async fn update_action_result(
        &self,
        _: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        Err(Status::unimplemented("read-only"))
    }
}

/// Serves the action cache, counting the connections it accepts.
fn spawn_server() -> (std::net::SocketAddr, Arc<AtomicUsize>) {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    let accepted = Arc::new(AtomicUsize::new(0));
    let counter = accepted.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            let listener =
                tokio::net::TcpListener::from_std(listener).expect("adopt bound listener");
            let incoming = stream::unfold((listener, counter), |(listener, counter)| async move {
                let accepted = listener.accept().await.map(|(stream, _)| stream);
                counter.fetch_add(1, Ordering::SeqCst);
                Some((accepted, (listener, counter)))
            });
            tonic::transport::Server::builder()
                .add_service(ActionCacheServer::new(NamedActionCache))
                .serve_with_incoming(incoming)
                .await
                .expect("serve");
        });
    });
    (addr, accepted)
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

fn remote_at(addr: std::net::SocketAddr) -> Arc<Remote> {
    Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "acme/app".into(),
        },
        TokenProvider::from_env(),
    )
}

#[test]
fn records_who_answered_hits_and_misses_and_when_their_connection_opened() {
    let (addr, _) = spawn_server();
    let remote = remote_at(addr);
    assert_eq!(remote.served_by(), None, "nothing has answered yet");

    let before = now_ms();
    assert!(remote.get_action(b"m").is_ok());
    let served = remote
        .served_by()
        .expect("a not-found status names who answered it");
    assert_eq!(&*served.region, "us-central");
    assert_eq!(&*served.node, "acme-us-central-0");
    assert!(served.connected_at_ms >= before);

    assert!(matches!(remote.get_action(b"hit"), Ok(Some(_))));
    assert_eq!(
        remote.served_by().map(|served| served.connected_at_ms),
        Some(served.connected_at_ms),
        "a second call rides the same connection"
    );
}

#[test]
fn renewing_opens_a_new_connection_on_the_next_call() {
    let (addr, accepted) = spawn_server();
    let remote = remote_at(addr);

    assert!(remote.get_action(b"hit").is_ok());
    assert!(remote.get_action(b"hit").is_ok());
    assert_eq!(accepted.load(Ordering::SeqCst), 1);
    let first = remote.served_by().unwrap().connected_at_ms;

    std::thread::sleep(Duration::from_millis(5));
    remote.renew_connection();
    assert!(remote.get_action(b"hit").is_ok());

    assert_eq!(
        accepted.load(Ordering::SeqCst),
        2,
        "the call after a renewal dials again, resolving the host again"
    );
    let second = remote.served_by().unwrap().connected_at_ms;
    assert!(second > first, "{second} should be after {first}");
}
