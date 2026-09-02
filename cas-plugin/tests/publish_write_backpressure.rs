//! End-to-end validation of the publication write path's backpressure handling.
//!
//! Reproduces the production shape without a kura node: a real gRPC CAS server
//! that answers every `BatchUpdateBlobs` with RESOURCE_EXHAUSTED, which is what
//! a node whose outbox is at its cap returns while it sheds writes. The actual
//! `Remote::batch_update` wire path is driven against it and the server counts
//! the RPCs, so the retry ladder and the breaker are observed over the wire
//! rather than asserted about a mock.
//!
//! Before the fix every publication paid the full ladder, whose sleep is 200ms,
//! on every shed. Publications are background work, so a build's wall clock
//! absorbed it and the only place it surfaced was `write_duration` in the build
//! report -- the 40x write-latency regression of 2026-09-02, whose tell was that
//! `read_duration` stayed flat because reads already had a breaker.

use std::net::TcpListener as StdTcpListener;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use bazel_remote_apis::google::rpc::Status as RpcStatus;
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

/// `ATTEMPTS` in the client: an unbroken ladder issues this many RPCs.
const LADDER_ATTEMPTS: usize = 3;
/// `RETRY_BACKOFF * (attempt - 1)` summed over the ladder. Only the third
/// attempt sleeps, so one ladder is one 200ms sleep.
const LADDER_SLEEP: Duration = Duration::from_millis(200);

/// gRPC RESOURCE_EXHAUSTED, as it appears in a per-blob `status` field.
const RESOURCE_EXHAUSTED: i32 = 8;

/// How a server refuses a write. Kura does it both ways, and the client used to
/// notice only the first: it declines the whole call when its outbox is already
/// at its cap, and answers OK with the refusal on the individual blob when
/// capacity runs out partway through the request.
#[derive(Clone, Copy)]
enum Shed {
    WholeCall,
    PerBlob,
}

/// A CAS server that sheds every write in one of those two shapes, counting the
/// `BatchUpdateBlobs` RPCs it receives.
struct SheddingCas {
    batch_update_calls: Arc<AtomicUsize>,
    shed: Shed,
}

#[tonic::async_trait]
impl ContentAddressableStorage for SheddingCas {
    async fn batch_update_blobs(
        &self,
        request: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        self.batch_update_calls.fetch_add(1, Ordering::SeqCst);
        match self.shed {
            Shed::WholeCall => Err(Status::resource_exhausted("write outbox at capacity")),
            Shed::PerBlob => Ok(Response::new(reapi::BatchUpdateBlobsResponse {
                responses: request
                    .into_inner()
                    .requests
                    .into_iter()
                    .map(|entry| reapi::batch_update_blobs_response::Response {
                        digest: entry.digest,
                        status: Some(RpcStatus {
                            code: RESOURCE_EXHAUSTED,
                            message: "write outbox reached capacity mid-request".into(),
                            details: Vec::new(),
                        }),
                    })
                    .collect(),
            })),
        }
    }

    async fn batch_read_blobs(
        &self,
        _: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        Err(Status::unimplemented("test server"))
    }

    async fn find_missing_blobs(
        &self,
        _: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
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

/// Binds an ephemeral port and serves the shedding CAS on a dedicated thread.
/// The bound listener is handed to tonic directly so the port is held
/// continuously and the client's connection lands in the listen backlog the
/// moment `bind` returns -- readiness needs no sleep to guess at.
fn spawn_server(calls: Arc<AtomicUsize>, shed: Shed) -> std::net::SocketAddr {
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
            tonic::transport::Server::builder()
                .add_service(ContentAddressableStorageServer::new(SheddingCas {
                    batch_update_calls: calls,
                    shed,
                }))
                .serve_with_incoming(incoming)
                .await
                .expect("serve");
        });
    });
    addr
}

fn one_blob() -> Vec<(Digest, Vec<u8>)> {
    vec![(
        Digest {
            hash: "aa".into(),
            size_bytes: 3,
        },
        b"abc".to_vec(),
    )]
}

#[test]
fn a_shed_publication_arms_the_breaker_and_the_next_ones_stop_paying_the_ladder() {
    let calls = Arc::new(AtomicUsize::new(0));
    let addr = spawn_server(calls.clone(), Shed::WholeCall);
    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );

    assert!(
        !remote.shedding_writes(),
        "a Remote that has published nothing is not backing off"
    );

    // The first publication to meet the shed pays the ladder, which is what the
    // ladder is for: a node that is briefly unavailable recovers inside it.
    let first_started = Instant::now();
    let first = remote.batch_update(one_blob());
    let first_elapsed = first_started.elapsed();
    assert!(first.is_err(), "a shed write is not reported as published");
    assert_eq!(
        calls.load(Ordering::SeqCst),
        LADDER_ATTEMPTS,
        "the first publication re-issues BatchUpdateBlobs across the whole ladder"
    );
    assert!(
        first_elapsed >= LADDER_SLEEP,
        "the ladder's sleep is what the breaker exists to stop paying repeatedly, \
         so the unbroken path must really pay it (took {first_elapsed:?})"
    );
    assert!(
        remote.shedding_writes(),
        "a shed that survived the ladder arms the fail-fast window"
    );

    // Every publication queued behind it now fails fast. This is the fix: the
    // 200ms was being paid per publication, thousands of times per build.
    let mut fast = Vec::new();
    for _ in 0..20 {
        let before = calls.load(Ordering::SeqCst);
        let started = Instant::now();
        assert!(
            remote.batch_update(one_blob()).is_err(),
            "a shed write is still not reported as published"
        );
        fast.push(started.elapsed());
        assert_eq!(
            calls.load(Ordering::SeqCst) - before,
            1,
            "inside the window a publication makes one fail-fast attempt"
        );
    }

    let worst = fast.iter().copied().max().expect("samples");
    let total: Duration = fast.iter().sum();
    assert!(
        worst < LADDER_SLEEP,
        "no publication inside the window may pay a ladder sleep (worst {worst:?})"
    );
    // The headline: 20 publications against a shedding node used to cost 20
    // ladders. Asserted against the ladder's sleep alone, so the bound holds
    // whatever the loopback RTT is on the machine running this.
    assert!(
        total < LADDER_SLEEP * 20,
        "20 publications inside the window must cost less than 20 ladders \
         (took {total:?}, one ladder is {LADDER_SLEEP:?})"
    );
    eprintln!(
        "first publication {first_elapsed:?} (full ladder); \
         next 20 {total:?} total, worst {worst:?}"
    );

    assert_eq!(
        remote.shed_writes(),
        0,
        "batch_update is not the publication-level skip; that counter belongs to \
         the path that never starts a publication at all"
    );
}

#[test]
fn a_per_blob_shed_arms_the_same_breaker_as_a_refused_call() {
    // The shape the RPC-level check cannot see: the call succeeds and the
    // refusal rides on the blob. It means the same thing about the node, so it
    // has to reach the same breaker; before it did, this path returned a plain
    // error and left every later publication paying a probe, a closure walk and
    // a missing-blob query to arrive at a refusal already known.
    let calls = Arc::new(AtomicUsize::new(0));
    let addr = spawn_server(calls.clone(), Shed::PerBlob);
    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );

    assert!(
        remote.batch_update(one_blob()).is_err(),
        "a per-blob shed is not reported as published"
    );
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "the RPC itself succeeded, so the ladder never re-issues it"
    );
    assert!(
        remote.shedding_writes(),
        "a per-blob shed arms the breaker just as a refused call does"
    );

    // And the publication path is now the cheap one.
    let started = Instant::now();
    assert!(remote.batch_update(one_blob()).is_err());
    let elapsed = started.elapsed();
    assert!(
        elapsed < LADDER_SLEEP,
        "the next publication must not pay a ladder sleep (took {elapsed:?})"
    );
}

#[test]
fn an_unavailable_node_still_gets_the_full_ladder() {
    // Nothing is listening, so every attempt fails with UNAVAILABLE. That is a
    // transient transport condition, not a node saying it has too much load, and
    // failing publications fast for 5s because one connection blipped would turn
    // a reconnect into a window of skipped publications.
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind");
    let addr = listener.local_addr().expect("addr");
    drop(listener);

    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );
    assert!(remote.batch_update(one_blob()).is_err());
    assert!(
        !remote.shedding_writes(),
        "an unreachable node must not arm the shed breaker"
    );
}
