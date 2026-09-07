use api::{
    capabilities_server::{Capabilities, CapabilitiesServer},
    content_addressable_storage_server::{
        ContentAddressableStorage, ContentAddressableStorageServer,
    },
};
use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use bazel_remote_apis::google::rpc::Status as BlobStatus;
use std::{
    collections::HashMap,
    net::TcpListener,
    pin::Pin,
    sync::{Arc, Mutex},
};
use tonic::{Request, Response, Status};
use tuist_cas_plugin::{
    reapi::{blob_digest, Remote, RemoteConfig},
    token::TokenProvider,
};

#[derive(Clone, Copy)]
enum Mode {
    Old,
    Disabled,
    UnknownParameters,
    Mixed,
    Evicted,
    Unrequested,
    Incomplete,
    InvalidRecipe,
    CorruptDownload,
    MissingDownload,
}

#[derive(Default)]
struct Calls {
    capabilities: usize,
    missing: usize,
    splice: usize,
    split: usize,
    reads: usize,
    blobs: HashMap<String, Vec<u8>>,
}

struct Server {
    mode: Mode,
    calls: Arc<Mutex<Calls>>,
}

#[tonic::async_trait]
impl Capabilities for Server {
    async fn get_capabilities(
        &self,
        _: Request<api::GetCapabilitiesRequest>,
    ) -> Result<Response<api::ServerCapabilities>, Status> {
        self.calls.lock().unwrap().capabilities += 1;
        if matches!(self.mode, Mode::Old) {
            return Err(Status::unimplemented("old server"));
        }
        Ok(Response::new(api::ServerCapabilities {
            cache_capabilities: Some(api::CacheCapabilities {
                split_blob_support: !matches!(self.mode, Mode::Disabled),
                splice_blob_support: !matches!(self.mode, Mode::Disabled),
                fast_cdc_2020_params: Some(api::FastCdc2020Params {
                    avg_chunk_size_bytes: 512 * 1024,
                    seed: if matches!(self.mode, Mode::UnknownParameters) {
                        1
                    } else {
                        0
                    },
                }),
                ..Default::default()
            }),
            ..Default::default()
        }))
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for Server {
    async fn batch_update_blobs(
        &self,
        request: Request<api::BatchUpdateBlobsRequest>,
    ) -> Result<Response<api::BatchUpdateBlobsResponse>, Status> {
        let mut calls = self.calls.lock().unwrap();
        if matches!(self.mode, Mode::Incomplete) {
            return Ok(Response::new(api::BatchUpdateBlobsResponse::default()));
        }
        Ok(Response::new(api::BatchUpdateBlobsResponse {
            responses: request
                .into_inner()
                .requests
                .into_iter()
                .map(|item| {
                    calls.blobs.insert(
                        item.digest.as_ref().unwrap().hash.clone(),
                        item.data.to_vec(),
                    );
                    api::batch_update_blobs_response::Response {
                        digest: item.digest,
                        status: Some(BlobStatus::default()),
                    }
                })
                .collect(),
        }))
    }
    async fn find_missing_blobs(
        &self,
        request: Request<api::FindMissingBlobsRequest>,
    ) -> Result<Response<api::FindMissingBlobsResponse>, Status> {
        self.calls.lock().unwrap().missing += 1;
        Ok(Response::new(api::FindMissingBlobsResponse {
            missing_blob_digests: if matches!(self.mode, Mode::Unrequested) {
                vec![blob_digest(b"unrequested")]
            } else {
                request.into_inner().blob_digests
            },
        }))
    }
    async fn splice_blob(
        &self,
        _: Request<api::SpliceBlobRequest>,
    ) -> Result<Response<api::SpliceBlobResponse>, Status> {
        self.calls.lock().unwrap().splice += 1;
        if matches!(self.mode, Mode::Evicted) {
            Err(Status::not_found("evicted"))
        } else {
            Err(Status::unimplemented("mixed-version node"))
        }
    }
    async fn split_blob(
        &self,
        request: Request<api::SplitBlobRequest>,
    ) -> Result<Response<api::SplitBlobResponse>, Status> {
        let mut calls = self.calls.lock().unwrap();
        calls.split += 1;
        if !matches!(
            self.mode,
            Mode::InvalidRecipe | Mode::CorruptDownload | Mode::MissingDownload
        ) {
            return Err(Status::unimplemented("mixed-version server"));
        }
        let digest = request.into_inner().blob_digest.unwrap();
        let bytes = calls.blobs[&digest.hash].clone();
        let chunks = bytes
            .chunks(1024 * 1024)
            .map(|bytes| {
                let digest = blob_digest(bytes);
                calls.blobs.insert(digest.hash.clone(), bytes.to_vec());
                digest
            })
            .collect::<Vec<_>>();
        Ok(Response::new(api::SplitBlobResponse {
            chunk_digests: if matches!(self.mode, Mode::InvalidRecipe) {
                vec![api::Digest {
                    hash: "a".repeat(64),
                    size_bytes: -1,
                }]
            } else {
                chunks
            },
            chunking_function: api::chunking_function::Value::FastCdc2020 as i32,
        }))
    }
    async fn batch_read_blobs(
        &self,
        request: Request<api::BatchReadBlobsRequest>,
    ) -> Result<Response<api::BatchReadBlobsResponse>, Status> {
        let mut calls = self.calls.lock().unwrap();
        calls.reads += 1;
        Ok(Response::new(api::BatchReadBlobsResponse {
            responses: request
                .into_inner()
                .digests
                .into_iter()
                .map(|digest| {
                    let mut bytes = calls.blobs[&digest.hash].clone();
                    let mut code = 0;
                    if digest.size_bytes <= 1024 * 1024 {
                        if matches!(self.mode, Mode::CorruptDownload) {
                            bytes.fill(0);
                        }
                        if matches!(self.mode, Mode::MissingDownload) {
                            bytes.clear();
                            code = 5;
                        }
                    }
                    api::batch_read_blobs_response::Response {
                        digest: Some(digest),
                        data: bytes,
                        status: Some(BlobStatus {
                            code,
                            ..Default::default()
                        }),
                        ..Default::default()
                    }
                })
                .collect(),
        }))
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

#[test]
fn download_negotiation_and_bad_chunk_responses_fall_back_to_whole_blobs() {
    for (index, mode) in [
        Mode::Old,
        Mode::Disabled,
        Mode::UnknownParameters,
        Mode::Mixed,
        Mode::InvalidRecipe,
        Mode::CorruptDownload,
        Mode::MissingDownload,
    ]
    .into_iter()
    .enumerate()
    {
        let (remote, calls, _stop) = server(mode);
        let directory = std::env::temp_dir().join(format!(
            "chunk-download-wire-{}-{index}",
            std::process::id()
        ));
        remote.enable_chunk_cache(directory.clone(), "tenant/project");
        let bytes = vec![7; 3 * 1024 * 1024];
        let digest = blob_digest(&bytes);
        calls
            .lock()
            .unwrap()
            .blobs
            .insert(digest.hash.clone(), bytes.clone());
        for _ in 0..2 {
            assert_eq!(
                remote.batch_read(&[digest.clone()]).unwrap()[&digest.hash],
                bytes
            );
        }
        let observed = calls.lock().unwrap();
        assert_eq!(observed.capabilities, 1);
        if matches!(mode, Mode::Old | Mode::Disabled | Mode::UnknownParameters) {
            assert_eq!(observed.split, 0);
        }
        if matches!(mode, Mode::Mixed) {
            assert_eq!(observed.split, 1);
        }
        assert!(observed.reads >= 2);
        if directory.exists() {
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}

fn server(
    mode: Mode,
) -> (
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
                    .add_service(CapabilitiesServer::new(Server {
                        mode,
                        calls: calls.clone(),
                    }))
                    .add_service(ContentAddressableStorageServer::new(Server { mode, calls }))
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
fn old_disabled_and_unknown_servers_receive_only_legacy_uploads() {
    for mode in [Mode::Old, Mode::Disabled, Mode::UnknownParameters] {
        let (remote, calls, _stop) = server(mode);
        let bytes = vec![1; 3 * 1024 * 1024];
        for _ in 0..2 {
            remote
                .batch_update(vec![(blob_digest(&bytes), bytes.clone())])
                .unwrap();
        }
        let calls = calls.lock().unwrap();
        assert_eq!(calls.capabilities, 1);
        assert_eq!((calls.missing, calls.splice), (0, 0));
        assert_eq!(calls.blobs[&blob_digest(&bytes).hash], bytes);
    }
}

#[test]
fn small_blobs_do_not_probe_capabilities() {
    let (remote, calls, _stop) = server(Mode::Old);
    remote
        .batch_update(vec![(blob_digest(b"small"), b"small".to_vec())])
        .unwrap();
    assert_eq!(calls.lock().unwrap().capabilities, 0);
}

#[test]
fn mixed_version_and_eviction_fall_back_to_a_complete_legacy_blob() {
    for mode in [Mode::Mixed, Mode::Evicted] {
        let (remote, calls, _stop) = server(mode);
        let bytes = vec![1; 3 * 1024 * 1024];
        remote
            .batch_update(vec![(blob_digest(&bytes), bytes.clone())])
            .unwrap();
        assert_eq!(
            calls.lock().unwrap().blobs[&blob_digest(&bytes).hash],
            bytes
        );
        assert_eq!(calls.lock().unwrap().splice, 1);
        if matches!(mode, Mode::Mixed) {
            remote
                .batch_update(vec![(blob_digest(&bytes), bytes.clone())])
                .unwrap();
            assert_eq!(calls.lock().unwrap().splice, 1);
        }
    }
}

#[test]
fn malformed_chunk_responses_cannot_be_published() {
    for mode in [Mode::Unrequested, Mode::Incomplete] {
        let (remote, calls, _stop) = server(mode);
        let bytes = vec![1; 3 * 1024 * 1024];
        assert!(remote
            .batch_update(vec![(blob_digest(&bytes), bytes)])
            .is_err());
        assert_eq!(calls.lock().unwrap().splice, 0);
    }
}
