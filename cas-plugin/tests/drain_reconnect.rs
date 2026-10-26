//! A kura replica that starts draining refuses every request with
//! `UNAVAILABLE: server is draining` until it terminates, 20 s later in a
//! hosted rollout. Retrying on the connection that carried the refusal reaches
//! the same replica every time, so the client has to reconnect, and keep
//! retrying for as long as a stale endpoint list may route it back there.
//!
//! The server below stands in for a draining replica behind the same address:
//! it tells connections apart by their client address, the way a load balancer
//! spreads new connections over replicas.

use std::collections::HashSet;
use std::net::{SocketAddr, TcpListener as StdTcpListener};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use bazel_remote_apis::google::rpc::Status as RpcStatus;
use reapi::content_addressable_storage_server::{
    ContentAddressableStorage, ContentAddressableStorageServer,
};
use tonic::{Request, Response, Status};

use tuist_cas_plugin::reapi::{blob_digest, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

const BLOB: &[u8] = b"compiled object";

#[derive(Clone, Copy)]
enum Drain {
    /// Only the first connection reaches the draining replica.
    FirstConnection,
    /// Every connection reaches it until the deadline, as while the endpoint
    /// list still names the draining replica.
    Until(Instant),
}

#[derive(Default)]
struct Observed {
    draining_connection: Option<SocketAddr>,
    connections: HashSet<SocketAddr>,
    refused: usize,
    served: usize,
}

struct DrainingCas {
    drain: Drain,
    observed: Arc<Mutex<Observed>>,
}

impl DrainingCas {
    fn admit<T>(&self, request: &Request<T>) -> Result<(), Status> {
        let peer = request.remote_addr().expect("client address");
        let mut observed = self.observed.lock().unwrap();
        observed.connections.insert(peer);
        let draining = match self.drain {
            Drain::FirstConnection => *observed.draining_connection.get_or_insert(peer) == peer,
            Drain::Until(deadline) => Instant::now() < deadline,
        };
        if draining {
            observed.refused += 1;
            return Err(Status::unavailable("server is draining"));
        }
        observed.served += 1;
        Ok(())
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for DrainingCas {
    async fn batch_read_blobs(
        &self,
        request: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        self.admit(&request)?;
        let responses = request
            .into_inner()
            .digests
            .into_iter()
            .map(|digest| reapi::batch_read_blobs_response::Response {
                digest: Some(digest),
                data: BLOB.to_vec(),
                compressor: 0,
                status: Some(RpcStatus::default()),
            })
            .collect();
        Ok(Response::new(reapi::BatchReadBlobsResponse { responses }))
    }

    async fn find_missing_blobs(
        &self,
        request: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        self.admit(&request)?;
        Ok(Response::new(reapi::FindMissingBlobsResponse {
            missing_blob_digests: Vec::new(),
        }))
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

fn spawn_server(drain: Drain) -> (Arc<Remote>, Arc<Mutex<Observed>>) {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    listener
        .set_nonblocking(true)
        .expect("nonblocking for tokio adoption");
    let addr = listener.local_addr().expect("local addr");
    let observed = Arc::new(Mutex::new(Observed::default()));
    let service = DrainingCas {
        drain,
        observed: observed.clone(),
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
            instance: "test".into(),
        },
        TokenProvider::from_env(),
    );
    (remote, observed)
}

#[test]
fn a_draining_refusal_is_retried_on_a_new_connection() {
    let (remote, observed) = spawn_server(Drain::FirstConnection);
    let digest = blob_digest(BLOB);

    let served = remote
        .batch_read(std::slice::from_ref(&digest))
        .expect("batch_read");

    assert_eq!(
        served.get(&digest.hash).map(Vec::as_slice),
        Some(BLOB),
        "the retry reached a serving replica instead of the draining one"
    );
    let observed = observed.lock().unwrap();
    assert_eq!(
        observed.refused, 1,
        "only the first attempt went to the draining connection"
    );
    assert_eq!(observed.connections.len(), 2);
}

#[test]
fn retries_outlast_a_drain_the_endpoint_list_has_not_caught_up_with() {
    let drain_window = Duration::from_millis(1_500);
    let (remote, observed) = spawn_server(Drain::Until(Instant::now() + drain_window));

    let missing = remote
        .find_missing(vec![blob_digest(BLOB)])
        .expect("find_missing outlasts the drain");

    assert!(missing.is_empty());
    let observed = observed.lock().unwrap();
    assert!(observed.refused > 1, "refused {} times", observed.refused);
    assert_eq!(observed.served, 1);
    assert_eq!(
        observed.connections.len(),
        observed.refused + 1,
        "every refusal moved the next attempt to a new connection"
    );
}
