use std::{
    collections::BTreeMap,
    error::Error,
    future::Future,
    pin::Pin,
    task::{Context, Poll},
    time::{Duration, Instant},
};

use bazel_remote_apis::{
    build::bazel::{
        remote::execution::v2::{
            self as reapi,
            action_cache_server::{ActionCache, ActionCacheServer},
            capabilities_server::{Capabilities, CapabilitiesServer},
            content_addressable_storage_server::{
                ContentAddressableStorage, ContentAddressableStorageServer,
            },
        },
        semver::SemVer,
    },
    google::{
        bytestream::{
            self,
            byte_stream_server::{ByteStream, ByteStreamServer},
        },
        rpc::Status as RpcStatus,
    },
};
use bytes::Bytes;
use futures_util::{StreamExt, future::BoxFuture};
use http_body_util::{BodyExt, combinators::UnsyncBoxBody};
use prost::Message;
use sha2::{Digest as _, Sha256};
use tokio::net::TcpListener;
use tokio_stream::wrappers::TcpListenerStream;
use tokio_util::io::ReaderStream;
use tonic::{
    Request, Response, Status,
    body::Body as TonicBody,
    codegen::{Body as HttpBody, Service, http},
    transport::{Identity, Server, ServerTlsConfig},
};
use tower::Layer;

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    config::GrpcTlsConfig,
    constants::MAX_MODULE_TOTAL_BYTES,
    extension::{AccessDecision, ExtensionContext, Principal},
    replication::replication_targets,
    state::SharedState,
    utils::{action_cache_key, blob_key, temp_file_path},
};

const DEFAULT_INSTANCE_NAME: &str = "default";
const REAPI_READ_STREAM_CHUNK_BYTES: usize = 512 * 1024;
const REAPI_MATERIALIZATION_REJECTED_ACTION: &str = "reapi_materialization_rejected";
type BoxError = Box<dyn Error + Send + Sync + 'static>;
type GrpcAccountingBody = UnsyncBoxBody<Bytes, BoxError>;

#[derive(Clone)]
pub struct ReapiService {
    state: SharedState,
}

#[derive(Clone)]
struct GrpcExtensionSpec<'a> {
    route: &'a str,
    operation: &'a str,
    namespace_id: Option<&'a str>,
    producer: Option<&'a str>,
    artifact_key: Option<String>,
    artifact_hash: Option<String>,
}

pub async fn serve<F>(listener: TcpListener, state: SharedState, shutdown: F) -> Result<(), String>
where
    F: Future<Output = ()> + Send + 'static,
{
    let tls = state.config.grpc_tls.clone();
    let service = ReapiService {
        state: state.clone(),
    };
    let capabilities = CapabilitiesServer::new(service.clone()).max_decoding_message_size(64 << 20);
    let action_cache = ActionCacheServer::new(service.clone()).max_decoding_message_size(64 << 20);
    let cas =
        ContentAddressableStorageServer::new(service.clone()).max_decoding_message_size(64 << 20);
    let byte_stream = ByteStreamServer::new(service).max_decoding_message_size(64 << 20);

    let mut builder = Server::builder()
        .max_connection_age(Duration::from_secs(300))
        .max_connection_age_grace(Duration::from_secs(300))
        .layer(GrpcRequestAccountingLayer { state });
    if let Some(tls) = tls {
        builder = builder
            .tls_config(load_grpc_tls_config(&tls).await?)
            .map_err(|error| format!("gRPC TLS configuration error: {error}"))?;
    }

    builder
        .add_service(capabilities)
        .add_service(action_cache)
        .add_service(cas)
        .add_service(byte_stream)
        .serve_with_incoming_shutdown(TcpListenerStream::new(listener), shutdown)
        .await
        .map_err(|error| format!("gRPC server error: {error}"))
}

#[derive(Clone)]
struct GrpcRequestAccountingLayer {
    state: SharedState,
}

impl<S> Layer<S> for GrpcRequestAccountingLayer {
    type Service = GrpcRequestAccountingService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        GrpcRequestAccountingService {
            inner,
            state: self.state.clone(),
        }
    }
}

#[derive(Clone)]
struct GrpcRequestAccountingService<S> {
    inner: S,
    state: SharedState,
}

impl<S, ResBody> Service<http::Request<TonicBody>> for GrpcRequestAccountingService<S>
where
    S: Service<http::Request<TonicBody>, Response = http::Response<ResBody>> + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
    ResBody: HttpBody<Data = Bytes> + Send + 'static,
    ResBody::Error: Into<BoxError> + 'static,
{
    type Response = http::Response<GrpcAccountingBody>;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: http::Request<TonicBody>) -> Self::Future {
        let started_at = Instant::now();
        let route = request.uri().path().to_owned();
        let guard = self.state.start_grpc_request();
        let state = self.state.clone();
        let future = self.inner.call(request);
        Box::pin(async move {
            let response = future.await?;
            // Sample latency once the response is ready, before the body
            // streams, so long ByteStream reads do not inflate the signal.
            state.runtime.record_public_request_latency(
                &state.metrics,
                "grpc",
                &route,
                started_at.elapsed(),
            );
            Ok(response.map(|body| {
                body.map_frame(move |frame| {
                    let _guard = &guard;
                    frame
                })
                .map_err(|error| -> BoxError { error.into() })
                .boxed_unsync()
            }))
        })
    }
}

async fn load_grpc_tls_config(tls: &GrpcTlsConfig) -> Result<ServerTlsConfig, String> {
    let cert = tokio::fs::read(&tls.cert_path).await.map_err(|error| {
        format!(
            "failed to read gRPC TLS cert at {}: {error}",
            tls.cert_path.display()
        )
    })?;
    let key = tokio::fs::read(&tls.key_path).await.map_err(|error| {
        format!(
            "failed to read gRPC TLS key at {}: {error}",
            tls.key_path.display()
        )
    })?;
    Ok(ServerTlsConfig::new().identity(Identity::from_pem(cert, key)))
}

impl ReapiService {
    async fn authorize_request<T>(
        &self,
        request: &Request<T>,
        spec: GrpcExtensionSpec<'_>,
    ) -> Result<Option<Principal>, Status> {
        if self.state.runtime.is_draining() {
            return Err(Status::unavailable("server is draining"));
        }
        let Some(extension) = self.state.extension.as_ref() else {
            return Ok(None);
        };
        let context = grpc_extension_context(
            &self.state.config.tenant_id,
            &spec,
            request.metadata(),
            None,
        );
        match extension.evaluate_access(&context).await {
            AccessDecision::Allow(principal) => Ok(principal),
            AccessDecision::Deny(deny) => {
                Err(grpc_status_from_http_status(deny.status, &deny.message))
            }
        }
    }

    async fn apply_response_headers<T>(
        &self,
        response: &mut Response<T>,
        spec: GrpcExtensionSpec<'_>,
        principal: Option<&Principal>,
    ) -> Result<(), Status> {
        let Some(extension) = self.state.extension.as_ref() else {
            return Ok(());
        };
        let context = grpc_extension_context(
            &self.state.config.tenant_id,
            &spec,
            response.metadata(),
            Some(200),
        );
        let headers = extension.response_headers(&context, principal).await;
        for (name, value) in headers.headers {
            let metadata_key = tonic::metadata::MetadataKey::from_bytes(name.as_bytes())
                .map_err(|_| Status::internal("invalid extension response header name"))?;
            let metadata_value = tonic::metadata::MetadataValue::try_from(value.as_str())
                .map_err(|_| Status::internal("invalid extension response header value"))?;
            response.metadata_mut().insert(metadata_key, metadata_value);
        }
        Ok(())
    }
}

#[tonic::async_trait]
impl Capabilities for ReapiService {
    async fn get_capabilities(
        &self,
        request: Request<reapi::GetCapabilitiesRequest>,
    ) -> Result<Response<reapi::ServerCapabilities>, Status> {
        let extension = GrpcExtensionSpec {
            route: "reapi.capabilities.get",
            operation: "capabilities.read",
            namespace_id: None,
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut response = Response::new(reapi::ServerCapabilities {
            cache_capabilities: Some(reapi::CacheCapabilities {
                digest_functions: vec![reapi::digest_function::Value::Sha256 as i32],
                action_cache_update_capabilities: Some(reapi::ActionCacheUpdateCapabilities {
                    update_enabled: true,
                }),
                cache_priority_capabilities: None,
                max_batch_total_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                symlink_absolute_path_strategy:
                    reapi::symlink_absolute_path_strategy::Value::Disallowed as i32,
                supported_compressors: Vec::new(),
                supported_batch_update_compressors: Vec::new(),
                max_cas_blob_size_bytes: MAX_MODULE_TOTAL_BYTES as i64,
                split_blob_support: false,
                splice_blob_support: false,
                ..Default::default()
            }),
            execution_capabilities: None,
            deprecated_api_version: None,
            low_api_version: Some(SemVer {
                major: 2,
                minor: 0,
                patch: 0,
                prerelease: String::new(),
            }),
            high_api_version: Some(SemVer {
                major: 2,
                minor: 3,
                patch: 0,
                prerelease: String::new(),
            }),
        });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }
}

#[tonic::async_trait]
impl ActionCache for ReapiService {
    async fn get_action_result(
        &self,
        request: Request<reapi::GetActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let digest = request
            .get_ref()
            .action_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing action_digest"))?;
        let key = action_cache_key(&digest_key(digest)?);
        let extension = GrpcExtensionSpec {
            route: "reapi.action_cache.get",
            operation: "artifact.read",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(key.clone()),
            artifact_hash: Some(digest.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut materialization_budget = MaterializationBudget::new(&self.state);
        let (size_bytes, mut action_result) = fetch_keyvalue_proto::<reapi::ActionResult>(
            &self.state,
            namespace_id,
            &key,
            "action result",
            Some(&mut materialization_budget),
        )
        .await?;

        if request.get_ref().inline_stdout
            && action_result.stdout_raw.is_empty()
            && let Some(digest) = &action_result.stdout_digest
            && let Some(bytes) = maybe_read_cas_bytes(
                &self.state,
                namespace_id,
                digest,
                Some(&mut materialization_budget),
            )
            .await?
        {
            action_result.stdout_raw = bytes;
        }
        if request.get_ref().inline_stderr
            && action_result.stderr_raw.is_empty()
            && let Some(digest) = &action_result.stderr_digest
            && let Some(bytes) = maybe_read_cas_bytes(
                &self.state,
                namespace_id,
                digest,
                Some(&mut materialization_budget),
            )
            .await?
        {
            action_result.stderr_raw = bytes;
        }
        if !request.get_ref().inline_output_files.is_empty() {
            for output_file in &mut action_result.output_files {
                if !request
                    .get_ref()
                    .inline_output_files
                    .iter()
                    .any(|path| path == &output_file.path)
                {
                    continue;
                }
                if output_file.contents.is_empty()
                    && let Some(digest) = &output_file.digest
                    && let Some(bytes) = maybe_read_cas_bytes(
                        &self.state,
                        namespace_id,
                        digest,
                        Some(&mut materialization_budget),
                    )
                    .await?
                {
                    output_file.contents = bytes;
                }
            }
        }

        let mut response = Response::new(action_result);
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", size_bytes);
        Ok(response)
    }

    async fn update_action_result(
        &self,
        request: Request<reapi::UpdateActionResultRequest>,
    ) -> Result<Response<reapi::ActionResult>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let digest = request
            .get_ref()
            .action_digest
            .as_ref()
            .ok_or_else(|| Status::invalid_argument("missing action_digest"))?;
        let action_result = request
            .get_ref()
            .action_result
            .clone()
            .ok_or_else(|| Status::invalid_argument("missing action_result"))?;
        let key = action_cache_key(&digest_key(digest)?);
        let extension = GrpcExtensionSpec {
            route: "reapi.action_cache.update",
            operation: "artifact.write",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(key.clone()),
            artifact_hash: Some(digest.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let bytes = action_result.encode_to_vec();
        let targets = replication_targets(&self.state).await;
        let manifest = self
            .state
            .store
            .persist_inline_artifact_from_bytes_and_enqueue(
                ArtifactProducer::Reapi,
                namespace_id,
                &key,
                "application/x-protobuf",
                &bytes,
                &targets,
            )
            .await
            .map_err(|error| Status::internal(format!("failed to store action result: {error}")))?;
        self.state.notify.notify_one();
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
        let mut response = Response::new(action_result);
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }
}

#[tonic::async_trait]
impl ContentAddressableStorage for ReapiService {
    type GetTreeStream =
        Pin<Box<dyn tokio_stream::Stream<Item = Result<reapi::GetTreeResponse, Status>> + Send>>;

    async fn find_missing_blobs(
        &self,
        request: Request<reapi::FindMissingBlobsRequest>,
    ) -> Result<Response<reapi::FindMissingBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.find_missing",
            operation: "artifact.inspect",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut missing = Vec::new();
        for digest in &request.get_ref().blob_digests {
            let key = blob_key(&digest_key(digest)?);
            let exists = self
                .state
                .store
                .artifact_exists(ArtifactProducer::Reapi, namespace_id, &key)
                .await
                .map_err(|error| {
                    Status::internal(format!("failed to inspect CAS blob: {error}"))
                })?;
            if !exists {
                missing.push(digest.clone());
            }
        }

        let mut response = Response::new(reapi::FindMissingBlobsResponse {
            missing_blob_digests: missing,
        });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }

    async fn batch_update_blobs(
        &self,
        request: Request<reapi::BatchUpdateBlobsRequest>,
    ) -> Result<Response<reapi::BatchUpdateBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.batch_update",
            operation: "artifact.write",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut responses = Vec::with_capacity(request.get_ref().requests.len());

        for item in &request.get_ref().requests {
            let digest = match &item.digest {
                Some(digest) => digest.clone(),
                None => {
                    responses.push(reapi::batch_update_blobs_response::Response {
                        digest: None,
                        status: Some(rpc_status(3, "missing digest")),
                    });
                    continue;
                }
            };
            if item.compressor != 0 {
                responses.push(reapi::batch_update_blobs_response::Response {
                    digest: Some(digest),
                    status: Some(rpc_status(3, "compressed uploads are not supported")),
                });
                continue;
            }
            match persist_cas_blob(&self.state, namespace_id, &digest, &item.data).await {
                Ok(()) => responses.push(reapi::batch_update_blobs_response::Response {
                    digest: Some(digest),
                    status: Some(rpc_status(0, "")),
                }),
                Err(error) => responses.push(reapi::batch_update_blobs_response::Response {
                    digest: Some(digest),
                    status: Some(rpc_status(13, error)),
                }),
            }
        }

        let mut response = Response::new(reapi::BatchUpdateBlobsResponse { responses });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }

    async fn batch_read_blobs(
        &self,
        request: Request<reapi::BatchReadBlobsRequest>,
    ) -> Result<Response<reapi::BatchReadBlobsResponse>, Status> {
        require_sha256(request.get_ref().digest_function)?;
        let namespace_id = namespace_from_instance(&request.get_ref().instance_name);
        let extension = GrpcExtensionSpec {
            route: "reapi.cas.batch_read",
            operation: "artifact.read",
            namespace_id: Some(namespace_id),
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let mut responses = Vec::with_capacity(request.get_ref().digests.len());
        let mut materialization_budget = MaterializationBudget::new(&self.state);

        for digest in &request.get_ref().digests {
            let response = match maybe_read_cas_bytes(
                &self.state,
                namespace_id,
                digest,
                Some(&mut materialization_budget),
            )
            .await
            {
                Ok(Some(data)) => reapi::batch_read_blobs_response::Response {
                    digest: Some(digest.clone()),
                    data,
                    compressor: 0,
                    status: Some(rpc_status(0, "")),
                },
                Ok(None) => reapi::batch_read_blobs_response::Response {
                    digest: Some(digest.clone()),
                    data: Vec::new(),
                    compressor: 0,
                    status: Some(rpc_status(5, "blob not found")),
                },
                Err(status) => reapi::batch_read_blobs_response::Response {
                    digest: Some(digest.clone()),
                    data: Vec::new(),
                    compressor: 0,
                    status: Some(rpc_status_from_grpc_status(&status)),
                },
            };
            responses.push(response);
        }

        let mut response = Response::new(reapi::BatchReadBlobsResponse { responses });
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }

    async fn get_tree(
        &self,
        _request: Request<reapi::GetTreeRequest>,
    ) -> Result<Response<Self::GetTreeStream>, Status> {
        Err(Status::unimplemented("GetTree is not supported"))
    }

    async fn split_blob(
        &self,
        _request: Request<reapi::SplitBlobRequest>,
    ) -> Result<Response<reapi::SplitBlobResponse>, Status> {
        Err(Status::unimplemented("SplitBlob is not supported"))
    }

    async fn splice_blob(
        &self,
        _request: Request<reapi::SpliceBlobRequest>,
    ) -> Result<Response<reapi::SpliceBlobResponse>, Status> {
        Err(Status::unimplemented("SpliceBlob is not supported"))
    }
}

#[tonic::async_trait]
impl ByteStream for ReapiService {
    type ReadStream =
        Pin<Box<dyn tokio_stream::Stream<Item = Result<bytestream::ReadResponse, Status>> + Send>>;

    async fn read(
        &self,
        request: Request<bytestream::ReadRequest>,
    ) -> Result<Response<Self::ReadStream>, Status> {
        let resource = parse_read_resource_name(&request.get_ref().resource_name)?;
        let extension = GrpcExtensionSpec {
            route: "reapi.bytestream.read",
            operation: "artifact.read",
            namespace_id: Some(&resource.namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(resource.key.clone()),
            artifact_hash: Some(resource.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        if request.get_ref().read_offset < 0 {
            return Err(Status::invalid_argument("read_offset must be non-negative"));
        }
        if request.get_ref().read_limit < 0 {
            return Err(Status::invalid_argument("read_limit must be non-negative"));
        }
        let manifest = match self
            .state
            .store
            .fetch_artifact_for_serving(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
            )
            .await
        {
            Ok(Some(manifest)) => manifest,
            Ok(None) => {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
                return Err(Status::not_found("blob not found"));
            }
            Err(error) => {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
                return Err(Status::internal(format!(
                    "failed to read CAS blob: {error}"
                )));
            }
        };
        let read_offset = request.get_ref().read_offset as u64;
        if read_offset > manifest.size {
            return Err(Status::out_of_range("read_offset exceeds blob size"));
        }
        let read_limit = if request.get_ref().read_limit == 0 {
            None
        } else {
            Some(request.get_ref().read_limit as u64)
        };
        let bytes_to_read = read_limit
            .unwrap_or_else(|| manifest.size.saturating_sub(read_offset))
            .min(manifest.size.saturating_sub(read_offset));
        let reader = self
            .state
            .store
            .open_artifact_reader_range(&manifest, read_offset, read_limit)
            .await
            .map_err(|error| {
                self.state
                    .metrics
                    .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
                Status::internal(format!("failed to stream blob: {error}"))
            })?;
        self.state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes_to_read);
        let stream =
            ReaderStream::with_capacity(reader, REAPI_READ_STREAM_CHUNK_BYTES).map(move |result| {
                match result {
                    Ok(bytes) => Ok(bytestream::ReadResponse {
                        data: bytes.to_vec(),
                    }),
                    Err(error) => Err(Status::internal(format!(
                        "failed to stream blob chunk: {error}"
                    ))),
                }
            });

        let mut response = Response::new(Box::pin(stream) as Self::ReadStream);
        self.apply_response_headers(&mut response, extension, principal.as_ref())
            .await?;
        Ok(response)
    }

    async fn write(
        &self,
        request: Request<tonic::Streaming<bytestream::WriteRequest>>,
    ) -> Result<Response<bytestream::WriteResponse>, Status> {
        let extension = GrpcExtensionSpec {
            route: "reapi.bytestream.write",
            operation: "artifact.write",
            namespace_id: None,
            producer: Some("reapi"),
            artifact_key: None,
            artifact_hash: None,
        };
        let principal = self.authorize_request(&request, extension).await?;
        let temp_path = temp_file_path(&self.state.config.tmp_dir.join("uploads"), "reapi-write");
        if let Some(parent) = temp_path.parent() {
            self.state
                .io
                .create_dir_all(parent)
                .await
                .map_err(Status::internal)?;
        }
        let mut temp_file = self
            .state
            .io
            .create_file(&temp_path)
            .await
            .map_err(Status::internal)?;
        let mut stream = request.into_inner();
        let mut resource_name = None::<String>;
        let mut resource = None::<BlobResource>;
        let mut written = 0_u64;
        let mut hasher = Sha256::new();
        let mut finished = false;

        while let Some(chunk) = stream.message().await? {
            if finished {
                self.state.io.remove_file_if_exists(&temp_path).await;
                return Err(Status::invalid_argument(
                    "received data after finish_write=true",
                ));
            }
            let chunk_resource_name = if chunk.resource_name.is_empty() {
                resource_name.clone().ok_or_else(|| {
                    Status::invalid_argument("first write request must include resource_name")
                })?
            } else {
                chunk.resource_name.clone()
            };
            if let Some(existing) = &resource_name {
                if existing != &chunk_resource_name {
                    self.state.io.remove_file_if_exists(&temp_path).await;
                    return Err(Status::invalid_argument("resource_name changed mid-stream"));
                }
            } else {
                resource = Some(parse_write_resource_name(&chunk_resource_name)?);
                resource_name = Some(chunk_resource_name);
            }
            if chunk.write_offset < 0 || chunk.write_offset as u64 != written {
                self.state.io.remove_file_if_exists(&temp_path).await;
                return Err(Status::invalid_argument("unexpected write_offset"));
            }
            if !chunk.data.is_empty() {
                tokio::io::AsyncWriteExt::write_all(&mut temp_file, &chunk.data)
                    .await
                    .map_err(|error| {
                        Status::internal(format!("failed to write temp blob: {error}"))
                    })?;
                hasher.update(&chunk.data);
                written = written.saturating_add(chunk.data.len() as u64);
            }
            if chunk.finish_write {
                finished = true;
            }
        }

        let resource = match resource {
            Some(resource) => resource,
            None => {
                self.state.io.remove_file_if_exists(&temp_path).await;
                return Err(Status::invalid_argument("empty write stream"));
            }
        };
        if !finished {
            self.state.io.remove_file_if_exists(&temp_path).await;
            return Err(Status::invalid_argument("write stream did not finish"));
        }
        if written != resource.size_bytes {
            self.state.io.remove_file_if_exists(&temp_path).await;
            return Err(Status::invalid_argument(
                "uploaded blob size did not match digest",
            ));
        }
        let actual_hash = hex::encode(hasher.finalize());
        if actual_hash != resource.hash {
            self.state.io.remove_file_if_exists(&temp_path).await;
            return Err(Status::invalid_argument(
                "uploaded blob digest did not match content",
            ));
        }

        // Flush tokio's internal write buffer to the OS and close the write handle before
        // the blob is persisted. persist_artifact_from_path re-opens this path on a
        // separate descriptor to stat and copy it into a segment; without an explicit
        // flush, tokio::fs::File's lazily-flushed writes race that read and the segment
        // append fails with "appended N bytes, expected M" — which silently breaks remote
        // caching of any action that uploads many blobs concurrently (e.g. cargo build
        // scripts' directory outputs). The HTTP upload path flushes for the same reason.
        tokio::io::AsyncWriteExt::flush(&mut temp_file)
            .await
            .map_err(|error| Status::internal(format!("failed to flush temp blob: {error}")))?;
        drop(temp_file);

        let targets = replication_targets(&self.state).await;
        let manifest = self
            .state
            .store
            .persist_artifact_from_path_and_enqueue(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
                "application/octet-stream",
                &temp_path,
                &targets,
            )
            .await
            .map_err(|error| Status::internal(format!("failed to persist CAS blob: {error}")))?;
        self.state.notify.notify_one();
        self.state
            .metrics
            .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);

        let mut response = Response::new(bytestream::WriteResponse {
            committed_size: written as i64,
        });
        self.apply_response_headers(
            &mut response,
            GrpcExtensionSpec {
                route: "reapi.bytestream.write",
                operation: "artifact.write",
                namespace_id: Some(&resource.namespace_id),
                producer: Some("reapi"),
                artifact_key: Some(resource.key),
                artifact_hash: Some(resource.hash),
            },
            principal.as_ref(),
        )
        .await?;
        Ok(response)
    }

    async fn query_write_status(
        &self,
        request: Request<bytestream::QueryWriteStatusRequest>,
    ) -> Result<Response<bytestream::QueryWriteStatusResponse>, Status> {
        let resource = parse_write_resource_name(&request.get_ref().resource_name)?;
        let extension = GrpcExtensionSpec {
            route: "reapi.bytestream.query_write_status",
            operation: "artifact.inspect",
            namespace_id: Some(&resource.namespace_id),
            producer: Some("reapi"),
            artifact_key: Some(resource.key.clone()),
            artifact_hash: Some(resource.hash.clone()),
        };
        let principal = self.authorize_request(&request, extension.clone()).await?;
        let manifest = self
            .state
            .store
            .fetch_artifact(
                ArtifactProducer::Reapi,
                &resource.namespace_id,
                &resource.key,
            )
            .await
            .map_err(|error| Status::internal(format!("failed to inspect blob status: {error}")))?;

        match manifest {
            Some(manifest) => {
                let mut response = Response::new(bytestream::QueryWriteStatusResponse {
                    committed_size: manifest.size as i64,
                    complete: true,
                });
                self.apply_response_headers(&mut response, extension, principal.as_ref())
                    .await?;
                Ok(response)
            }
            None => Err(Status::not_found("blob not found")),
        }
    }
}

async fn fetch_keyvalue_proto<T>(
    state: &SharedState,
    namespace_id: &str,
    key: &str,
    label: &str,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<(u64, T), Status>
where
    T: Message + Default,
{
    let manifest = match state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, key)
        .await
    {
        Ok(Some(manifest)) => manifest,
        Ok(None) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
            return Err(Status::not_found(format!("{label} not found")));
        }
        Err(error) => {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
            return Err(Status::internal(format!("failed to load {label}: {error}")));
        }
    };
    if let Some(budget) = materialization_budget {
        budget.claim(manifest.size, label)?;
    }
    let bytes = read_manifest_bytes(state, &manifest)
        .await
        .map_err(|error| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
            Status::internal(format!("failed to load {label}: {error}"))
        })?;
    let decoded = T::decode(bytes.as_slice()).map_err(|error| {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        Status::internal(format!("failed to decode {label}: {error}"))
    })?;
    Ok((bytes.len() as u64, decoded))
}

async fn maybe_read_cas_bytes(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    materialization_budget: Option<&mut MaterializationBudget<'_>>,
) -> Result<Option<Vec<u8>>, Status> {
    let key = blob_key(&digest_key(digest)?);
    let Some(manifest) = state
        .store
        .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?
    else {
        state
            .metrics
            .record_artifact_read(ArtifactProducer::Reapi, "not_found", 0);
        return Ok(None);
    };
    if let Some(budget) = materialization_budget {
        budget.claim(manifest.size, "CAS response materialization")?;
    }
    let bytes = read_manifest_bytes(state, &manifest)
        .await
        .inspect_err(|_| {
            state
                .metrics
                .record_artifact_read(ArtifactProducer::Reapi, "error", 0);
        })
        .map_err(Status::internal)?;
    state
        .metrics
        .record_artifact_read(ArtifactProducer::Reapi, "ok", bytes.len() as u64);
    Ok(Some(bytes))
}

async fn persist_cas_blob(
    state: &SharedState,
    namespace_id: &str,
    digest: &reapi::Digest,
    bytes: &[u8],
) -> Result<(), String> {
    validate_digest_bytes(digest, bytes)?;
    let key = blob_key(&digest_key(digest).map_err(|error| error.message().to_owned())?);
    let targets = replication_targets(state).await;
    let manifest = state
        .store
        .persist_artifact_from_bytes_and_enqueue(
            ArtifactProducer::Reapi,
            namespace_id,
            &key,
            "application/octet-stream",
            bytes,
            &targets,
        )
        .await?;
    state.notify.notify_one();
    state
        .metrics
        .record_artifact_write(ArtifactProducer::Reapi, "ok", manifest.size);
    Ok(())
}

async fn read_manifest_bytes(
    state: &SharedState,
    manifest: &ArtifactManifest,
) -> Result<Vec<u8>, String> {
    state.store.read_artifact_bytes(manifest).await
}

struct MaterializationBudget<'a> {
    state: &'a SharedState,
    remaining_bytes: usize,
    held_permits: Vec<tokio::sync::OwnedSemaphorePermit>,
}

impl<'a> MaterializationBudget<'a> {
    fn new(state: &'a SharedState) -> Self {
        Self {
            state,
            remaining_bytes: state.memory.reapi_response_budget_bytes(),
            held_permits: Vec::new(),
        }
    }

    fn claim(&mut self, size_bytes: u64, label: &str) -> Result<(), Status> {
        let requested_bytes = usize::try_from(size_bytes).map_err(|_| {
            self.reject(format!(
                "{label} exceeds the maximum addressable REAPI materialization size"
            ))
        })?;
        if requested_bytes > self.remaining_bytes {
            return Err(self.reject(format!(
                "{label} needs {requested_bytes} bytes but only {} bytes remain in the REAPI materialization budget",
                self.remaining_bytes
            )));
        }
        let pool_bytes = self.state.memory.reapi_materialization_pool_bytes();
        if requested_bytes > pool_bytes {
            return Err(self.reject(format!(
                "{label} needs {requested_bytes} bytes but the node only allows {pool_bytes} bytes of concurrent REAPI response materialization"
            )));
        }
        let permit = self
            .state
            .memory
            .try_acquire_reapi_materialization(requested_bytes)
            .map_err(|_| {
                self.reject(format!(
                    "{label} was rejected because the concurrent REAPI response materialization pool is exhausted"
                ))
            })?;
        self.remaining_bytes -= requested_bytes;
        if let Some(permit) = permit {
            self.held_permits.push(permit);
        }
        Ok(())
    }

    fn reject(&self, message: String) -> Status {
        self.state
            .metrics
            .record_memory_action(REAPI_MATERIALIZATION_REJECTED_ACTION);
        Status::resource_exhausted(message)
    }
}

fn validate_digest_bytes(digest: &reapi::Digest, bytes: &[u8]) -> Result<(), String> {
    if digest.size_bytes < 0 {
        return Err("digest size must be non-negative".to_string());
    }
    if digest.size_bytes as usize != bytes.len() {
        return Err("digest size did not match payload length".to_string());
    }
    let actual_hash = hex::encode(Sha256::digest(bytes));
    if actual_hash != digest.hash {
        return Err("digest hash did not match payload".to_string());
    }
    Ok(())
}

fn digest_key(digest: &reapi::Digest) -> Result<String, Status> {
    if digest.size_bytes < 0 {
        return Err(Status::invalid_argument("digest size must be non-negative"));
    }
    if digest.hash.is_empty() {
        return Err(Status::invalid_argument("digest hash must be present"));
    }
    Ok(format!("{}/{}", digest.hash, digest.size_bytes))
}

fn require_sha256(digest_function: i32) -> Result<(), Status> {
    if digest_function == 0 || digest_function == reapi::digest_function::Value::Sha256 as i32 {
        return Ok(());
    }
    Err(Status::invalid_argument(
        "only SHA256 digests are supported",
    ))
}

fn namespace_from_instance(instance_name: &str) -> &str {
    if instance_name.is_empty() {
        DEFAULT_INSTANCE_NAME
    } else {
        instance_name
    }
}

fn rpc_status(code: i32, message: impl Into<String>) -> RpcStatus {
    RpcStatus {
        code,
        message: message.into(),
        details: Vec::new(),
    }
}

fn rpc_status_from_grpc_status(status: &Status) -> RpcStatus {
    rpc_status(status.code() as i32, status.message())
}

fn grpc_extension_context(
    server_tenant_id: &str,
    spec: &GrpcExtensionSpec<'_>,
    metadata: &tonic::metadata::MetadataMap,
    status_code: Option<u16>,
) -> ExtensionContext {
    ExtensionContext {
        transport: "grpc".into(),
        route: spec.route.to_owned(),
        method: "RPC".into(),
        operation: spec.operation.to_owned(),
        server_tenant_id: server_tenant_id.to_owned(),
        tenant_id: None,
        namespace_id: spec.namespace_id.map(ToOwned::to_owned),
        producer: spec.producer.map(ToOwned::to_owned),
        artifact_key: spec.artifact_key.clone(),
        artifact_hash: spec.artifact_hash.clone(),
        headers: metadata_to_btree(metadata),
        query: BTreeMap::new(),
        status_code,
    }
}

fn metadata_to_btree(metadata: &tonic::metadata::MetadataMap) -> BTreeMap<String, String> {
    metadata
        .iter()
        .filter_map(|entry| match entry {
            tonic::metadata::KeyAndValueRef::Ascii(key, value) => value
                .to_str()
                .ok()
                .map(|value| (key.as_str().to_ascii_lowercase(), value.to_string())),
            tonic::metadata::KeyAndValueRef::Binary(_, _) => None,
        })
        .collect()
}

fn grpc_status_from_http_status(status: u16, message: &str) -> Status {
    match status {
        401 => Status::unauthenticated(message.to_owned()),
        403 => Status::permission_denied(message.to_owned()),
        404 => Status::not_found(message.to_owned()),
        400 => Status::invalid_argument(message.to_owned()),
        429 => Status::resource_exhausted(message.to_owned()),
        503 => Status::unavailable(message.to_owned()),
        _ if status >= 500 => Status::internal(message.to_owned()),
        _ => Status::permission_denied(message.to_owned()),
    }
}

#[derive(Debug, PartialEq, Eq)]
struct BlobResource {
    namespace_id: String,
    hash: String,
    size_bytes: u64,
    key: String,
}

fn parse_read_resource_name(resource_name: &str) -> Result<BlobResource, Status> {
    parse_blob_resource_name(resource_name, false)
}

fn parse_write_resource_name(resource_name: &str) -> Result<BlobResource, Status> {
    parse_blob_resource_name(resource_name, true)
}

fn parse_blob_resource_name(
    resource_name: &str,
    require_upload_prefix: bool,
) -> Result<BlobResource, Status> {
    let parts = resource_name
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let Some(blob_index) = parts.iter().rposition(|part| *part == "blobs") else {
        return Err(Status::invalid_argument(
            "resource_name must contain /blobs/",
        ));
    };
    if blob_index + 2 >= parts.len() {
        return Err(Status::invalid_argument(
            "resource_name is missing digest components",
        ));
    }
    let prefix = &parts[..blob_index];
    let namespace_parts = if prefix.len() >= 2 && prefix[prefix.len() - 2] == "uploads" {
        &prefix[..prefix.len() - 2]
    } else {
        if require_upload_prefix {
            return Err(Status::invalid_argument(
                "write resource_name must include uploads/{uuid}/blobs/{hash}/{size}",
            ));
        }
        prefix
    };
    let hash = parts[blob_index + 1].to_owned();
    let size_bytes = parts[blob_index + 2]
        .parse::<u64>()
        .map_err(|error| Status::invalid_argument(format!("invalid blob size: {error}")))?;
    let namespace_id = if namespace_parts.is_empty() {
        DEFAULT_INSTANCE_NAME.to_string()
    } else {
        namespace_parts.join("/")
    };
    // Key CAS blobs the same way as the digest-based paths (FindMissingBlobs,
    // BatchUpdateBlobs, BatchReadBlobs) which use `blob_key(&digest_key(..))` =
    // "blob/{hash}/{size}". Without the `blob/` prefix, blobs uploaded via ByteStream were
    // stored under "{hash}/{size}" and were invisible to FindMissingBlobs, so REAPI clients
    // (e.g. Bazel) treated the produced outputs as missing and re-executed the action.
    let key = blob_key(&format!("{hash}/{size_bytes}"));

    Ok(BlobResource {
        namespace_id,
        hash,
        size_bytes,
        key,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{convert::Infallible, time::Duration};

    use crate::{
        artifact::producer::ArtifactProducer,
        failpoints::{FailpointAction, FailpointName},
        test_support::test_context,
    };

    #[tokio::test]
    async fn grpc_request_accounting_layer_keeps_guard_until_response_body_drops() {
        let context = test_context(|_| {}).await;
        let layer = GrpcRequestAccountingLayer {
            state: context.state.clone(),
        };
        let mut service = layer.layer(tower::service_fn(
            |_request: http::Request<TonicBody>| async {
                Ok::<_, Infallible>(http::Response::new(TonicBody::empty()))
            },
        ));

        let response = service
            .call(http::Request::new(TonicBody::empty()))
            .await
            .expect("accounting layer should pass through service response");

        assert_eq!(context.state.runtime.grpc_inflight(), 1);
        assert_eq!(context.state.runtime.public_inflight(), 1);

        drop(response);

        assert_eq!(context.state.runtime.grpc_inflight(), 0);
        assert_eq!(context.state.runtime.public_inflight(), 0);
    }

    // Regression test for the missing flush in the ByteStream `write` handler. The
    // handler streams chunks into a temp file with `write_all` and then persists it by
    // re-opening the path on a separate descriptor (stat + copy into a segment).
    // `tokio::fs::File` buffers writes and flushes lazily, so without an explicit flush
    // the persist read races the flush and intermittently fails with
    // "appended N bytes, expected M" — which silently broke remote caching of every
    // action that uploads many blobs concurrently (notably cargo build scripts' directory
    // outputs, e.g. librocksdb-sys). This drives the real gRPC handler with many
    // concurrent multi-chunk uploads and asserts each persists and reads back intact.
    #[tokio::test]
    async fn bytestream_writes_persist_completely_under_concurrency() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let concurrency = 24u32;
        let chunk_size = 32 * 1024;
        let mut writers = Vec::new();
        for index in 0..concurrency {
            let mut client = ByteStreamClient::new(channel.clone());
            writers.push(tokio::spawn(async move {
                // Per-blob-distinct, multi-chunk content so each upload spans many
                // `write_all` calls (leaving buffered bytes for the flush to race).
                let blob: Vec<u8> = (0..384 * 1024u32)
                    .map(|byte| byte.wrapping_mul(31).wrapping_add(index) as u8)
                    .collect();
                let hash = hex::encode(Sha256::digest(&blob));
                let resource = format!("uploads/upload-{index}/blobs/{hash}/{}", blob.len());
                let mut requests = Vec::new();
                let mut offset = 0usize;
                while offset < blob.len() {
                    let end = (offset + chunk_size).min(blob.len());
                    requests.push(bytestream::WriteRequest {
                        resource_name: if offset == 0 {
                            resource.clone()
                        } else {
                            String::new()
                        },
                        write_offset: offset as i64,
                        finish_write: end == blob.len(),
                        data: blob[offset..end].to_vec(),
                    });
                    offset = end;
                }
                let committed = client
                    .write(tokio_stream::iter(requests))
                    .await
                    .expect("concurrent ByteStream write should persist")
                    .into_inner()
                    .committed_size;
                assert_eq!(committed as usize, blob.len());
                (hash, blob)
            }));
        }

        let mut reader = ByteStreamClient::new(channel.clone());
        for writer in writers {
            let (hash, blob) = writer.await.expect("write task should not panic");
            let mut stream = reader
                .read(bytestream::ReadRequest {
                    resource_name: format!("blobs/{hash}/{}", blob.len()),
                    read_offset: 0,
                    read_limit: 0,
                })
                .await
                .expect("blob should be readable back")
                .into_inner();
            let mut roundtrip = Vec::new();
            while let Some(chunk) = stream.message().await.expect("read chunk") {
                roundtrip.extend_from_slice(&chunk.data);
            }
            assert_eq!(roundtrip, blob, "persisted blob must match the upload");
        }

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    // Regression: a CAS blob uploaded via the ByteStream `Write` interface must be reported
    // present by `FindMissingBlobs`. ByteStream Write/Read once keyed blobs as "{hash}/{size}"
    // while FindMissingBlobs/BatchUpdateBlobs/BatchReadBlobs use blob_key() = "blob/{hash}/{size}",
    // so ByteStream-uploaded blobs were invisible to FindMissingBlobs and REAPI clients (e.g.
    // Bazel) re-executed the action that produced them. Drives the real gRPC handlers end to end.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn bytestream_uploaded_blob_is_visible_to_find_missing_blobs() {
        use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;
        use reapi::content_addressable_storage_client::ContentAddressableStorageClient;

        let context = test_context(|_| {}).await;
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let addr = listener.local_addr().expect("listener addr");
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let server_state = context.state.clone();
        let server = tokio::spawn(async move {
            serve(listener, server_state, async move {
                let _ = shutdown_rx.await;
            })
            .await
        });

        let endpoint = format!("http://{addr}");
        let mut channel = None;
        for _ in 0..50 {
            match tonic::transport::Endpoint::from_shared(endpoint.clone())
                .expect("valid endpoint")
                .connect()
                .await
            {
                Ok(connected) => {
                    channel = Some(connected);
                    break;
                }
                Err(_) => tokio::time::sleep(Duration::from_millis(20)).await,
            }
        }
        let channel = channel.expect("gRPC server should accept connections");

        let blob = b"kura reapi bytestream blob-key regression payload".to_vec();
        let hash = hex::encode(Sha256::digest(&blob));
        let len = blob.len();

        // Upload via the ByteStream Write interface, exactly as a REAPI client does for CAS.
        let committed = ByteStreamClient::new(channel.clone())
            .write(tokio_stream::iter(vec![bytestream::WriteRequest {
                resource_name: format!("uploads/regression/blobs/{hash}/{len}"),
                write_offset: 0,
                finish_write: true,
                data: blob.clone(),
            }]))
            .await
            .expect("ByteStream write should succeed")
            .into_inner()
            .committed_size;
        assert_eq!(committed as usize, len);

        // FindMissingBlobs must report it PRESENT — it shares blob_key()'s namespace with Write.
        let missing = ContentAddressableStorageClient::new(channel.clone())
            .find_missing_blobs(reapi::FindMissingBlobsRequest {
                instance_name: String::new(),
                blob_digests: vec![reapi::Digest {
                    hash: hash.clone(),
                    size_bytes: len as i64,
                }],
                digest_function: 0,
            })
            .await
            .expect("find_missing_blobs should succeed")
            .into_inner()
            .missing_blob_digests;
        assert!(
            missing.is_empty(),
            "a ByteStream-uploaded blob must be visible to FindMissingBlobs; got {} missing",
            missing.len()
        );

        let _ = shutdown_tx.send(());
        let _ = server.await;
    }

    #[test]
    fn parses_read_resource_names_with_and_without_instance_names() {
        assert_eq!(
            parse_read_resource_name("blobs/abc/10").expect("resource should parse"),
            BlobResource {
                namespace_id: "default".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
        assert_eq!(
            parse_read_resource_name("bazel/cache/blobs/abc/10")
                .expect("instance-scoped resource should parse"),
            BlobResource {
                namespace_id: "bazel/cache".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
    }

    #[test]
    fn parses_write_resource_names_with_upload_prefix() {
        assert_eq!(
            parse_write_resource_name("buck/cache/uploads/uuid-1/blobs/abc/10")
                .expect("write resource should parse"),
            BlobResource {
                namespace_id: "buck/cache".into(),
                hash: "abc".into(),
                size_bytes: 10,
                key: "blob/abc/10".into(),
            }
        );
    }

    #[test]
    fn rejects_write_resources_without_upload_prefix() {
        let error = parse_write_resource_name("blobs/abc/10")
            .expect_err("write resources should require uploads prefix");
        assert_eq!(error.code(), tonic::Code::InvalidArgument);
    }

    #[tokio::test]
    async fn action_cache_reads_emit_keyvalue_metrics() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        let action_result = reapi::ActionResult::default();
        let bytes = action_result.encode_to_vec();
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = action_cache_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/x-protobuf",
                &bytes,
            )
            .await
            .expect("action result should persist");

        service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(digest),
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("action result should load");

        let rendered = context.state.metrics.render();
        assert!(rendered.contains("kura_artifact_reads_total"));
        assert!(rendered.contains("producer=\"reapi\""));
        assert!(rendered.contains("result=\"ok\""));
    }

    #[tokio::test]
    async fn cas_batch_reads_emit_module_metrics() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        let bytes = b"blob-bytes";
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("cas blob should persist");

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should succeed");

        assert_eq!(response.get_ref().responses.len(), 1);
        assert_eq!(response.get_ref().responses[0].data, bytes);

        let rendered = context.state.metrics.render();
        assert!(rendered.contains("kura_artifact_reads_total"));
        assert!(rendered.contains("producer=\"reapi\""));
        assert!(rendered.contains("result=\"ok\""));
    }

    #[tokio::test]
    async fn cas_batch_reads_mark_oversized_blobs_resource_exhausted_without_spending_budget() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        let oversized_bytes = vec![b'x'; 9 * 1024 * 1024];
        let small_bytes = b"small-bytes";
        let oversized_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&oversized_bytes)),
            size_bytes: oversized_bytes.len() as i64,
        };
        let small_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(small_bytes)),
            size_bytes: small_bytes.len() as i64,
        };
        let oversized_key =
            blob_key(&digest_key(&oversized_digest).expect("digest key should build"));
        let small_key = blob_key(&digest_key(&small_digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &oversized_key,
                "application/octet-stream",
                &oversized_bytes,
            )
            .await
            .expect("oversized cas blob should persist");
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &small_key,
                "application/octet-stream",
                small_bytes,
            )
            .await
            .expect("small cas blob should persist");

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![oversized_digest, small_digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should succeed");

        assert_eq!(response.get_ref().responses.len(), 2);
        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );
        assert!(response.get_ref().responses[0].data.is_empty());
        assert_eq!(
            response.get_ref().responses[1]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(0)
        );
        assert_eq!(response.get_ref().responses[1].data, small_bytes);
    }

    #[tokio::test]
    async fn concurrent_cas_batch_reads_respect_shared_materialization_pool() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 64 * 1024 * 1024;
            config.memory_hard_limit_bytes = 128 * 1024 * 1024;
        })
        .await;
        let first_service = ReapiService {
            state: context.state.clone(),
        };
        let second_service = ReapiService {
            state: context.state.clone(),
        };
        let third_service = ReapiService {
            state: context.state.clone(),
        };
        let bytes = vec![b'b'; 16 * 1024 * 1024];
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                &bytes,
            )
            .await
            .expect("cas blob should persist");
        context.state.store.failpoints().set_always(
            FailpointName::AfterReadArtifactBytesBeforeReturn,
            FailpointAction::Sleep(Duration::from_millis(250)),
        );

        let first = tokio::spawn({
            let digest = digest.clone();
            async move {
                first_service
                    .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                        instance_name: DEFAULT_INSTANCE_NAME.into(),
                        digests: vec![digest],
                        digest_function: reapi::digest_function::Value::Sha256 as i32,
                        ..Default::default()
                    }))
                    .await
            }
        });
        let second = tokio::spawn({
            let digest = digest.clone();
            async move {
                second_service
                    .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                        instance_name: DEFAULT_INSTANCE_NAME.into(),
                        digests: vec![digest],
                        digest_function: reapi::digest_function::Value::Sha256 as i32,
                        ..Default::default()
                    }))
                    .await
            }
        });

        tokio::time::sleep(Duration::from_millis(50)).await;

        let third = third_service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest.clone()],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("third request should get a per-digest response");

        context
            .state
            .store
            .failpoints()
            .clear(FailpointName::AfterReadArtifactBytesBeforeReturn);

        assert_eq!(
            third.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );

        for handle in [first, second] {
            let response = handle
                .await
                .expect("concurrent read task should join")
                .expect("concurrent read should succeed");
            assert_eq!(
                response.get_ref().responses[0]
                    .status
                    .as_ref()
                    .map(|status| status.code),
                Some(0)
            );
            assert_eq!(response.get_ref().responses[0].data, bytes);
        }
    }

    #[tokio::test]
    async fn cas_batch_reads_shed_under_critical_memory_pressure() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        let bytes = b"blob-bytes";
        let digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(bytes)),
            size_bytes: bytes.len() as i64,
        };
        let key = blob_key(&digest_key(&digest).expect("digest key should build"));

        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &key,
                "application/octet-stream",
                bytes,
            )
            .await
            .expect("cas blob should persist");
        context
            .state
            .memory
            .observe(context.state.config.memory_hard_limit_bytes);

        let response = service
            .batch_read_blobs(Request::new(reapi::BatchReadBlobsRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                digests: vec![digest],
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect("batch read should return per-digest status");

        assert_eq!(
            response.get_ref().responses[0]
                .status
                .as_ref()
                .map(|status| status.code),
            Some(tonic::Code::ResourceExhausted as i32)
        );
    }

    #[tokio::test]
    async fn action_cache_inline_reads_reject_when_inline_expansion_exceeds_budget() {
        let context = test_context(|config| {
            config.memory_soft_limit_bytes = 32 * 1024 * 1024;
            config.memory_hard_limit_bytes = 64 * 1024 * 1024;
        })
        .await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        let stdout_bytes = vec![b's'; 9 * 1024 * 1024];
        let stdout_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&stdout_bytes)),
            size_bytes: stdout_bytes.len() as i64,
        };
        let stdout_key = blob_key(&digest_key(&stdout_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &stdout_key,
                "application/octet-stream",
                &stdout_bytes,
            )
            .await
            .expect("stdout blob should persist");

        let action_result = reapi::ActionResult {
            stdout_digest: Some(stdout_digest),
            ..Default::default()
        };
        let action_bytes = action_result.encode_to_vec();
        let action_digest = reapi::Digest {
            hash: hex::encode(Sha256::digest(&action_bytes)),
            size_bytes: action_bytes.len() as i64,
        };
        let action_key =
            action_cache_key(&digest_key(&action_digest).expect("digest key should build"));
        context
            .state
            .store
            .persist_inline_artifact_from_bytes(
                ArtifactProducer::Reapi,
                DEFAULT_INSTANCE_NAME,
                &action_key,
                "application/x-protobuf",
                &action_bytes,
            )
            .await
            .expect("action result should persist");

        let error = service
            .get_action_result(Request::new(reapi::GetActionResultRequest {
                instance_name: DEFAULT_INSTANCE_NAME.into(),
                action_digest: Some(action_digest),
                inline_stdout: true,
                digest_function: reapi::digest_function::Value::Sha256 as i32,
                ..Default::default()
            }))
            .await
            .expect_err("inline expansion should respect the materialization budget");

        assert_eq!(error.code(), tonic::Code::ResourceExhausted);
    }

    #[tokio::test]
    async fn draining_rejects_new_grpc_requests() {
        let context = test_context(|_| {}).await;
        let service = ReapiService {
            state: context.state.clone(),
        };
        context.state.enter_draining();

        let error = service
            .get_capabilities(Request::new(reapi::GetCapabilitiesRequest::default()))
            .await
            .expect_err("draining nodes should reject new gRPC requests");

        assert_eq!(error.code(), tonic::Code::Unavailable);
        assert!(error.message().contains("draining"));
    }
}
