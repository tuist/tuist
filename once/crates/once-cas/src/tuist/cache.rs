use std::collections::BTreeMap;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use bazel_remote_apis::{
    build::bazel::remote::execution::v2::{
        self as reapi, action_cache_client::ActionCacheClient,
        capabilities_client::CapabilitiesClient,
        content_addressable_storage_client::ContentAddressableStorageClient,
    },
    google::rpc::Status as RpcStatus,
};
use reqwest::{Method, Url};
use sha2::{Digest as _, Sha256};
use tokio::sync::Mutex;
use tokio::time::Instant;
use tonic::metadata::MetadataValue;
use tonic::transport::{Channel, ClientTlsConfig, Endpoint};
use tonic::{Code, Request, Status};

use super::{
    join_url, remote_status_message, TuistAuth, TuistCacheConfig, ENDPOINTS_PATH, PROVIDER_NAME,
};
use crate::{ActionResult, Cas, Digest, Error, Result};

const ENDPOINT_PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const GRPC_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const KURA_FEATURE_FLAGS_HEADER: &str = "x-tuist-feature-flags";
const KURA_FEATURE_FLAG: &str = "kura";
const BLOB_MAPPING_OUTPUT_PATH: &str = "blob";
const BLOB_MAPPING_PREFIX: &str = "once.blob.v1";
const ACTION_MAPPING_PREFIX: &str = "once.action.v1";
const REAPI_STATUS_OK: i32 = 0;
const REAPI_STATUS_NOT_FOUND: i32 = 5;
const SHA256_DIGEST_FUNCTION: i32 = reapi::digest_function::Value::Sha256 as i32;

#[derive(Debug, Clone)]
pub struct TuistCache {
    local: Cas,
    client: reqwest::Client,
    config: TuistCacheConfig,
    endpoint_cache: Arc<Mutex<Option<String>>>,
    grpc_channel_cache: Arc<Mutex<Option<(String, Channel)>>>,
    auth: TuistAuth,
}

impl TuistCache {
    pub fn new(local: Cas, auth_root: impl AsRef<Path>, config: TuistCacheConfig) -> Result<Self> {
        let Some(account) = config.account.as_deref() else {
            return Err(Error::InvalidConfig {
                provider: PROVIDER_NAME,
                message: "cache provider `tuist` requires `account`".to_string(),
            });
        };
        if account.is_empty() {
            return Err(Error::InvalidConfig {
                provider: PROVIDER_NAME,
                message: "cache provider `tuist` requires non-empty `account`".to_string(),
            });
        }
        if matches!(config.project.as_deref(), Some("")) {
            return Err(Error::InvalidConfig {
                provider: PROVIDER_NAME,
                message: "cache provider `tuist` requires non-empty `project` when set".to_string(),
            });
        }
        let client = reqwest::Client::builder()
            .timeout(GRPC_REQUEST_TIMEOUT)
            .build()
            .map_err(|source| Error::Remote {
                provider: PROVIDER_NAME,
                operation: "build client",
                message: source.to_string(),
            })?;
        let auth = TuistAuth::new(auth_root, &config);
        Ok(Self {
            local,
            client,
            config,
            endpoint_cache: Arc::new(Mutex::new(None)),
            grpc_channel_cache: Arc::new(Mutex::new(None)),
            auth,
        })
    }

    pub fn local(&self) -> &Cas {
        &self.local
    }

    pub fn config(&self) -> &TuistCacheConfig {
        &self.config
    }

    pub async fn get_blob(&self, digest: &Digest) -> Result<Vec<u8>> {
        match self.local.get_blob(digest).await {
            Ok(bytes) => return Ok(bytes),
            Err(Error::BlobNotFound(_)) => {}
            Err(error) => return Err(error),
        }

        let bytes = self.get_blob_remote(digest).await?;
        let mirrored = self.local.put_blob(&bytes).await?;
        if mirrored != *digest {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation: "get blob",
                message: format!("remote blob {digest} did not match requested digest"),
            });
        }
        Ok(bytes)
    }

    pub async fn put_blob(&self, bytes: &[u8]) -> Result<Digest> {
        let digest = self.local.put_blob(bytes).await?;
        let _ = self.put_blob_remote(&digest, bytes).await;
        Ok(digest)
    }

    /// True if the blob is present locally or remotely. A remote
    /// failure is treated as "not present" so a transient outage degrades
    /// to a cache miss instead of a hard error.
    pub async fn has_blob(&self, digest: &Digest) -> Result<bool> {
        if self.local.has_blob(digest).await? {
            return Ok(true);
        }
        Ok(self.head_blob_remote(digest).await.unwrap_or(false))
    }

    pub async fn get_action_result(&self, action: &Digest) -> Result<Option<ActionResult>> {
        if let Some(result) = self.local.get_action_result(action).await? {
            return Ok(Some(result));
        }

        match self.get_action_result_remote(action).await {
            Ok(Some(result)) => {
                if self.prefetch_action_blobs(&result).await.is_ok() {
                    let _ = self.local.put_action_result(action, &result).await;
                }
                Ok(Some(result))
            }
            Ok(None) => Ok(None),
            Err(error) if error.is_read_miss() => Ok(None),
            Err(error) => Err(error.into_public_error("get action result")),
        }
    }

    pub async fn put_action_result(&self, action: &Digest, result: &ActionResult) -> Result<()> {
        self.local.put_action_result(action, result).await?;
        let _ = self.put_action_result_remote(action, result).await;
        Ok(())
    }

    pub async fn forget_action(&self, action: &Digest) -> Result<bool> {
        self.local.forget_action(action).await
    }

    async fn prefetch_action_blobs(&self, result: &ActionResult) -> Result<()> {
        let mut digests = Vec::with_capacity(2 + result.outputs.len());
        digests.extend(result.stdout);
        digests.extend(result.stderr);
        digests.extend(result.outputs.values().copied());
        for digest in digests {
            let _ = self.local.get_blob(&digest).await?;
        }
        Ok(())
    }

    async fn head_blob_remote(&self, digest: &Digest) -> Result<bool> {
        let sha256 = match self.get_blob_mapping(digest).await {
            Ok(digest) => digest,
            Err(Error::BlobNotFound(_)) => return Ok(false),
            Err(error) => return Err(error),
        };
        self.reapi_blob_exists(&sha256).await
    }

    async fn get_blob_remote(&self, digest: &Digest) -> Result<Vec<u8>> {
        let sha256 = self.get_blob_mapping(digest).await?;
        let Some(bytes) = self.read_reapi_blob(&sha256, "get blob").await? else {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation: "get blob",
                message: format!("remote blob mapping for {digest} points at a missing blob"),
            });
        };
        Ok(bytes)
    }

    async fn put_blob_remote(&self, digest: &Digest, bytes: &[u8]) -> Result<reapi::Digest> {
        if Digest::of_bytes(bytes) != *digest {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation: "put blob",
                message: format!("blob body did not match digest {digest}"),
            });
        }
        let sha256 = sha256_digest(bytes)?;
        self.upload_reapi_blob(&sha256, bytes, "put blob").await?;
        self.put_blob_mapping(digest, &sha256).await?;
        Ok(sha256)
    }

    async fn get_action_result_remote(
        &self,
        action: &Digest,
    ) -> std::result::Result<Option<ActionResult>, RemoteReadError> {
        let mapping_digest = action_mapping_digest(action).map_err(RemoteReadError::fatal)?;
        let Some(result) = self
            .get_reapi_action_result(&mapping_digest, "get action result")
            .await
            .map_err(remote_action_read_error)?
        else {
            return Ok(None);
        };

        self.reapi_to_once_action_result(result)
            .await
            .map(Some)
            .map_err(remote_action_read_error)
    }

    async fn put_action_result_remote(&self, action: &Digest, result: &ActionResult) -> Result<()> {
        let stdout_digest = self
            .upload_local_blob(result.stdout.as_ref(), "put action result")
            .await?;
        let stderr_digest = self
            .upload_local_blob(result.stderr.as_ref(), "put action result")
            .await?;

        let mut output_files = Vec::with_capacity(result.outputs.len());
        for (path, digest) in &result.outputs {
            let reapi_digest = self
                .upload_local_blob(Some(digest), "put action result")
                .await?;
            output_files.push(reapi::OutputFile {
                path: path.clone(),
                digest: reapi_digest,
                ..Default::default()
            });
        }

        let reapi_result = reapi::ActionResult {
            output_files,
            exit_code: result.exit_code,
            stdout_digest,
            stderr_digest,
            ..Default::default()
        };
        let mapping_digest = action_mapping_digest(action)?;
        self.update_reapi_action_result(&mapping_digest, reapi_result, "put action result")
            .await
    }

    async fn upload_local_blob(
        &self,
        digest: Option<&Digest>,
        operation: &'static str,
    ) -> Result<Option<reapi::Digest>> {
        let Some(digest) = digest else {
            return Ok(None);
        };
        let bytes = self.local.get_blob(digest).await?;
        self.put_blob_remote(digest, &bytes)
            .await
            .map(Some)
            .map_err(|error| match error {
                Error::Remote { message, .. } => Error::Remote {
                    provider: PROVIDER_NAME,
                    operation,
                    message,
                },
                other => other,
            })
    }

    async fn put_blob_mapping(&self, digest: &Digest, sha256: &reapi::Digest) -> Result<()> {
        let action_digest = blob_mapping_digest(digest)?;
        let action_result = reapi::ActionResult {
            output_files: vec![reapi::OutputFile {
                path: BLOB_MAPPING_OUTPUT_PATH.to_string(),
                digest: Some(sha256.clone()),
                ..Default::default()
            }],
            ..Default::default()
        };
        self.update_reapi_action_result(&action_digest, action_result, "put blob mapping")
            .await
    }

    async fn get_blob_mapping(&self, digest: &Digest) -> Result<reapi::Digest> {
        let action_digest = blob_mapping_digest(digest)?;
        let Some(action_result) = self
            .get_reapi_action_result(&action_digest, "get blob mapping")
            .await?
        else {
            return Err(Error::BlobNotFound(*digest));
        };
        action_result
            .output_files
            .into_iter()
            .find(|file| file.path == BLOB_MAPPING_OUTPUT_PATH)
            .and_then(|file| file.digest)
            .ok_or_else(|| Error::Remote {
                provider: PROVIDER_NAME,
                operation: "get blob mapping",
                message: format!("remote blob mapping for {digest} is missing its REAPI digest"),
            })
    }

    async fn reapi_to_once_action_result(
        &self,
        result: reapi::ActionResult,
    ) -> Result<ActionResult> {
        let stdout = self
            .mirror_reapi_digest_or_raw(
                result.stdout_digest.as_ref(),
                &result.stdout_raw,
                "get action result",
            )
            .await?;
        let stderr = self
            .mirror_reapi_digest_or_raw(
                result.stderr_digest.as_ref(),
                &result.stderr_raw,
                "get action result",
            )
            .await?;

        let mut outputs = BTreeMap::new();
        for output_file in result.output_files {
            let digest = match output_file.digest.as_ref() {
                Some(reapi_digest) => {
                    self.mirror_reapi_blob(reapi_digest, "get action result")
                        .await?
                }
                None if !output_file.contents.is_empty() => {
                    self.local.put_blob(&output_file.contents).await?
                }
                None => continue,
            };
            outputs.insert(output_file.path, digest);
        }

        Ok(ActionResult {
            exit_code: result.exit_code,
            stdout,
            stderr,
            outputs,
        })
    }

    async fn mirror_reapi_digest_or_raw(
        &self,
        digest: Option<&reapi::Digest>,
        raw: &[u8],
        operation: &'static str,
    ) -> Result<Option<Digest>> {
        if let Some(digest) = digest {
            return self.mirror_reapi_blob(digest, operation).await.map(Some);
        }
        if raw.is_empty() {
            return Ok(None);
        }
        self.local.put_blob(raw).await.map(Some)
    }

    async fn mirror_reapi_blob(
        &self,
        digest: &reapi::Digest,
        operation: &'static str,
    ) -> Result<Digest> {
        let Some(bytes) = self.read_reapi_blob(digest, operation).await? else {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: format!(
                    "remote action result points at missing blob {}",
                    digest_key(digest)
                ),
            });
        };
        self.local.put_blob(&bytes).await
    }

    async fn upload_reapi_blob(
        &self,
        digest: &reapi::Digest,
        bytes: &[u8],
        operation: &'static str,
    ) -> Result<()> {
        let channel = self.grpc_channel().await?;
        let mut client = ContentAddressableStorageClient::new(channel);
        let request = reapi::BatchUpdateBlobsRequest {
            instance_name: self.instance_name(),
            requests: vec![reapi::batch_update_blobs_request::Request {
                digest: Some(digest.clone()),
                data: bytes.to_vec(),
                compressor: reapi::compressor::Value::Identity as i32,
            }],
            digest_function: SHA256_DIGEST_FUNCTION,
        };
        let response = client
            .batch_update_blobs(self.authorized_grpc_request(request, operation).await?)
            .await
            .map_err(|source| grpc_error(operation, &source))?
            .into_inner();
        let Some(status) = response
            .responses
            .first()
            .and_then(|response| response.status.as_ref())
        else {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: "Kura returned no status for blob upload".to_string(),
            });
        };
        if status.code == REAPI_STATUS_OK {
            Ok(())
        } else {
            Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: rpc_status_message(status),
            })
        }
    }

    async fn read_reapi_blob(
        &self,
        digest: &reapi::Digest,
        operation: &'static str,
    ) -> Result<Option<Vec<u8>>> {
        let channel = self.grpc_channel().await?;
        let mut client = ContentAddressableStorageClient::new(channel);
        let request = reapi::BatchReadBlobsRequest {
            instance_name: self.instance_name(),
            digests: vec![digest.clone()],
            acceptable_compressors: vec![reapi::compressor::Value::Identity as i32],
            digest_function: SHA256_DIGEST_FUNCTION,
        };
        let response = client
            .batch_read_blobs(self.authorized_grpc_request(request, operation).await?)
            .await
            .map_err(|source| grpc_error(operation, &source))?
            .into_inner();
        let Some(blob) = response.responses.into_iter().next() else {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: "Kura returned no blob response".to_string(),
            });
        };
        let Some(status) = blob.status.as_ref() else {
            return Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: "Kura returned no status for blob read".to_string(),
            });
        };
        match status.code {
            REAPI_STATUS_OK => {
                validate_sha256_digest(digest, &blob.data, operation)?;
                Ok(Some(blob.data))
            }
            REAPI_STATUS_NOT_FOUND => Ok(None),
            _ => Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message: rpc_status_message(status),
            }),
        }
    }

    async fn reapi_blob_exists(&self, digest: &reapi::Digest) -> Result<bool> {
        let channel = self.grpc_channel().await?;
        let mut client = ContentAddressableStorageClient::new(channel);
        let request = reapi::FindMissingBlobsRequest {
            instance_name: self.instance_name(),
            blob_digests: vec![digest.clone()],
            digest_function: SHA256_DIGEST_FUNCTION,
        };
        let response = client
            .find_missing_blobs(self.authorized_grpc_request(request, "head blob").await?)
            .await
            .map_err(|source| grpc_error("head blob", &source))?
            .into_inner();
        Ok(response.missing_blob_digests.is_empty())
    }

    async fn get_reapi_action_result(
        &self,
        action_digest: &reapi::Digest,
        operation: &'static str,
    ) -> Result<Option<reapi::ActionResult>> {
        let channel = self.grpc_channel().await?;
        let mut client = ActionCacheClient::new(channel);
        let request = reapi::GetActionResultRequest {
            instance_name: self.instance_name(),
            action_digest: Some(action_digest.clone()),
            inline_stdout: false,
            inline_stderr: false,
            inline_output_files: Vec::new(),
            digest_function: SHA256_DIGEST_FUNCTION,
        };
        match client
            .get_action_result(self.authorized_grpc_request(request, operation).await?)
            .await
        {
            Ok(response) => Ok(Some(response.into_inner())),
            Err(status) if status.code() == Code::NotFound => Ok(None),
            Err(status) => Err(grpc_error(operation, &status)),
        }
    }

    async fn update_reapi_action_result(
        &self,
        action_digest: &reapi::Digest,
        action_result: reapi::ActionResult,
        operation: &'static str,
    ) -> Result<()> {
        let channel = self.grpc_channel().await?;
        let mut client = ActionCacheClient::new(channel);
        let request = reapi::UpdateActionResultRequest {
            instance_name: self.instance_name(),
            action_digest: Some(action_digest.clone()),
            action_result: Some(action_result),
            results_cache_policy: None,
            digest_function: SHA256_DIGEST_FUNCTION,
        };
        client
            .update_action_result(self.authorized_grpc_request(request, operation).await?)
            .await
            .map_err(|source| grpc_error(operation, &source))?;
        Ok(())
    }

    async fn data_plane_endpoint(&self) -> Result<String> {
        let mut cached = self.endpoint_cache.lock().await;
        if let Some(endpoint) = cached.as_ref() {
            return Ok(endpoint.clone());
        }
        let endpoints = self.fetch_endpoints().await?;
        let endpoint = match endpoints.len() {
            0 => {
                return Err(Error::Remote {
                    provider: PROVIDER_NAME,
                    operation: "discover endpoints",
                    message: "Tuist returned no Kura cache endpoints".to_string(),
                });
            }
            _ => self.pick_fastest_endpoint(&endpoints).await?,
        };
        *cached = Some(endpoint.clone());
        Ok(endpoint)
    }

    async fn fetch_endpoints(&self) -> Result<Vec<String>> {
        let url = self.endpoints_url()?;
        let response = self
            .authorized_request(Method::GET, url, &self.auth_token().await?)
            .header(KURA_FEATURE_FLAGS_HEADER, KURA_FEATURE_FLAG)
            .send()
            .await
            .map_err(|source| Error::Remote {
                provider: PROVIDER_NAME,
                operation: "discover endpoints",
                message: source.to_string(),
            })?;
        match response.status() {
            status if status.is_success() => {
                let endpoints: EndpointResponse =
                    response.json().await.map_err(|source| Error::Remote {
                        provider: PROVIDER_NAME,
                        operation: "decode endpoints",
                        message: source.to_string(),
                    })?;
                Ok(endpoints.endpoints)
            }
            _ => Err(Error::Remote {
                provider: PROVIDER_NAME,
                operation: "discover endpoints",
                message: remote_status_message(response).await,
            }),
        }
    }

    async fn pick_fastest_endpoint(&self, endpoints: &[String]) -> Result<String> {
        let token = self.auth_token().await?;
        let instance_name = String::new();
        let mut set = tokio::task::JoinSet::new();
        for endpoint in endpoints {
            let endpoint = endpoint.clone();
            let token = token.clone();
            let instance_name = instance_name.clone();
            set.spawn(async move {
                let start = Instant::now();
                let outcome = async {
                    let channel = connect_grpc_endpoint(&endpoint).await?;
                    let mut client = CapabilitiesClient::new(channel);
                    let request = reapi::GetCapabilitiesRequest { instance_name };
                    let request = authorized_grpc_request_with_token(request, &token)
                        .map_err(|error| error.to_string())?;
                    timeout_result(
                        tokio::time::timeout(
                            ENDPOINT_PROBE_TIMEOUT,
                            client.get_capabilities(request),
                        )
                        .await,
                    )
                }
                .await;
                match outcome {
                    Ok(()) => Ok((start.elapsed(), endpoint)),
                    Err(error) => Err(format!("{endpoint}: {error}")),
                }
            });
        }

        let mut best: Option<(Duration, String)> = None;
        let mut failures = Vec::new();
        while let Some(joined) = set.join_next().await {
            let Ok(result) = joined else {
                failures.push("probe task failed".to_string());
                continue;
            };
            let (elapsed, endpoint) = match result {
                Ok(candidate) => candidate,
                Err(error) => {
                    failures.push(error);
                    continue;
                }
            };
            match &best {
                Some((best_elapsed, _)) if *best_elapsed <= elapsed => {}
                _ => best = Some((elapsed, endpoint)),
            }
        }

        best.map(|(_, endpoint)| endpoint).ok_or_else(|| {
            let message = if failures.is_empty() {
                "no reachable Tuist Kura cache endpoints".to_string()
            } else {
                format!(
                    "no reachable Tuist Kura cache endpoints: {}",
                    failures.join("; ")
                )
            };
            Error::Remote {
                provider: PROVIDER_NAME,
                operation: "pick fastest endpoint",
                message,
            }
        })
    }

    async fn grpc_channel(&self) -> Result<Channel> {
        let endpoint = self.data_plane_endpoint().await?;
        {
            let cached = self.grpc_channel_cache.lock().await;
            if let Some((cached_endpoint, channel)) = cached.as_ref() {
                if cached_endpoint == &endpoint {
                    return Ok(channel.clone());
                }
            }
        }
        let channel = connect_grpc_endpoint(&endpoint)
            .await
            .map_err(|message| Error::Remote {
                provider: PROVIDER_NAME,
                operation: "connect endpoint",
                message,
            })?;
        *self.grpc_channel_cache.lock().await = Some((endpoint, channel.clone()));
        Ok(channel)
    }

    async fn auth_token(&self) -> Result<String> {
        let auth = self.auth.clone();
        tokio::task::spawn_blocking(move || auth.token())
            .await
            .map_err(|source| Error::Remote {
                provider: PROVIDER_NAME,
                operation: "load auth token",
                message: source.to_string(),
            })?
    }

    fn authorized_request(&self, method: Method, url: Url, token: &str) -> reqwest::RequestBuilder {
        self.client.request(method, url).bearer_auth(token)
    }

    async fn authorized_grpc_request<T>(
        &self,
        message: T,
        operation: &'static str,
    ) -> Result<Request<T>> {
        let token = self.auth_token().await?;
        authorized_grpc_request_with_token(message, &token).map_err(|message| Error::Remote {
            provider: PROVIDER_NAME,
            operation,
            message,
        })
    }

    fn account(&self) -> &str {
        self.config
            .account
            .as_deref()
            .expect("validated at construction")
    }

    fn instance_name(&self) -> String {
        let Some(project) = self.config.project.as_deref() else {
            return self.account().to_string();
        };
        format!("{}/{}", self.account(), project)
    }

    fn endpoints_url(&self) -> Result<Url> {
        let mut url = self.server_url(ENDPOINTS_PATH)?;
        url.query_pairs_mut()
            .append_pair("account_handle", self.account());
        Ok(url)
    }

    fn server_url(&self, path: &str) -> Result<Url> {
        join_url(&self.config.url, path)
    }
}

#[derive(Debug, serde::Deserialize)]
struct EndpointResponse {
    endpoints: Vec<String>,
}

#[derive(Debug)]
enum RemoteReadError {
    Miss(String),
    Fatal(Error),
}

impl RemoteReadError {
    fn miss(message: String) -> Self {
        Self::Miss(message)
    }

    fn fatal(error: Error) -> Self {
        Self::Fatal(error)
    }

    fn is_read_miss(&self) -> bool {
        matches!(self, Self::Miss(_))
    }

    fn into_public_error(self, operation: &'static str) -> Error {
        match self {
            Self::Miss(message) => Error::Remote {
                provider: PROVIDER_NAME,
                operation,
                message,
            },
            Self::Fatal(error) => error,
        }
    }
}

fn remote_action_read_error(error: Error) -> RemoteReadError {
    match error {
        Error::Remote {
            message,
            operation,
            provider,
        } if provider == PROVIDER_NAME && operation == "get action result" => {
            RemoteReadError::miss(message)
        }
        other => RemoteReadError::fatal(other),
    }
}

async fn connect_grpc_endpoint(endpoint: &str) -> std::result::Result<Channel, String> {
    let endpoint_url = grpc_endpoint_url(endpoint);
    let mut endpoint = Endpoint::from_shared(endpoint_url.clone())
        .map_err(|source| source.to_string())?
        .connect_timeout(ENDPOINT_PROBE_TIMEOUT)
        .timeout(GRPC_REQUEST_TIMEOUT);
    if endpoint_url.starts_with("https://") {
        endpoint = endpoint
            .tls_config(ClientTlsConfig::new().with_enabled_roots())
            .map_err(|source| format!("{source:?}"))?;
    }
    endpoint
        .connect()
        .await
        .map_err(|source| format!("{source:?}"))
}

fn authorized_grpc_request_with_token<T>(
    message: T,
    token: &str,
) -> std::result::Result<Request<T>, String> {
    let header = format!("Bearer {token}");
    let metadata = MetadataValue::try_from(header.as_str()).map_err(|source| source.to_string())?;
    let mut request = Request::new(message);
    request.metadata_mut().insert("authorization", metadata);
    Ok(request)
}

fn timeout_result<T>(
    result: std::result::Result<std::result::Result<T, Status>, tokio::time::error::Elapsed>,
) -> std::result::Result<(), String> {
    match result {
        Ok(Ok(_)) => Ok(()),
        Ok(Err(status)) => Err(status.to_string()),
        Err(source) => Err(source.to_string()),
    }
}

fn grpc_error(operation: &'static str, status: &Status) -> Error {
    Error::Remote {
        provider: PROVIDER_NAME,
        operation,
        message: grpc_status_message(status),
    }
}

fn grpc_status_message(status: &Status) -> String {
    if status.message().is_empty() {
        format!("gRPC {}", status.code())
    } else {
        format!("gRPC {}: {}", status.code(), status.message())
    }
}

fn rpc_status_message(status: &RpcStatus) -> String {
    if status.message.is_empty() {
        format!("REAPI status {}", status.code)
    } else {
        format!("REAPI status {}: {}", status.code, status.message)
    }
}

fn sha256_digest(bytes: &[u8]) -> Result<reapi::Digest> {
    Ok(reapi::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: size_bytes_i64(bytes.len())?,
    })
}

fn validate_sha256_digest(
    digest: &reapi::Digest,
    bytes: &[u8],
    operation: &'static str,
) -> Result<()> {
    let actual = sha256_digest(bytes)?;
    if actual == *digest {
        Ok(())
    } else {
        Err(Error::Remote {
            provider: PROVIDER_NAME,
            operation,
            message: format!(
                "remote blob {} did not match expected digest {}",
                digest_key(&actual),
                digest_key(digest)
            ),
        })
    }
}

fn blob_mapping_digest(digest: &Digest) -> Result<reapi::Digest> {
    mapping_digest(BLOB_MAPPING_PREFIX, digest)
}

fn action_mapping_digest(digest: &Digest) -> Result<reapi::Digest> {
    mapping_digest(ACTION_MAPPING_PREFIX, digest)
}

fn mapping_digest(prefix: &str, digest: &Digest) -> Result<reapi::Digest> {
    let preimage = format!("{prefix}\0{}", digest.to_hex());
    sha256_digest(preimage.as_bytes())
}

fn digest_key(digest: &reapi::Digest) -> String {
    format!("{}/{}", digest.hash, digest.size_bytes)
}

fn size_bytes_i64(size: usize) -> Result<i64> {
    let Ok(size) = i64::try_from(size) else {
        return Err(Error::Remote {
            provider: PROVIDER_NAME,
            operation: "compute digest",
            message: format!("blob size exceeds REAPI size limit: {size} bytes"),
        });
    };
    Ok(size)
}

fn grpc_endpoint_url(endpoint: &str) -> String {
    if let Some(rest) = endpoint.strip_prefix("grpc://") {
        format!("http://{rest}")
    } else if let Some(rest) = endpoint.strip_prefix("grpcs://") {
        format!("https://{rest}")
    } else {
        endpoint.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grpc_endpoint_url_normalizes_grpc_schemes() {
        assert_eq!(
            grpc_endpoint_url("grpc://localhost:5101"),
            "http://localhost:5101"
        );
        assert_eq!(
            grpc_endpoint_url("grpcs://cache.example.com"),
            "https://cache.example.com"
        );
        assert_eq!(
            grpc_endpoint_url("https://cache.example.com"),
            "https://cache.example.com"
        );
    }

    #[test]
    fn sha256_digest_matches_reapi_shape() {
        let digest = sha256_digest(b"hello").unwrap();
        assert_eq!(
            digest.hash,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
        assert_eq!(digest.size_bytes, 5);
    }

    #[test]
    fn size_bytes_rejects_values_that_do_not_fit_reapi_digest() {
        if i64::try_from(usize::MAX).is_ok() {
            return;
        }

        let error = size_bytes_i64(usize::MAX).unwrap_err();
        assert!(error.to_string().contains("REAPI size limit"));
    }

    #[test]
    fn grpc_error_includes_code_and_message() {
        let error = grpc_error("get blob", &Status::unavailable("cache unavailable"));
        let message = error.to_string();
        assert!(message.to_lowercase().contains("unavailable"));
        assert!(message.contains("cache unavailable"));
    }

    #[test]
    fn blob_and_action_mapping_digests_are_distinct() {
        let digest = Digest::of_bytes(b"payload");
        assert_ne!(
            blob_mapping_digest(&digest).unwrap(),
            action_mapping_digest(&digest).unwrap()
        );
    }

    #[test]
    fn remote_action_materialization_errors_are_read_misses() {
        let error = Error::Remote {
            provider: PROVIDER_NAME,
            operation: "get action result",
            message: "remote action result points at missing blob".to_string(),
        };

        assert!(remote_action_read_error(error).is_read_miss());
    }

    #[test]
    fn unrelated_remote_action_errors_stay_fatal() {
        let error = Error::Remote {
            provider: PROVIDER_NAME,
            operation: "put blob",
            message: "write failed".to_string(),
        };

        assert!(!remote_action_read_error(error).is_read_miss());
    }
}
