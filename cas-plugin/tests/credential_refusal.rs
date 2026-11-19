//! A credential the server refuses stays refused until it changes, so a client
//! that keeps sending it only repeats the refusal. The proxy's publication
//! sweep re-sends every spooled record every few seconds, which turned one
//! refused machine into a steady stream of requests for as long as it ran.
//!
//! The server below answers every FindMissingBlobs the same way, serves every
//! read, and counts what reaches it.

use std::net::TcpListener as StdTcpListener;
use std::pin::Pin;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{blob_digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

#[derive(Clone, Copy)]
enum Answer {
    PermissionDenied,
    Unauthenticated,
    Unavailable,
    Missing,
}

struct CountingCas {
    answer: Answer,
    received: Arc<AtomicUsize>,
    reads: Arc<AtomicUsize>,
}

#[tonic::async_trait]
impl ContentAddressableStorage for CountingCas {
    async fn find_missing_blobs(
        &self,
        request: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        self.received.fetch_add(1, Ordering::SeqCst);
        match self.answer {
            Answer::PermissionDenied => Err(Status::permission_denied("no access to this account")),
            Answer::Unauthenticated => Err(Status::unauthenticated("invalid token")),
            Answer::Unavailable => Err(Status::unavailable("node down")),
            Answer::Missing => Ok(Response::new(reapi::FindMissingBlobsResponse {
                missing_blob_digests: request.into_inner().blob_digests,
            })),
        }
    }

    async fn batch_read_blobs(
        &self,
        _: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        self.reads.fetch_add(1, Ordering::SeqCst);
        Ok(Response::new(reapi::BatchReadBlobsResponse::default()))
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

fn spawn_server(answer: Answer) -> (Arc<Remote>, Arc<AtomicUsize>, Arc<AtomicUsize>) {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    let received = Arc::new(AtomicUsize::new(0));
    let reads = Arc::new(AtomicUsize::new(0));
    let service = CountingCas {
        answer,
        received: received.clone(),
        reads: reads.clone(),
    };
    std::thread::spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .expect("server runtime");
        rt.block_on(async move {
            let listener =
                tokio::net::TcpListener::from_std(listener).expect("adopt bound listener");
            tonic::transport::Server::builder()
                .add_service(ContentAddressableStorageServer::new(service))
                .serve_with_incoming(tonic::transport::server::TcpIncoming::from(listener))
                .await
                .expect("serve");
        });
    });
    let remote = Remote::new(
        RemoteConfig {
            grpc_url: format!("http://{addr}"),
            instance: "acme/app".into(),
        },
        TokenProvider::from_env(),
    );
    (remote, received, reads)
}

#[test]
fn a_refused_credential_is_not_sent_again() {
    for answer in [Answer::PermissionDenied, Answer::Unauthenticated] {
        let (remote, received, _) = spawn_server(answer);

        for _ in 0..20 {
            assert!(remote.find_missing(vec![blob_digest(b"object")]).is_err());
        }

        assert_eq!(
            received.load(Ordering::SeqCst),
            1,
            "only the first request was sent"
        );
        assert!(remote.publication_refused());
        assert_eq!(remote.skipped_credential_requests(), 19);
    }
}

#[test]
fn answers_that_do_not_judge_the_credential_keep_it_in_use() {
    for (answer, per_call) in [(Answer::Missing, 1), (Answer::Unavailable, 3)] {
        let (remote, received, _) = spawn_server(answer);

        for _ in 0..3 {
            let _ = remote.find_missing(vec![blob_digest(b"object")]);
        }

        assert_eq!(received.load(Ordering::SeqCst), 3 * per_call);
        assert!(!remote.publication_refused());
    }
}

// Kura authorizes each operation, so a read-only credential is refused its
// writes while its reads are served. Pausing it entirely would turn every
// cache hit into a miss.
#[test]
fn a_refused_write_does_not_pause_reads() {
    let (remote, received, reads) = spawn_server(Answer::PermissionDenied);

    for _ in 0..3 {
        assert!(remote.find_missing(vec![blob_digest(b"object")]).is_err());
        remote
            .batch_read(&[blob_digest(b"object")])
            .expect("reads are still sent");
    }

    assert_eq!(received.load(Ordering::SeqCst), 1);
    assert_eq!(reads.load(Ordering::SeqCst), 3);
}
