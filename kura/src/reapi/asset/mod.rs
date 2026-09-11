mod http;
mod request;
#[cfg(test)]
mod tests;

use std::{
    collections::HashMap,
    sync::{Arc, Mutex, Weak},
    time::{SystemTime, UNIX_EPOCH},
};

use bazel_remote_apis::build::bazel::remote::{
    asset::v1::{
        self as asset,
        fetch_server::{Fetch, FetchServer},
    },
    execution::v2::{Digest, digest_function},
};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex as AsyncMutex, Semaphore};
use tonic::{Request, Response, Status};

use super::service::{GrpcRequestSpec, ReapiService, namespace_from_instance, require_sha256};
use crate::{
    artifact::producer::ArtifactProducer, memory::MemoryPressure, replication::replication_targets,
    utils::blob_key,
};
use request::{FetchSpec, MAX_REQUEST_BYTES};

const MAX_CONCURRENT_FETCHES: usize = 32;

#[derive(Clone)]
pub(super) struct AssetService {
    reapi: ReapiService,
    slots: Arc<Semaphore>,
    flights: Arc<Mutex<HashMap<String, Weak<AsyncMutex<()>>>>>,
    http: http::OriginClient,
}

pub(super) fn server(reapi: ReapiService) -> FetchServer<AssetService> {
    FetchServer::new(AssetService::new(reapi)).max_decoding_message_size(MAX_REQUEST_BYTES)
}

#[derive(Serialize, Deserialize)]
struct CachedAsset {
    hash: String,
    size: i64,
    fetched_at_nanos: u128,
}

impl CachedAsset {
    fn digest(&self) -> Digest {
        Digest {
            hash: self.hash.clone(),
            size_bytes: self.size,
        }
    }
}

impl AssetService {
    fn new(reapi: ReapiService) -> Self {
        Self {
            reapi,
            slots: Arc::new(Semaphore::new(MAX_CONCURRENT_FETCHES)),
            flights: Arc::new(Mutex::new(HashMap::new())),
            http: http::OriginClient::default(),
        }
    }

    fn flight(&self, namespace: &str, key: &str) -> Arc<AsyncMutex<()>> {
        let mut flights = self.flights.lock().expect("asset flight lock");
        flights.retain(|_, value| value.strong_count() != 0);
        let key = format!("{namespace}\0{key}");
        if let Some(lock) = flights.get(&key).and_then(Weak::upgrade) {
            return lock;
        }
        let lock = Arc::new(AsyncMutex::new(()));
        flights.insert(key, Arc::downgrade(&lock));
        lock
    }

    async fn cached(
        &self,
        namespace: &str,
        spec: &FetchSpec,
    ) -> Result<Option<(usize, Digest)>, Status> {
        let state = &self.reapi.state;
        for (index, key) in spec.keys.iter().enumerate() {
            let Some(manifest) = state
                .store
                .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace, key)
                .await
                .map_err(Status::internal)?
            else {
                continue;
            };
            if manifest.size > 1024 {
                continue;
            }
            let Some(bytes) = state
                .store
                .read_artifact_bytes_tolerating_promotion(&manifest)
                .await
                .map_err(Status::internal)?
            else {
                continue;
            };
            let Ok(entry) = serde_json::from_slice::<CachedAsset>(&bytes) else {
                continue;
            };
            if entry.fetched_at_nanos < spec.oldest
                || entry.size < 0
                || entry.size as u64 > crate::constants::MAX_MODULE_TOTAL_BYTES
                || entry.hash.len() != 64
                || !entry.hash.bytes().all(|b| b.is_ascii_hexdigit())
            {
                continue;
            }
            let key = blob_key(&format!("{}/{}", entry.hash, entry.size));
            if state
                .store
                .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace, &key)
                .await
                .map_err(Status::internal)?
                .is_some()
            {
                tracing::debug!(namespace, digest = %entry.hash, "remote asset cache hit");
                return Ok(Some((index, entry.digest())));
            }
        }
        Ok(None)
    }

    async fn fetch(
        &self,
        request: &Request<asset::FetchBlobRequest>,
        spec: &FetchSpec,
    ) -> Result<asset::FetchBlobResponse, Status> {
        let namespace = namespace_from_instance(&request.get_ref().instance_name);
        self.reapi
            .authorize_request(
                request,
                GrpcRequestSpec {
                    operation: "artifact.read",
                    namespace_id: Some(namespace),
                },
            )
            .await?;
        if spec.oldest
            > SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        {
            return Err(Status::invalid_argument(
                "oldest_content_accepted is in the future",
            ));
        }
        if let Some((index, digest)) = self.cached(namespace, spec).await? {
            return Ok(success(request, index, digest));
        }
        let _slot = self
            .slots
            .try_acquire()
            .map_err(|_| Status::resource_exhausted("too many concurrent asset fetches"))?;
        // Waiting requests recheck durable metadata after the leader completes. Keeping only
        // weak locks bounds the flight table to the admitted calls and cancels work on disconnect.
        let flight = self.flight(namespace, &spec.keys[0]);
        let _flight = flight.lock().await;
        if let Some((index, digest)) = self.cached(namespace, spec).await? {
            return Ok(success(request, index, digest));
        }
        self.reapi
            .authorize_request(
                request,
                GrpcRequestSpec {
                    operation: "artifact.write",
                    namespace_id: Some(namespace),
                },
            )
            .await?;
        let state = &self.reapi.state;
        if state.memory.pressure() == MemoryPressure::Critical
            || state.store.outbox_saturated(&state.replication_targets())
        {
            return Err(Status::resource_exhausted(
                "server is limiting asset downloads while storage recovers",
            ));
        }
        let mut failure = Status::not_found("asset was not found at any supplied URI");
        let mut failure_index = 0;
        for index in 0..spec.uris.len() {
            // Retry upstream transients, then proceed to the next mirror. Permanent failures
            // and checksum mismatches also allow a different mirror to satisfy the request.
            for attempt in 0..3 {
                let started = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos();
                match self.download(spec, index, namespace).await {
                    Ok((digest, newly_stored)) => {
                        if newly_stored {
                            self.reapi.record_reapi_upload(
                                request.metadata(),
                                namespace,
                                digest.size_bytes as u64,
                            );
                        }
                        let entry = CachedAsset {
                            hash: digest.hash.clone(),
                            size: digest.size_bytes,
                            fetched_at_nanos: started,
                        };
                        let bytes =
                            serde_json::to_vec(&entry).expect("serializable asset metadata");
                        let targets = replication_targets(state);
                        // Only associate the successful origin's effective headers with its content.
                        state
                            .store
                            .persist_inline_artifact_from_bytes_damped_and_enqueue(
                                ArtifactProducer::Reapi,
                                namespace,
                                &spec.keys[index],
                                "application/json",
                                &bytes,
                                &targets,
                                None,
                                None,
                            )
                            .await
                            .map_err(|_| Status::internal("failed to store asset metadata"))?;
                        state.notify.notify_one();
                        tracing::debug!(namespace, digest = %digest.hash, "remote asset fetched and cached");
                        return Ok(success(request, index, digest));
                    }
                    Err(error) => {
                        let retry = error.code() == tonic::Code::Unavailable;
                        failure = error;
                        failure_index = index;
                        if !retry || attempt == 2 {
                            break;
                        }
                        tokio::time::sleep(std::time::Duration::from_millis(250 << attempt)).await;
                    }
                }
            }
        }
        Ok(asset::FetchBlobResponse {
            status: Some(bazel_remote_apis::google::rpc::Status {
                code: failure.code() as i32,
                message: failure.message().to_owned(),
                details: vec![],
            }),
            uri: request.get_ref().uris[failure_index].clone(),
            ..Default::default()
        })
    }
}

fn success(
    request: &Request<asset::FetchBlobRequest>,
    index: usize,
    digest: Digest,
) -> asset::FetchBlobResponse {
    asset::FetchBlobResponse {
        status: Some(bazel_remote_apis::google::rpc::Status::default()),
        uri: request.get_ref().uris[index].clone(),
        // Origin headers may contain credentials. They are neither stored nor echoed.
        qualifiers: vec![],
        expires_at: None,
        blob_digest: Some(digest),
        digest_function: digest_function::Value::Sha256 as i32,
    }
}

#[tonic::async_trait]
impl Fetch for AssetService {
    async fn fetch_blob(
        &self,
        request: Request<asset::FetchBlobRequest>,
    ) -> Result<Response<asset::FetchBlobResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let spec = FetchSpec::parse(request.get_ref())?;
        let result = tokio::select! {
            biased;
            _ = self.reapi.state.runtime.wait_for_drain() => {
                return Err(Status::unavailable("server is draining"));
            }
            result = tokio::time::timeout(spec.timeout, self.fetch(&request, &spec)) => result,
        };
        let response = match result {
            Ok(result) => result?,
            Err(_) => asset::FetchBlobResponse {
                status: Some(bazel_remote_apis::google::rpc::Status {
                    code: tonic::Code::DeadlineExceeded as i32,
                    message: "asset fetch exceeded its timeout".into(),
                    details: vec![],
                }),
                ..Default::default()
            },
        };
        Ok(Response::new(response))
    }

    async fn fetch_directory(
        &self,
        _request: Request<asset::FetchDirectoryRequest>,
    ) -> Result<Response<asset::FetchDirectoryResponse>, Status> {
        Err(Status::unimplemented("directory fetching is not supported"))
    }
}
