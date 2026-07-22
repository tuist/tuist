//! End-to-end validation of the CAS proxy's per-blob backpressure handling.
//!
//! Reproduces the exact production failure without a kura node: a real gRPC CAS
//! server that holds every blob but answers each `BatchReadBlobs` entry with
//! `RESOURCE_EXHAUSTED` -- what a memory-`Critical` kura returns while its
//! per-request REAPI materialization budget is zero. The actual
//! `Remote::batch_read` wire path is driven against it, and the server counts
//! the RPCs it receives, so the retry (over the real wire) and the per-`Remote`
//! backoff are observed rather than asserted about a mock closure.
//!
//! Before the fix this manifested as a single pass whose rejection was silently
//! discarded, handing the compiler an unbacked cache hit that failed the build
//! on a present object.

use std::net::TcpListener as StdTcpListener;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use bazel_remote_apis::google::rpc::Status as RpcStatus;
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{Digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

/// gRPC RESOURCE_EXHAUSTED. What kura stamps on every blob under memory pressure.
const RESOURCE_EXHAUSTED: i32 = 8;
/// `BLOB_STATUS_ATTEMPTS` in the client: the first read tries this many times.
const EXPECTED_ATTEMPTS: usize = 3;

/// A CAS server that holds every blob but declines every read with
/// RESOURCE_EXHAUSTED, counting the `BatchReadBlobs` RPCs it receives.
struct ExhaustedCas {
    batch_read_calls: Arc<AtomicUsize>,
}

#[tonic::async_trait]
impl ContentAddressableStorage for ExhaustedCas {
    async fn batch_read_blobs(
        &self,
        request: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        self.batch_read_calls.fetch_add(1, Ordering::SeqCst);
        let responses = request
            .into_inner()
            .digests
            .into_iter()
            .map(|digest| reapi::batch_read_blobs_response::Response {
                digest: Some(digest),
                data: Vec::new(),
                compressor: 0,
                status: Some(RpcStatus {
                    code: RESOURCE_EXHAUSTED,
                    message: "needs 576 bytes but only 0 bytes remain in the REAPI \
                              materialization budget"
                        .into(),
                    details: Vec::new(),
                }),
            })
            .collect();
        Ok(Response::new(reapi::BatchReadBlobsResponse { responses }))
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

/// Binds an ephemeral port, serves the exhausted CAS on a dedicated thread, and
/// returns the address once it has had a moment to start listening.
fn spawn_server(calls: Arc<AtomicUsize>) -> std::net::SocketAddr {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let addr = listener.local_addr().expect("local addr");
    drop(listener); // hand the port to tonic (a small, tolerable race in a test)
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            tonic::transport::Server::builder()
                .add_service(ContentAddressableStorageServer::new(ExhaustedCas {
                    batch_read_calls: calls,
                }))
                .serve(addr)
                .await
                .expect("serve");
        });
    });
    std::thread::sleep(Duration::from_millis(500));
    addr
}

#[test]
fn resource_exhausted_blobs_are_retried_over_the_wire_then_the_backoff_engages() {
    let calls = Arc::new(AtomicUsize::new(0));
    let addr = spawn_server(calls.clone());

    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );

    let digest = Digest {
        hash: "aa".into(),
        size_bytes: 3,
    };

    // First read: the server declines the blob it holds on every attempt, so the
    // fixed client re-issues the RPC up to its retry bound rather than dropping
    // the blob as absent. The blob is never served as bytes -- the point is that
    // the client no longer treats the refusal as a miss.
    let served = remote
        .batch_read(std::slice::from_ref(&digest))
        .expect("batch_read");
    assert!(served.is_empty(), "a declined blob is not served as bytes");
    assert_eq!(
        calls.load(Ordering::SeqCst),
        EXPECTED_ATTEMPTS,
        "the client re-issued BatchReadBlobs for each retry attempt, not a single silent pass"
    );

    // Second read within the backoff window: the per-Remote breaker the first
    // read armed makes this a single fail-fast pass, so a build's many reads
    // against a struggling node do not each pay the retry ladder.
    let before = calls.load(Ordering::SeqCst);
    let served = remote
        .batch_read(std::slice::from_ref(&digest))
        .expect("batch_read");
    assert!(served.is_empty());
    assert_eq!(
        calls.load(Ordering::SeqCst) - before,
        1,
        "within the backoff window the next read makes one fail-fast pass"
    );
}
