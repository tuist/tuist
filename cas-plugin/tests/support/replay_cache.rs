//! Loopback-only REAPI fixture for cold-replay tests. It deliberately serves
//! manifests without inline contents, so restores exercise actual blob RPCs.
use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    net::TcpListener,
    pin::Pin,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
};
use tonic::{Request, Response, Status};

type Key = (String, String, i64);

#[derive(Default)]
pub struct State {
    pub actions: Mutex<HashMap<Key, api::ActionResult>>,
    pub blobs: Mutex<HashMap<Key, Vec<u8>>>,
    pub action_reads: AtomicUsize,
    pub blob_reads: AtomicUsize,
    pub before_action_reply: Mutex<Option<Box<dyn FnOnce() + Send>>>,
}

#[derive(Clone)]
struct Server(Arc<State>);

impl std::ops::Deref for Server {
    type Target = State;
    fn deref(&self) -> &State {
        &self.0
    }
}

fn key(instance: &str, digest: &api::Digest) -> Key {
    (instance.into(), digest.hash.clone(), digest.size_bytes)
}

#[tonic::async_trait]
impl api::action_cache_server::ActionCache for Server {
    async fn get_action_result(
        &self,
        request: Request<api::GetActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        self.action_reads.fetch_add(1, Ordering::Relaxed);
        let request = request.into_inner();
        let digest = request
            .action_digest
            .ok_or_else(|| Status::invalid_argument("digest"))?;
        self.actions
            .lock()
            .unwrap()
            .get(&key(&request.instance_name, &digest))
            .cloned()
            .map(Response::new)
            .ok_or_else(|| Status::not_found("action"))
    }

    async fn update_action_result(
        &self,
        request: Request<api::UpdateActionResultRequest>,
    ) -> Result<Response<api::ActionResult>, Status> {
        let request = request.into_inner();
        let digest = request
            .action_digest
            .ok_or_else(|| Status::invalid_argument("digest"))?;
        let result = request
            .action_result
            .ok_or_else(|| Status::invalid_argument("result"))?;
        self.actions
            .lock()
            .unwrap()
            .insert(key(&request.instance_name, &digest), result.clone());
        if let Some(before_reply) = self.before_action_reply.lock().unwrap().take() {
            before_reply();
        }
        Ok(Response::new(result))
    }
}

#[tonic::async_trait]
impl api::content_addressable_storage_server::ContentAddressableStorage for Server {
    async fn batch_read_blobs(
        &self,
        request: Request<api::BatchReadBlobsRequest>,
    ) -> Result<Response<api::BatchReadBlobsResponse>, Status> {
        self.blob_reads.fetch_add(1, Ordering::Relaxed);
        let request = request.into_inner();
        let blobs = self.blobs.lock().unwrap();
        Ok(Response::new(api::BatchReadBlobsResponse {
            responses: request
                .digests
                .into_iter()
                .map(|digest| {
                    let data = blobs.get(&key(&request.instance_name, &digest)).cloned();
                    api::batch_read_blobs_response::Response {
                        digest: Some(digest),
                        status: Some(bazel_remote_apis::google::rpc::Status {
                            code: if data.is_some() { 0 } else { 5 },
                            ..Default::default()
                        }),
                        data: data.unwrap_or_default(),
                        ..Default::default()
                    }
                })
                .collect(),
        }))
    }

    async fn batch_update_blobs(
        &self,
        request: Request<api::BatchUpdateBlobsRequest>,
    ) -> Result<Response<api::BatchUpdateBlobsResponse>, Status> {
        let request = request.into_inner();
        let mut blobs = self.blobs.lock().unwrap();
        let mut responses = Vec::new();
        for entry in request.requests {
            let digest = entry
                .digest
                .ok_or_else(|| Status::invalid_argument("digest"))?;
            if format!("{:x}", Sha256::digest(&entry.data)) != digest.hash
                || entry.data.len() as i64 != digest.size_bytes
            {
                return Err(Status::invalid_argument("checksum"));
            }
            blobs.insert(key(&request.instance_name, &digest), entry.data);
            responses.push(api::batch_update_blobs_response::Response {
                digest: Some(digest),
                status: Some(Default::default()),
            });
        }
        Ok(Response::new(api::BatchUpdateBlobsResponse { responses }))
    }

    async fn find_missing_blobs(
        &self,
        request: Request<api::FindMissingBlobsRequest>,
    ) -> Result<Response<api::FindMissingBlobsResponse>, Status> {
        let request = request.into_inner();
        let blobs = self.blobs.lock().unwrap();
        Ok(Response::new(api::FindMissingBlobsResponse {
            missing_blob_digests: request
                .blob_digests
                .into_iter()
                .filter(|digest| !blobs.contains_key(&key(&request.instance_name, digest)))
                .collect(),
        }))
    }

    async fn split_blob(
        &self,
        _: Request<api::SplitBlobRequest>,
    ) -> Result<Response<api::SplitBlobResponse>, Status> {
        Err(Status::unimplemented("whole-blob fixture"))
    }

    async fn splice_blob(
        &self,
        _: Request<api::SpliceBlobRequest>,
    ) -> Result<Response<api::SpliceBlobResponse>, Status> {
        Err(Status::unimplemented("whole-blob fixture"))
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

pub struct Cache {
    pub url: String,
    pub state: Arc<State>,
    _stop: tokio::sync::oneshot::Sender<()>,
}

pub fn start() -> Cache {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let state = Arc::new(State::default());
    let server = Server(state.clone());
    let (stop, stopped) = tokio::sync::oneshot::channel();
    std::thread::spawn(move || {
        tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(async {
            tonic::transport::Server::builder()
                .add_service(api::action_cache_server::ActionCacheServer::new(server.clone())
                    .max_decoding_message_size(64 * 1024 * 1024)
                    .max_encoding_message_size(64 * 1024 * 1024))
                .add_service(api::content_addressable_storage_server::ContentAddressableStorageServer::new(server)
                    .max_decoding_message_size(64 * 1024 * 1024)
                    .max_encoding_message_size(64 * 1024 * 1024))
                .serve_with_incoming_shutdown(
                    tonic::transport::server::TcpIncoming::from(tokio::net::TcpListener::from_std(listener).unwrap()),
                    async { let _ = stopped.await; },
                ).await.unwrap();
        });
    });
    Cache {
        url,
        state,
        _stop: stop,
    }
}
