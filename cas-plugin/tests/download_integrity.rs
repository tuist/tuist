use api::{
    action_cache_server::{ActionCache, ActionCacheServer},
    content_addressable_storage_server::{
        ContentAddressableStorage, ContentAddressableStorageServer,
    },
};
use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use bazel_remote_apis::google::rpc::Status as BlobStatus;
use std::{
    net::TcpListener,
    pin::Pin,
    sync::{Arc, Mutex},
};
use tonic::{Request, Response, Status};
use tuist_cas_plugin::{
    reapi::{blob_digest, Remote, RemoteConfig},
    token::TokenProvider,
};

const INTACT: &[u8] = b"intact frame bytes";
const DAMAGED: &[u8] = b"damaged frame bytes";

#[derive(Default)]
struct Calls {
    reads: usize,
}

struct Server {
    calls: Arc<Mutex<Calls>>,
}

/// Serves `DAMAGED` under `INTACT`'s digest for the first blob and the intact
/// bytes for the second, so one response carries both outcomes.
#[tonic::async_trait]
impl ContentAddressableStorage for Server {
    async fn batch_read_blobs(
        &self,
        request: Request<api::BatchReadBlobsRequest>,
    ) -> Result<Response<api::BatchReadBlobsResponse>, Status> {
        self.calls.lock().unwrap().reads += 1;
        let intact = blob_digest(INTACT);
        Ok(Response::new(api::BatchReadBlobsResponse {
            responses: request
                .into_inner()
                .digests
                .into_iter()
                .map(|digest| api::batch_read_blobs_response::Response {
                    data: if digest == intact {
                        DAMAGED.to_vec()
                    } else {
                        b"second blob".to_vec()
                    },
                    digest: Some(digest),
                    status: Some(BlobStatus::default()),
                    ..Default::default()
                })
                .collect(),
        }))
    }

    async fn find_missing_blobs(
        &self,
        _: Request<api::FindMissingBlobsRequest>,
    ) -> Result<Response<api::FindMissingBlobsResponse>, Status> {
        Err(Status::unimplemented("unused"))
    }

    async fn batch_update_blobs(
        &self,
        _: Request<api::BatchUpdateBlobsRequest>,
    ) -> Result<Response<api::BatchUpdateBlobsResponse>, Status> {
        Err(Status::unimplemented("unused"))
    }

    async fn split_blob(
        &self,
        _: Request<api::SplitBlobRequest>,
    ) -> Result<Response<api::SplitBlobResponse>, Status> {
        Err(Status::unimplemented("unused"))
    }

    async fn splice_blob(
        &self,
        _: Request<api::SpliceBlobRequest>,
    ) -> Result<Response<api::SpliceBlobResponse>, Status> {
        Err(Status::unimplemented("unused"))
    }

    type GetTreeStream = Pin<
        Box<
            dyn tonic::codegen::tokio_stream::Stream<Item = Result<api::GetTreeResponse, Status>>
                + Send,
        >,
    >;

    async fn get_tree(
        &self,
        _: Request<api::GetTreeRequest>,
    ) -> Result<Response<Self::GetTreeStream>, Status> {
        Err(Status::unimplemented("unused"))
    }
}

/// Answers every action lookup with two inlined outputs, the first damaged,
/// and the snapshot key with a payload that does not match its digest.
#[tonic::async_trait]
impl ActionCache for Server {
    async fn get_action_result(
        &self,
        request: Request<api::GetActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        let snapshot = request.get_ref().action_digest
            == Some(blob_digest(tuist_cas_plugin::reapi::SNAPSHOT_ACTION_KEY));
        let output_files = if snapshot {
            vec![api::OutputFile {
                path: "snapshot".into(),
                digest: Some(blob_digest(INTACT)),
                contents: DAMAGED.to_vec(),
                ..Default::default()
            }]
        } else {
            vec![
                api::OutputFile {
                    path: "00ff".into(),
                    digest: Some(blob_digest(INTACT)),
                    contents: DAMAGED.to_vec(),
                    ..Default::default()
                },
                api::OutputFile {
                    path: "ff00".into(),
                    digest: Some(blob_digest(b"second blob")),
                    contents: b"second blob".to_vec(),
                    ..Default::default()
                },
            ]
        };
        Ok(Response::new(api::ActionResult {
            output_files,
            ..Default::default()
        }))
    }

    async fn update_action_result(
        &self,
        _: Request<api::UpdateActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        Err(Status::unimplemented("unused"))
    }
}

fn server() -> (
    Arc<Remote>,
    Arc<Mutex<Calls>>,
    tokio::sync::oneshot::Sender<()>,
) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let address = listener.local_addr().unwrap();
    let calls = Arc::new(Mutex::new(Calls::default()));
    let observed = calls.clone();
    let (stop, stopped) = tokio::sync::oneshot::channel();
    std::thread::spawn(move || {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(async {
                tonic::transport::Server::builder()
                    .add_service(ActionCacheServer::new(Server {
                        calls: calls.clone(),
                    }))
                    .add_service(ContentAddressableStorageServer::new(Server { calls }))
                    .serve_with_incoming_shutdown(
                        tonic::transport::server::TcpIncoming::from(
                            tokio::net::TcpListener::from_std(listener).unwrap(),
                        ),
                        async {
                            let _ = stopped.await;
                        },
                    )
                    .await
                    .unwrap();
            });
    });
    (
        Remote::new(
            RemoteConfig {
                grpc_url: format!("http://{address}"),
                instance: "test".into(),
            },
            TokenProvider::from_env(),
        ),
        observed,
        stop,
    )
}

#[test]
fn whole_blob_reads_treat_bytes_that_fail_their_digest_as_absent() {
    let (remote, calls, _stop) = server();
    let damaged = blob_digest(INTACT);
    let intact = blob_digest(b"second blob");

    let read = remote.batch_read(&[damaged.clone(), intact.clone()]).unwrap();

    assert!(!read.contains_key(&damaged.hash));
    assert_eq!(read[&intact.hash], b"second blob");
    assert_eq!(calls.lock().unwrap().reads, 1);
}

#[test]
fn inlined_contents_that_fail_their_digest_are_read_again() {
    let (remote, _calls, _stop) = server();

    let manifest = remote.get_action(b"action").unwrap().unwrap();

    assert_eq!(manifest[0].blob, blob_digest(INTACT));
    assert_eq!(manifest[0].contents, None);
    assert_eq!(manifest[1].contents.as_deref(), Some(&b"second blob"[..]));
}

#[test]
fn a_snapshot_that_fails_its_digest_is_not_used() {
    let (remote, _calls, _stop) = server();

    assert!(remote.get_snapshot(None, None).is_err());
}
