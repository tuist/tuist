//! A `Remote` whose endpoint does not serve the cache API stops calling it.
//!
//! The proxy's maintenance loop re-publishes every spooled record every 10s,
//! and a record is deleted only by a publication that succeeded. Against an
//! endpoint that answers every call with UNIMPLEMENTED (a plain HTTP server's
//! 404) or UNAVAILABLE (its 502), nothing ever succeeds, so each sweep sent every
//! record's existence probe and missing-blob query, around the clock, for as
//! long as the proxy ran. These drive the real client against gRPC servers that
//! answer that way and count what reaches them.

use std::net::TcpListener as StdTcpListener;
use std::pin::Pin;
use std::sync::atomic::{AtomicU8, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::action_cache_server::{ActionCache, ActionCacheServer};
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Digest, ManifestEntry, Remote, RemoteConfig, REMOTE_UNUSABLE};
use tuist_cas_plugin::token::TokenProvider;

const UNAVAILABLE: u8 = 0;
const UNIMPLEMENTED: u8 = 1;
const NOT_FOUND: u8 = 2;

/// Answers every ActionCache and CAS call with the status `mode` holds,
/// counting the calls that reach it.
#[derive(Clone)]
struct Failing {
    calls: Arc<AtomicUsize>,
    mode: Arc<AtomicU8>,
}

impl Failing {
    fn answer<T>(&self) -> Result<T, Status> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        match self.mode.load(Ordering::SeqCst) {
            UNAVAILABLE => Err(Status::unavailable("502 Bad Gateway")),
            // What tonic makes of a plain HTTP server's 404.
            UNIMPLEMENTED => Err(Status::unimplemented("404 Not Found")),
            _ => Err(Status::not_found("not in the cache")),
        }
    }
}

#[tonic::async_trait]
impl ActionCache for Failing {
    async fn get_action_result(
        &self,
        _: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        self.answer()
    }

    async fn update_action_result(
        &self,
        _: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        self.answer()
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for Failing {
    async fn find_missing_blobs(
        &self,
        _: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        self.answer()
    }

    async fn batch_update_blobs(
        &self,
        _: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        self.answer()
    }

    async fn batch_read_blobs(
        &self,
        _: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        self.answer()
    }

    type GetTreeStream = Pin<
        Box<
            dyn tonic::codegen::tokio_stream::Stream<Item = Result<reapi::GetTreeResponse, Status>>
                + Send,
        >,
    >;
    async fn get_tree(
        &self,
        _: Request<reapi::GetTreeRequest>,
    ) -> Result<Response<Self::GetTreeStream>, Status> {
        self.answer()
    }

    async fn split_blob(
        &self,
        _: Request<reapi::SplitBlobRequest>,
    ) -> Result<Response<reapi::SplitBlobResponse>, Status> {
        self.answer()
    }

    async fn splice_blob(
        &self,
        _: Request<reapi::SpliceBlobRequest>,
    ) -> Result<Response<reapi::SpliceBlobResponse>, Status> {
        self.answer()
    }
}

fn serve(router: tonic::transport::server::Router) -> std::net::SocketAddr {
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
            let incoming = tonic::transport::server::TcpIncoming::from(listener);
            router.serve_with_incoming(incoming).await.expect("serve");
        });
    });
    addr
}

fn remote_at(addr: std::net::SocketAddr) -> Arc<Remote> {
    Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    )
}

fn blob() -> Digest {
    Digest {
        hash: "aa".repeat(32),
        size_bytes: 3,
    }
}

fn refused_locally<T>(result: Result<T, String>) -> bool {
    matches!(result, Err(error) if error == REMOTE_UNUSABLE)
}

/// Everything one publication and one lookup send, each checked to fail fast.
fn every_core_call_fails_fast(remote: &Remote) {
    let manifest = [ManifestEntry {
        llcas_digest: vec![1],
        contents: None,
        blob: blob(),
    }];
    assert!(refused_locally(remote.get_action(b"key")));
    assert!(refused_locally(remote.probe_action(b"key")));
    assert!(refused_locally(remote.find_missing(vec![blob()])));
    assert!(refused_locally(
        remote.batch_update(vec![(blob(), b"abc".to_vec())])
    ));
    assert!(refused_locally(
        remote.update_action(b"key", &manifest, None, None)
    ));
}

fn serve_failing(mode: u8) -> (Arc<Remote>, Arc<AtomicUsize>, Arc<AtomicU8>) {
    let calls = Arc::new(AtomicUsize::new(0));
    let mode = Arc::new(AtomicU8::new(mode));
    let failing = Failing {
        calls: calls.clone(),
        mode: mode.clone(),
    };
    let addr = serve(
        tonic::transport::Server::builder()
            .add_service(ActionCacheServer::new(failing.clone()))
            .add_service(ContentAddressableStorageServer::new(failing)),
    );
    (remote_at(addr), calls, mode)
}

#[test]
fn an_endpoint_without_the_cache_api_is_called_once_not_once_per_publication() {
    let (remote, calls, _) = serve_failing(UNIMPLEMENTED);

    assert!(remote.probe_action(b"key").is_err());
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "UNIMPLEMENTED is not retried"
    );
    assert!(remote.unusable());

    // What the 10s sweep sends for 100 spooled records, all refused locally.
    for _ in 0..100 {
        every_core_call_fails_fast(&remote);
    }
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    // Past the shortest window: an endpoint that is not a cache is not asked
    // again within seconds.
    std::thread::sleep(Duration::from_millis(1_500));
    assert!(refused_locally(remote.find_missing(vec![blob()])));
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}

#[test]
fn an_unavailable_endpoint_backs_off_and_an_answer_ends_it() {
    let (remote, calls, mode) = serve_failing(UNAVAILABLE);

    // The first failure pays the retry ladder, which is what it is for: a node
    // that is briefly unavailable recovers inside it.
    assert!(remote.find_missing(vec![blob()]).is_err());
    let ladder = calls.load(Ordering::SeqCst);
    assert_eq!(ladder, 3, "one ladder is three attempts");
    assert!(remote.unusable());

    for _ in 0..100 {
        every_core_call_fails_fast(&remote);
    }
    assert_eq!(
        calls.load(Ordering::SeqCst),
        ladder,
        "no call reaches the endpoint while the window is open"
    );

    // The first window is short so a restarting node costs seconds of misses.
    std::thread::sleep(Duration::from_millis(1_100));
    assert!(!remote.unusable());
    assert!(remote.probe_action(b"key").is_err());
    assert_eq!(calls.load(Ordering::SeqCst), 2 * ladder);
    // The second one is twice as long.
    std::thread::sleep(Duration::from_millis(1_100));
    assert!(remote.unusable(), "a second failure doubles the window");
    std::thread::sleep(Duration::from_millis(1_000));
    assert!(!remote.unusable());

    // Any answer from the server ends the backoff and resets it.
    mode.store(NOT_FOUND, Ordering::SeqCst);
    assert!(matches!(remote.probe_action(b"key"), Ok(None)));
    assert!(!remote.unusable());
    mode.store(UNAVAILABLE, Ordering::SeqCst);
    assert!(remote.probe_action(b"key").is_err());
    assert!(remote.unusable());
    std::thread::sleep(Duration::from_millis(1_100));
    assert!(
        !remote.unusable(),
        "after an answer the next outage starts again from the shortest window"
    );
}
