//! Tuist compilation cache over the standard Bazel Remote Execution API.
//! Local algorithm-tagged identities remain intact. The remote CAS always uses
//! real SHA-256 content digests; domain-separated Action messages index those
//! identities. Prediction updates are speculative last-writer updates, not CAS.
use crate::reapi_proto as pb;
use crate::{
    BlobSource, BlobUpload, CacheDigest, CacheDirectory, ManifestPutOutcome, RemoteActionManifest,
    RemoteActionResult, RemoteCacheConfig, canonical_json,
};
use eyre::{Result, bail, eyre};
use prost::Message;
use sha2::{Digest as _, Sha256};
use std::{
    collections::{BTreeSet, HashMap},
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
    time::{Duration, Instant},
};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    sync::{Mutex, OnceCell},
};
use tonic::{
    Code, Request,
    transport::{Channel, ClientTlsConfig, Endpoint},
};

const JSON_LIMIT: u64 = 16 * 1024 * 1024;
const GRAPH_LIMIT: usize = 100_000;
const CHUNK: usize = 1024 * 1024;

pub(crate) struct ReapiRemoteCache {
    config: RemoteCacheConfig,
    account: String,
    instance: String,
    channel: OnceCell<Channel>,
    capabilities: OnceCell<pb::CacheCapabilities>,
    indexes: Mutex<HashMap<CacheDigest, pb::Digest>>,
    read_budget: Duration,
    read_spent: AtomicU64,
}

fn sha(bytes: &[u8]) -> pb::Digest {
    pb::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: bytes.len() as i64,
    }
}

type IndexAction = (pb::Digest, Vec<(pb::Digest, Vec<u8>)>);

/// These are genuine serialized Command/Action SHA-256 digests, not BLAKE3
/// values mislabeled as SHA-256. The input directory is the empty Directory.
fn index_action(kind: &str, identity: &CacheDigest) -> Result<IndexAction> {
    identity.validate()?;
    let command = pb::Command {
        arguments: vec![
            "tuist-cargo-cache".into(),
            "index-v1".into(),
            kind.into(),
            identity.key(),
        ],
        output_paths: vec!["record".into()],
    }
    .encode_to_vec();
    let command_digest = sha(&command);
    let directory_digest = sha(&[]);
    let action = pb::Action {
        command_digest: Some(command_digest.clone()),
        input_root_digest: Some(directory_digest.clone()),
    }
    .encode_to_vec();
    let digest = sha(&action);
    Ok((
        digest.clone(),
        vec![
            (command_digest, command),
            (directory_digest, vec![]),
            (digest, action),
        ],
    ))
}

fn report_reference(action: &CacheDigest, digest: &pb::Digest) {
    if validate_sha(digest).is_ok() {
        crate::public_cache_report::reference(
            action,
            &CacheDigest {
                algorithm: "sha256".into(),
                hash: digest.hash.clone(),
                size: digest.size_bytes as u64,
            },
        );
    }
}

fn validate_sha(digest: &pb::Digest) -> Result<()> {
    if digest.size_bytes < 0
        || digest.hash.len() != 64
        || !digest
            .hash
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        bail!("invalid REAPI SHA-256 digest");
    }
    Ok(())
}

impl ReapiRemoteCache {
    pub(crate) fn new(config: RemoteCacheConfig) -> Result<Self> {
        if !matches!(config.base_url.scheme(), "http" | "https")
            || config.base_url.host_str().is_none()
            || config.base_url.query().is_some()
            || config.base_url.fragment().is_some()
            || !config.base_url.username().is_empty()
            || config.base_url.password().is_some()
        {
            bail!("invalid REAPI endpoint");
        }
        let parts: Vec<_> = config.namespace.split('/').collect();
        if parts.len() != 2
            || parts.iter().any(|p| {
                p.is_empty()
                    || p.len() > 128
                    || !p
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_' | b'.'))
            })
        {
            bail!("REAPI requires a project-scoped account/project instance");
        }
        let account = parts[0].to_owned();
        let instance = parts[1].to_owned();
        Ok(Self {
            config,
            account,
            instance,
            channel: OnceCell::new(),
            capabilities: OnceCell::new(),
            indexes: Mutex::new(HashMap::new()),
            read_budget: Duration::ZERO,
            read_spent: AtomicU64::new(0),
        })
    }

    pub(crate) fn set_read_stall_budget(&mut self, budget: Duration) {
        self.read_budget = budget;
    }

    fn read_guard(&self, read: bool) -> Result<ReadGuard<'_>> {
        if read
            && !self.read_budget.is_zero()
            && self.read_spent.load(Ordering::Relaxed) as u128 >= self.read_budget.as_nanos()
        {
            bail!("remote cache read-stall budget exhausted");
        }
        Ok(ReadGuard {
            cache: self,
            started: Instant::now(),
            failed: read,
        })
    }

    async fn grpc(&self) -> Result<tonic::client::Grpc<Channel>> {
        let channel = self
            .channel
            .get_or_try_init(|| async {
                let mut endpoint = Endpoint::from_shared(
                    self.config
                        .base_url
                        .as_str()
                        .trim_end_matches('/')
                        .to_owned(),
                )?
                .connect_timeout(self.config.connect_timeout)
                .timeout(self.config.download_timeout)
                .http2_keep_alive_interval(Duration::from_secs(10))
                .keep_alive_timeout(self.config.read_timeout)
                .keep_alive_while_idle(true)
                .initial_connection_window_size(32 * 1024 * 1024)
                .initial_stream_window_size(2 * 1024 * 1024);
                if self.config.base_url.scheme() == "https" {
                    let mut tls = ClientTlsConfig::new().with_native_roots();
                    if let Some(path) = crate::remote_reapi_network::ca_certificate_path() {
                        tls = tls.ca_certificate(tonic::transport::Certificate::from_pem(
                            crate::remote_reapi_network::certificate_pem(
                                tokio::fs::read(path).await?,
                            ),
                        ));
                    }
                    endpoint = endpoint.tls_config(tls)?;
                }
                crate::remote_reapi_network::connect(
                    endpoint,
                    &self.config.base_url,
                    self.config.connect_timeout,
                )
                .await
            })
            .await?;
        let mut grpc =
            tonic::client::Grpc::new(channel.clone()).max_decoding_message_size(2 * 1024 * 1024);
        grpc.ready()
            .await
            .map_err(|error| eyre!("REAPI connection unavailable: {error}"))?;
        Ok(grpc)
    }

    async fn request<T>(&self, value: T) -> Result<Request<T>> {
        let mut request = Request::new(value);
        request.set_timeout(self.config.read_timeout);
        request
            .metadata_mut()
            .insert("x-tuist-account-handle", self.account.parse()?);
        let token = if let Some(file) = &self.config.token_file {
            Some(tokio::fs::read_to_string(file).await?)
        } else {
            self.config.token.clone()
        };
        if let Some(token) = token {
            request
                .metadata_mut()
                .insert("authorization", format!("Bearer {}", token.trim()).parse()?);
        }
        Ok(request)
    }

    async fn stream_request<T>(&self, value: T) -> Result<Request<T>> {
        let mut request = self.request(value).await?;
        request.set_timeout(self.config.download_timeout);
        Ok(request)
    }

    async fn unary<I, O>(&self, method: &'static str, value: I) -> Result<Option<O>>
    where
        I: Message + Default + Clone + Send + Sync + 'static,
        O: Message + Default + Send + Sync + 'static,
    {
        let mut guard = self.read_guard(method.contains("/Get"))?;
        let mut attempt = 0;
        loop {
            let remaining = if guard.failed && !self.read_budget.is_zero() {
                self.read_budget
                    .saturating_sub(Duration::from_nanos(
                        self.read_spent.load(Ordering::Relaxed),
                    ))
                    .saturating_sub(guard.started.elapsed())
            } else {
                self.config.read_timeout
            };
            let timeout = self.config.read_timeout.min(remaining);
            if timeout.is_zero() {
                bail!("remote cache read-stall budget exhausted");
            }
            let response = tokio::time::timeout(timeout, async {
                let mut grpc = self.grpc().await?;
                let response = grpc
                    .unary(
                        self.request(value.clone()).await?,
                        http::uri::PathAndQuery::from_static(method),
                        tonic_prost::ProstCodec::<I, O>::default(),
                    )
                    .await;
                Ok::<_, eyre::Report>(response)
            })
            .await??;
            match response {
                Ok(response) => {
                    guard.failed = false;
                    return Ok(Some(response.into_inner()));
                }
                Err(error) if error.code() == Code::NotFound => {
                    guard.failed = false;
                    return Ok(None);
                }
                Err(error) if attempt < self.config.retries.min(2) => {
                    let Some(delay) = crate::reapi_retry::delay(&error, attempt) else {
                        return Err(error.into());
                    };
                    attempt += 1;
                    tokio::time::sleep(delay).await;
                }
                Err(error) => return Err(error.into()),
            }
        }
    }

    pub(crate) async fn check_connection(&self) -> Result<()> {
        self.capabilities
            .get_or_try_init(|| async {
                let capabilities: pb::ServerCapabilities = self
                    .unary(
                        concat!(
                            "/build.bazel.remote.execution.v2.",
                            "Capabilities/GetCapabilities"
                        ),
                        pb::GetCapabilitiesRequest {
                            instance_name: self.instance.clone(),
                        },
                    )
                    .await?
                    .ok_or_else(|| eyre!("missing REAPI capabilities"))?;
                let capabilities = capabilities
                    .cache_capabilities
                    .ok_or_else(|| eyre!("missing REAPI cache capabilities"))?;
                if !capabilities.digest_functions.contains(&1) {
                    bail!("cache does not support REAPI SHA-256");
                }
                Ok::<_, eyre::Report>(capabilities)
            })
            .await?;
        Ok(())
    }

    async fn action(&self, kind: &str, identity: &CacheDigest) -> Result<Option<pb::ActionResult>> {
        self.check_connection().await?;
        let (digest, _) = index_action(kind, identity)?;
        let result: Option<pb::ActionResult> = self
            .unary(
                concat!(
                    "/build.bazel.remote.execution.v2.",
                    "ActionCache/GetActionResult"
                ),
                pb::GetActionResultRequest {
                    instance_name: self.instance.clone(),
                    action_digest: Some(digest),
                    digest_function: 1,
                },
            )
            .await?;
        if result.as_ref().is_some_and(|r| r.exit_code != 0) {
            bail!("invalid compilation-cache index result");
        }
        Ok(result)
    }

    async fn publish(
        &self,
        kind: &str,
        identity: &CacheDigest,
        output: pb::Digest,
        mut references: Vec<pb::Digest>,
    ) -> Result<()> {
        self.check_connection().await?;
        if !self.capabilities.get().is_some_and(|c| {
            c.action_cache_update_capabilities
                .as_ref()
                .is_some_and(|u| u.update_enabled)
        }) {
            bail!("REAPI Action Cache updates are not enabled");
        }
        let (action_digest, inputs) = index_action(kind, identity)?;
        for (digest, bytes) in inputs {
            self.upload_bytes(&digest, &bytes).await?;
        }
        references.push(output.clone());
        for batch in references.chunks(1000) {
            let missing: pb::FindMissingBlobsResponse = self
                .unary(
                    concat!(
                        "/build.bazel.remote.execution.v2.",
                        "ContentAddressableStorage/FindMissingBlobs"
                    ),
                    pb::FindMissingBlobsRequest {
                        instance_name: self.instance.clone(),
                        blob_digests: batch.to_vec(),
                        digest_function: 1,
                    },
                )
                .await?
                .ok_or_else(|| eyre!("missing presence response"))?;
            if !missing.missing_blob_digests.is_empty() {
                bail!("incomplete compilation output graph");
            }
        }
        let mut output_files = vec![pb::OutputFile {
            path: "record".into(),
            digest: Some(output),
        }];
        output_files.extend(
            references
                .into_iter()
                .enumerate()
                .map(|(i, digest)| pb::OutputFile {
                    path: format!("closure/{i}"),
                    digest: Some(digest),
                }),
        );
        let result = pb::ActionResult {
            output_files,
            exit_code: 0,
        };
        if result.encoded_len() > 1024 * 1024 {
            bail!("compilation output graph index exceeds REAPI limit");
        }
        let _: pb::ActionResult = self
            .unary(
                concat!(
                    "/build.bazel.remote.execution.v2.",
                    "ActionCache/UpdateActionResult"
                ),
                pb::UpdateActionResultRequest {
                    instance_name: self.instance.clone(),
                    action_digest: Some(action_digest),
                    action_result: Some(result),
                    digest_function: 1,
                },
            )
            .await?
            .ok_or_else(|| eyre!("REAPI refused action publication"))?;
        Ok(())
    }

    async fn resolve(&self, digest: &CacheDigest) -> Result<pb::Digest> {
        digest.validate()?;
        if digest.algorithm == "sha256" {
            return Ok(pb::Digest {
                hash: digest.hash.clone(),
                size_bytes: i64::try_from(digest.size)?,
            });
        }
        if let Some(found) = self.indexes.lock().await.get(digest).cloned() {
            return Ok(found);
        }
        let result = self
            .action("blob", digest)
            .await?
            .ok_or_else(|| eyre!("compilation blob index missing"))?;
        let found = result
            .output_files
            .into_iter()
            .find(|f| f.path == "record")
            .and_then(|f| f.digest)
            .ok_or_else(|| eyre!("invalid compilation blob index"))?;
        validate_sha(&found)?;
        if found.size_bytes as u64 != digest.size {
            bail!("compilation blob index size mismatch");
        }
        let mut indexes = self.indexes.lock().await;
        if indexes.len() >= GRAPH_LIMIT {
            indexes.clear();
        }
        indexes.insert(digest.clone(), found.clone());
        Ok(found)
    }

    async fn read_file(
        &self,
        digest: &pb::Digest,
        directory: &Path,
    ) -> Result<tempfile::NamedTempFile> {
        let mut guard = self.read_guard(true)?;
        validate_sha(digest)?;
        tokio::fs::create_dir_all(directory).await?;
        let file = tempfile::NamedTempFile::new_in(directory)?;
        if digest == &sha(&[]) {
            guard.failed = false;
            return Ok(file);
        }
        let mut report =
            crate::public_cache_report::Transfer::new(&digest.hash, digest.size_bytes, "download");
        let mut destination = tokio::fs::OpenOptions::new()
            .write(true)
            .open(file.path())
            .await?;
        let mut hasher = Sha256::new();
        let mut offset = 0i64;
        let resource = format!(
            "{}/blobs/{}/{}",
            self.instance, digest.hash, digest.size_bytes
        );
        let transfer = async {
            let mut stalled_attempts = 0;
            loop {
                let before = offset;
                let remaining = if !self.read_budget.is_zero() {
                    self.read_budget
                        .saturating_sub(Duration::from_nanos(
                            self.read_spent.load(Ordering::Relaxed),
                        ))
                        .saturating_sub(guard.started.elapsed())
                } else {
                    self.config.read_timeout
                };
                let timeout = self.config.read_timeout.min(remaining);
                if timeout.is_zero() {
                    bail!("remote cache read-stall budget exhausted");
                }
                let attempt = async {
                    let response = tokio::time::timeout(timeout, async {
                        let mut grpc = self.grpc().await?;
                        Ok::<_, eyre::Report>(grpc
                        .server_streaming(
                            self.stream_request(pb::ReadRequest {
                                resource_name: resource.clone(),
                                read_offset: offset,
                                read_limit: 0,
                            })
                            .await?,
                            http::uri::PathAndQuery::from_static(
                                "/google.bytestream.ByteStream/Read",
                            ),
                            tonic_prost::ProstCodec::<pb::ReadRequest, pb::ReadResponse>::default(),
                        )
                        .await?)
                    })
                    .await??;
                    let mut stream = response.into_inner();
                    while let Some(chunk) =
                        tokio::time::timeout(timeout, stream.message()).await??
                    {
                        let next = offset + chunk.data.len() as i64;
                        if next > digest.size_bytes {
                            bail!("REAPI blob exceeds declared size");
                        }
                        destination.write_all(&chunk.data).await?;
                        hasher.update(&chunk.data);
                        offset = next;
                    }
                    if offset != digest.size_bytes {
                        bail!("truncated REAPI blob");
                    }
                    Ok::<_, eyre::Report>(())
                }
                .await;
                match attempt {
                    Ok(()) => break,
                    Err(error) => {
                        let deterministic =
                            error.downcast_ref::<tonic::Status>().is_some_and(|s| {
                                !matches!(
                                    s.code(),
                                    Code::Unavailable | Code::DeadlineExceeded | Code::Cancelled
                                )
                            });
                        if deterministic
                            || error.downcast_ref::<std::io::Error>().is_some()
                            || offset > digest.size_bytes
                        {
                            return Err(error);
                        }
                        stalled_attempts = if offset > before {
                            0
                        } else {
                            stalled_attempts + 1
                        };
                        if stalled_attempts > self.config.retries.clamp(0, 3) {
                            return Err(error);
                        }
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    }
                }
            }
            destination.flush().await?;
            if offset != digest.size_bytes || hex::encode(hasher.finalize()) != digest.hash {
                bail!("corrupt REAPI blob");
            }
            Ok::<_, eyre::Report>(())
        };
        tokio::time::timeout(self.config.download_timeout, transfer).await??;
        guard.failed = false;
        report.complete("downloaded");
        Ok(file)
    }

    async fn read_bytes(&self, digest: &pb::Digest) -> Result<Vec<u8>> {
        if digest.size_bytes < 0 || digest.size_bytes as u64 > JSON_LIMIT {
            bail!("compilation cache record exceeds limit");
        }
        let directory = tempfile::tempdir()?;
        let file = self.read_file(digest, directory.path()).await?;
        Ok(tokio::fs::read(file.path()).await?)
    }

    async fn upload_file(&self, digest: &pb::Digest, path: &Path) -> Result<()> {
        let upload = async {
            let mut attempt = 0;
            loop {
                match self.upload_once(digest, path).await {
                    Ok(()) => return Ok(()),
                    Err(error) if attempt < self.config.retries.min(3) => {
                        let delay = error
                            .downcast_ref::<tonic::Status>()
                            .and_then(|status| crate::reapi_retry::delay(status, attempt));
                        let Some(delay) = delay else {
                            return Err(error);
                        };
                        attempt += 1;
                        tokio::time::sleep(delay).await;
                    }
                    Err(error) => return Err(error),
                }
            }
        };
        tokio::time::timeout(self.config.download_timeout, upload).await?
    }

    async fn upload_once(&self, digest: &pb::Digest, path: &Path) -> Result<()> {
        let mut report =
            crate::public_cache_report::Transfer::new(&digest.hash, digest.size_bytes, "upload");
        self.check_connection().await?;
        validate_sha(digest)?;
        let missing: pb::FindMissingBlobsResponse = self
            .unary(
                concat!(
                    "/build.bazel.remote.execution.v2.",
                    "ContentAddressableStorage/FindMissingBlobs"
                ),
                pb::FindMissingBlobsRequest {
                    instance_name: self.instance.clone(),
                    blob_digests: vec![digest.clone()],
                    digest_function: 1,
                },
            )
            .await?
            .ok_or_else(|| eyre!("missing presence response"))?;
        if missing.missing_blob_digests.is_empty() {
            report.complete("present");
            return Ok(());
        }
        let input = tokio::fs::File::open(path).await?;
        let resource = format!(
            "{}/uploads/{}/blobs/{}/{}",
            self.instance,
            rand::random::<u128>(),
            digest.hash,
            digest.size_bytes
        );
        let size = digest.size_bytes;
        let stream = futures_util::stream::unfold(
            (input, 0i64, resource, false),
            move |(mut input, offset, resource, finished)| async move {
                if finished {
                    return None;
                }
                let mut data = vec![0; CHUNK.min((size - offset).max(0) as usize)];
                let count = input.read(&mut data).await.ok()?;
                data.truncate(count);
                let end = offset + count as i64;
                let finish = end == size;
                if count == 0 && !finish {
                    return None;
                }
                let request = pb::WriteRequest {
                    resource_name: resource.clone(),
                    write_offset: offset,
                    finish_write: finish,
                    data,
                };
                Some((request, (input, end, resource, finish)))
            },
        );
        let mut grpc = self.grpc().await?;
        let response: tonic::Response<pb::WriteResponse> = grpc
            .client_streaming(
                self.stream_request(stream).await?,
                http::uri::PathAndQuery::from_static("/google.bytestream.ByteStream/Write"),
                tonic_prost::ProstCodec::<pb::WriteRequest, pb::WriteResponse>::default(),
            )
            .await?;
        if response.into_inner().committed_size != size {
            bail!("incomplete REAPI upload");
        }
        report.complete("uploaded");
        Ok(())
    }

    async fn upload_bytes(&self, digest: &pb::Digest, bytes: &[u8]) -> Result<()> {
        if &sha(bytes) != digest {
            bail!("invalid SHA-256 upload");
        }
        let file = tempfile::NamedTempFile::new()?;
        tokio::fs::write(file.path(), bytes).await?;
        self.upload_file(digest, file.path()).await
    }

    pub(crate) async fn put_blob(&self, upload: &BlobUpload) -> Result<()> {
        let temporary;
        let path = match &upload.source {
            BlobSource::Bytes(bytes) => {
                temporary = tempfile::NamedTempFile::new()?;
                tokio::fs::write(temporary.path(), bytes).await?;
                temporary.path()
            }
            BlobSource::File(file) => file.path(),
            BlobSource::Path(path) => path.as_path(),
        };
        let source = upload.digest.clone();
        let owned_path = path.to_owned();
        let digest = tokio::task::spawn_blocking(move || -> Result<pb::Digest> {
            if !source.matches_file(&owned_path)? {
                bail!("invalid local compilation blob");
            }
            let mut file = std::fs::File::open(owned_path)?;
            let mut hasher = Sha256::new();
            let mut size = 0u64;
            let mut buffer = vec![0u8; CHUNK];
            loop {
                let count = std::io::Read::read(&mut file, &mut buffer)?;
                if count == 0 {
                    break;
                }
                hasher.update(&buffer[..count]);
                size += count as u64;
            }
            Ok(pb::Digest {
                hash: hex::encode(hasher.finalize()),
                size_bytes: i64::try_from(size)?,
            })
        })
        .await??;
        self.upload_file(&digest, path).await?;
        self.publish("blob", &upload.digest, digest.clone(), vec![])
            .await?;
        let mut indexes = self.indexes.lock().await;
        if indexes.len() >= GRAPH_LIMIT {
            indexes.clear();
        }
        indexes.insert(upload.digest.clone(), digest);
        Ok(())
    }

    pub(crate) async fn get_blob_file(
        &self,
        digest: &CacheDigest,
        directory: &Path,
    ) -> Result<tempfile::NamedTempFile> {
        let remote = self.resolve(digest).await?;
        let file = self.read_file(&remote, directory).await?;
        let path = file.path().to_owned();
        let expected = digest.clone();
        if !tokio::task::spawn_blocking(move || expected.matches_file(&path)).await?? {
            bail!("compilation identity verification failed");
        }
        Ok(file)
    }

    pub(crate) async fn get_blob(&self, digest: &CacheDigest, _: &'static str) -> Result<Vec<u8>> {
        if digest.size > JSON_LIMIT {
            bail!("compilation record exceeds limit");
        }
        let directory = tempfile::tempdir()?;
        let file = self.get_blob_file(digest, directory.path()).await?;
        Ok(tokio::fs::read(file.path()).await?)
    }

    async fn record(&self, kind: &str, key: &CacheDigest) -> Result<Option<Vec<u8>>> {
        Ok(self
            .record_with_references(kind, key)
            .await?
            .map(|(bytes, _)| bytes))
    }

    async fn record_with_references(
        &self,
        kind: &str,
        key: &CacheDigest,
    ) -> Result<Option<(Vec<u8>, Vec<pb::Digest>)>> {
        let Some(result) = self.action(kind, key).await? else {
            return Ok(None);
        };
        let references = result
            .output_files
            .iter()
            .filter_map(|f| f.digest.clone())
            .collect();
        let digest = result
            .output_files
            .into_iter()
            .find(|f| f.path == "record")
            .and_then(|f| f.digest)
            .ok_or_else(|| eyre!("invalid compilation record"))?;
        self.read_bytes(&digest)
            .await
            .map(|bytes| Some((bytes, references)))
    }

    pub(crate) async fn get_action_result(
        &self,
        key: &CacheDigest,
    ) -> Result<Option<RemoteActionResult>> {
        let Some((bytes, references)) = self.record_with_references("action", key).await? else {
            return Ok(None);
        };
        let result: RemoteActionResult = serde_json::from_slice(&bytes)?;
        if result.version != 1 || &result.action != key {
            bail!("invalid compilation action result");
        }
        for reference in references {
            report_reference(key, &reference);
        }
        Ok(Some(result))
    }

    pub(crate) async fn put_action_result(&self, result: &RemoteActionResult) -> Result<()> {
        if result.version != 1 {
            bail!("unsupported compilation action result");
        }
        let mut pending = Vec::new();
        if let Some(metadata) = &result.metadata {
            pending.push((metadata.clone(), 1));
        }
        if let Some(directory) = &result.output_root {
            pending.push((directory.clone(), 2));
        }
        let mut visited = BTreeSet::new();
        let mut closure = Vec::new();
        while let Some((digest, kind)) = pending.pop() {
            if !visited.insert(digest.clone()) {
                continue;
            }
            if visited.len() > GRAPH_LIMIT {
                bail!("compilation output graph exceeds limit");
            }
            closure.push(self.resolve(&digest).await?);
            if kind == 2 {
                let bytes = self.get_blob(&digest, crate::DIRECTORY_MEDIA_TYPE).await?;
                let directory: CacheDirectory = serde_json::from_slice(&bytes)?;
                if directory.version != 1 {
                    bail!("unsupported compilation output directory");
                }
                pending.extend(directory.files.into_iter().map(|f| (f.digest, 0)));
                pending.extend(directory.directories.into_iter().map(|d| (d.digest, 2)));
            } else if kind == 1 {
                let metadata: serde_json::Value = serde_json::from_slice(
                    &self
                        .get_blob(&digest, crate::CLIENT_METADATA_MEDIA_TYPE)
                        .await?,
                )?;
                for field in ["stdout", "stderr"] {
                    if let Some(value) = metadata.get(field) {
                        pending.push((serde_json::from_value(value.clone())?, 0));
                    }
                }
            }
        }
        let bytes = canonical_json(result)?;
        let digest = sha(&bytes);
        self.upload_bytes(&digest, &bytes).await?;
        for reference in &closure {
            report_reference(&result.action, reference);
        }
        report_reference(&result.action, &digest);
        self.publish("action", &result.action, digest, closure)
            .await
    }

    pub(crate) async fn get_action_manifest(
        &self,
        key: &CacheDigest,
    ) -> Result<Option<RemoteActionManifest>> {
        let Some(bytes) = self.record("prediction", key).await? else {
            return Ok(None);
        };
        let manifest: crate::TaskActionManifest = serde_json::from_slice(&bytes)?;
        if !manifest.validate() || &manifest.selector_digest() != key {
            bail!("invalid compilation prediction manifest");
        }
        Ok(Some(RemoteActionManifest {
            etag: sha(&bytes).hash,
            bytes,
        }))
    }

    pub(crate) async fn put_action_manifest(
        &self,
        key: &CacheDigest,
        bytes: &[u8],
        expected: Option<&str>,
    ) -> Result<ManifestPutOutcome> {
        if bytes.len() as u64 > JSON_LIMIT {
            bail!("prediction manifest exceeds limit");
        }
        let manifest: crate::TaskActionManifest = serde_json::from_slice(bytes)?;
        if !manifest.validate() || &manifest.selector_digest() != key {
            bail!("invalid compilation prediction manifest");
        }
        let existing = self.get_action_manifest(key).await?;
        if existing.as_ref().map(|m| m.etag.as_str()) != expected {
            return Ok(ManifestPutOutcome::PreconditionFailed);
        }
        // REAPI has no conditional update. This check is only an advisory stale
        // snapshot check; concurrent writers may lose predictions, never hits.
        let digest = sha(bytes);
        self.upload_bytes(&digest, bytes).await?;
        self.publish("prediction", key, digest, vec![]).await?;
        Ok(ManifestPutOutcome::Stored)
    }
}

struct ReadGuard<'a> {
    cache: &'a ReapiRemoteCache,
    started: Instant,
    failed: bool,
}
impl Drop for ReadGuard<'_> {
    fn drop(&mut self) {
        if self.failed {
            let nanos = self.started.elapsed().as_nanos().min(u64::MAX as u128) as u64;
            let _ =
                self.cache
                    .read_spent
                    .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |spent| {
                        Some(spent.saturating_add(nanos))
                    });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cache() -> ReapiRemoteCache {
        ReapiRemoteCache::new(RemoteCacheConfig {
            base_url: "https://cache.example.com".parse().unwrap(),
            namespace: "account/project".into(),
            token: Some("fixture-token".into()),
            token_file: None,
            oidc_audience: None,
            connect_timeout: Duration::from_secs(1),
            read_timeout: Duration::from_secs(1),
            download_timeout: Duration::from_secs(1),
            retries: 1,
        })
        .unwrap()
    }

    #[tokio::test]
    async fn account_metadata_and_project_instance_match_kura_authorization() {
        let cache = cache();
        assert_eq!(cache.instance, "project");
        assert_eq!(cache.account, "account");
        let request = cache
            .request(pb::GetCapabilitiesRequest {
                instance_name: cache.instance.clone(),
            })
            .await
            .unwrap();
        assert_eq!(
            request.metadata().get("x-tuist-account-handle").unwrap(),
            "account"
        );
        assert_eq!(
            request.metadata().get("authorization").unwrap(),
            "Bearer fixture-token"
        );
        assert_eq!(request.get_ref().instance_name, "project");
    }

    #[tokio::test]
    async fn a_peer_that_accepts_but_never_answers_is_bounded_by_read_timeout() {
        for streaming in [false, true] {
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let server = tokio::spawn(async move {
                let (_stream, _) = listener.accept().await.unwrap();
                tokio::time::sleep(Duration::from_secs(10)).await;
            });
            let mut cache = cache();
            cache.config.base_url = format!("http://{address}").parse().unwrap();
            cache.config.connect_timeout = Duration::from_secs(5);
            cache.config.read_timeout = Duration::from_millis(75);
            cache.config.download_timeout = Duration::from_secs(600);
            cache.config.retries = 0;
            let started = Instant::now();
            if streaming {
                cache
                    .capabilities
                    .set(pb::CacheCapabilities {
                        digest_functions: vec![1],
                        ..Default::default()
                    })
                    .unwrap();
                let directory = tempfile::tempdir().unwrap();
                assert!(
                    cache
                        .read_file(&sha(b"content"), directory.path())
                        .await
                        .is_err()
                );
            } else {
                assert!(cache.check_connection().await.is_err());
            }
            assert!(started.elapsed() < Duration::from_secs(1));
            server.abort();
        }
    }

    #[test]
    fn read_stall_budget_blocks_reads_but_not_publication() {
        let mut cache = cache();
        cache.set_read_stall_budget(Duration::from_nanos(10));
        cache.read_spent.store(10, Ordering::Relaxed);
        assert!(cache.read_guard(true).is_err());
        assert!(cache.read_guard(false).is_ok());
        cache.set_read_stall_budget(Duration::ZERO);
        assert!(cache.read_guard(true).is_ok());
    }

    #[test]
    fn action_indexes_are_real_sha256_actions_and_domain_separated() {
        let identity = CacheDigest::blake3(b"input");
        let (blob, inputs) = index_action("blob", &identity).unwrap();
        let (action, _) = index_action("action", &identity).unwrap();
        let (prediction, _) = index_action("prediction", &identity).unwrap();
        assert_ne!(blob.hash, identity.hash);
        assert_ne!(blob, action);
        assert_ne!(blob, prediction);
        let (digest, bytes) = inputs.last().unwrap();
        assert_eq!(digest, &sha(bytes));
        assert_eq!(digest, &blob);
        assert!(pb::Action::decode(bytes.as_slice()).is_ok());
    }
}
