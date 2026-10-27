//! Lookups against a remote that is not answering, over a real wire.
//!
//! The server stands in for the cache activation gateway in front of an
//! instance that never becomes ready: it holds each request for a while, then
//! answers UNAVAILABLE carrying `x-tuist-cache-activation: pending`, the way
//! the gateway does at the end of its activation wait. A build waits on every
//! lookup, so each one must cost at most that one wait, and the lookups after
//! it must not ask again until the remote answers.

use std::net::TcpListener as StdTcpListener;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::action_cache_server::{ActionCache, ActionCacheServer};
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

/// `LOOKUP_UNAVAILABLE_BACKOFF_MS` in the client.
const SKIP_WINDOW: Duration = Duration::from_secs(5);

#[derive(Clone)]
struct Unanswering {
    delay: Duration,
    activation_pending: bool,
    answering: Arc<AtomicBool>,
    lookups: Arc<AtomicUsize>,
    reads: Arc<AtomicUsize>,
}

impl Unanswering {
    fn new(delay: Duration, activation_pending: bool) -> Self {
        Self {
            delay,
            activation_pending,
            answering: Arc::default(),
            lookups: Arc::default(),
            reads: Arc::default(),
        }
    }

    async fn refuse(&self) -> Status {
        tokio::time::sleep(self.delay).await;
        let mut status = Status::unavailable("Service Unavailable");
        if self.activation_pending {
            status
                .metadata_mut()
                .insert("x-tuist-cache-activation", "pending".parse().unwrap());
            status
                .metadata_mut()
                .insert("retry-after", "2".parse().unwrap());
        }
        status
    }
}

#[tonic::async_trait]
impl ActionCache for Unanswering {
    async fn get_action_result(
        &self,
        _: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        self.lookups.fetch_add(1, Ordering::SeqCst);
        if self.answering.load(Ordering::SeqCst) {
            return Err(Status::not_found("no such action"));
        }
        Err(self.refuse().await)
    }

    async fn update_action_result(
        &self,
        _: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        Err(Status::unimplemented("test server"))
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for Unanswering {
    async fn batch_read_blobs(
        &self,
        _: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        Err(self.refuse().await)
    }

    async fn find_missing_blobs(
        &self,
        _: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        Err(Status::unimplemented("test server"))
    }

    async fn batch_update_blobs(
        &self,
        _: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        Err(Status::unimplemented("test server"))
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
        Err(Status::unimplemented("test server"))
    }

    async fn split_blob(
        &self,
        _: Request<reapi::SplitBlobRequest>,
    ) -> Result<Response<reapi::SplitBlobResponse>, Status> {
        Err(Status::unimplemented("test server"))
    }

    async fn splice_blob(
        &self,
        _: Request<reapi::SpliceBlobRequest>,
    ) -> Result<Response<reapi::SpliceBlobResponse>, Status> {
        Err(Status::unimplemented("test server"))
    }
}

fn remote_for(server: &Unanswering) -> Arc<Remote> {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    let server = server.clone();
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            let listener =
                tokio::net::TcpListener::from_std(listener).expect("adopt bound listener");
            let incoming = tonic::transport::server::TcpIncoming::from(listener);
            tonic::transport::Server::builder()
                .add_service(ActionCacheServer::new(server.clone()))
                .add_service(ContentAddressableStorageServer::new(server))
                .serve_with_incoming(incoming)
                .await
                .expect("serve");
        });
    });
    Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    )
}

fn digest() -> Digest {
    Digest {
        hash: "aa".into(),
        size_bytes: 3,
    }
}

fn eventually(what: &str, condition: impl Fn() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !condition() {
        assert!(Instant::now() < deadline, "{what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn a_lookup_the_activation_gateway_held_costs_one_wait_and_the_next_lookups_skip() {
    let delay = Duration::from_secs(1);
    let server = Unanswering::new(delay, true);
    let remote = remote_for(&server);

    // Retried, this was three waits: one per attempt.
    let started = Instant::now();
    assert!(remote.get_action(b"key").is_err());
    let elapsed = started.elapsed();
    assert!(
        elapsed < delay * 2,
        "the lookup took {elapsed:?}; it must return after the one wait"
    );
    assert_eq!(server.lookups.load(Ordering::SeqCst), 1);

    let started = Instant::now();
    assert!(remote.get_action(b"another key").is_err());
    assert!(remote.batch_read(&[digest()]).is_err());
    assert!(started.elapsed() < delay / 2);
    assert_eq!(server.lookups.load(Ordering::SeqCst), 1, "no lookup was sent");
    assert_eq!(server.reads.load(Ordering::SeqCst), 0, "no read was sent");
    assert_eq!(remote.skipped_lookups(), 2);
}

#[test]
fn a_demand_read_the_activation_gateway_held_costs_one_wait_and_the_lookups_skip() {
    let delay = Duration::from_secs(1);
    let server = Unanswering::new(delay, true);
    let remote = remote_for(&server);

    let started = Instant::now();
    assert!(remote.batch_read(&[digest()]).is_err());
    let elapsed = started.elapsed();
    assert!(
        elapsed < delay * 2,
        "the read took {elapsed:?}; it must return after the one wait"
    );
    assert_eq!(server.reads.load(Ordering::SeqCst), 1);

    assert!(remote.skip_lookup());
    assert!(remote.get_action(b"key").is_err());
    assert_eq!(server.lookups.load(Ordering::SeqCst), 0, "no lookup was sent");
}

#[test]
fn an_unavailable_from_the_server_itself_is_still_retried_before_lookups_skip() {
    // A draining kura node answers UNAVAILABLE and the retry reaches the other
    // replica, so only the activation gateway's answer goes unretried.
    let server = Unanswering::new(Duration::from_millis(50), false);
    let remote = remote_for(&server);

    assert!(remote.get_action(b"key").is_err());
    assert_eq!(server.lookups.load(Ordering::SeqCst), 3);

    assert!(remote.get_action(b"another key").is_err());
    assert_eq!(server.lookups.load(Ordering::SeqCst), 3, "no lookup was sent");
}

#[test]
fn lookups_resume_once_the_background_probe_is_answered() {
    let server = Unanswering::new(Duration::from_millis(200), true);
    let remote = remote_for(&server);

    assert!(remote.get_action(b"key").is_err());
    assert_eq!(server.lookups.load(Ordering::SeqCst), 1);
    server.answering.store(true, Ordering::SeqCst);
    std::thread::sleep(SKIP_WINDOW + Duration::from_millis(200));

    // The first lookup past the window starts the probe and still skips, so no
    // build thread waits on a remote that may still be down.
    let started = Instant::now();
    assert!(remote.get_action(b"key").is_err());
    assert!(started.elapsed() < Duration::from_millis(100));
    eventually("the probe reached the server", || {
        server.lookups.load(Ordering::SeqCst) == 2
    });
    eventually("the probe's answer closed the breaker", || {
        !remote.skip_lookup()
    });

    assert!(matches!(remote.get_action(b"key"), Ok(None)));
    assert_eq!(server.lookups.load(Ordering::SeqCst), 3);
}
