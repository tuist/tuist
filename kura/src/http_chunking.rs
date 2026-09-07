//! Negotiated upload deduplication. Completion publishes an ordinary artifact,
//! so readers and replication peers need no knowledge of this transfer protocol.
use super::*;
use sha2::{Digest as _, Sha256};

const MAX_CHUNK_BYTES: usize = 2 * 1024 * 1024;
const MAX_CHUNKS: usize = 16_384;
const COPY_BYTES: usize = 64 * 1024;
const JSON_BYTES: usize = 2 * 1024 * 1024;

type ErrorResponse = Box<Response>;

fn error_response(status: StatusCode, message: impl Into<String>) -> ErrorResponse {
    Box::new(super::error_response(status, message.into()))
}

fn overloaded_response(message: &str) -> ErrorResponse {
    Box::new(super::overloaded_response(message))
}

#[derive(Clone, Deserialize, Serialize)]
pub(super) struct ChunkDigest {
    hash: String,
    size: u64,
}

impl ChunkDigest {
    fn valid(&self, max_size: u64) -> bool {
        self.size > 0
            && self.size <= max_size
            && self.hash.len() == 64
            && self
                .hash
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    }

    fn key(&self) -> String {
        format!("transfer_chunks/v1/{}/{}", self.hash, self.size)
    }
}

#[derive(Deserialize)]
struct MissingRequest {
    chunks: Vec<ChunkDigest>,
}

#[derive(Deserialize, Serialize)]
struct CompleteRequest {
    blob: ChunkDigest,
    chunks: Vec<ChunkDigest>,
}

fn producer(params: &HashMap<String, String>) -> Result<ArtifactProducer, ErrorResponse> {
    match params.get("kind").map(String::as_str) {
        Some("module") => Ok(ArtifactProducer::Module),
        Some("gradle") => Ok(ArtifactProducer::Gradle),
        _ => Err(error_response(
            StatusCode::BAD_REQUEST,
            "kind must be module or gradle",
        )),
    }
}

fn namespace(params: &HashMap<String, String>) -> Result<NamespaceQuery, ErrorResponse> {
    let namespace = NamespaceQuery::from_params(params)
        .map_err(|error| error_response(StatusCode::BAD_REQUEST, error))?;
    if namespace.scope != NamespaceScope::Project {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "chunk transfers require a project",
        ));
    }
    Ok(namespace)
}

fn validate_chunks(chunks: &[ChunkDigest]) -> Result<(), ErrorResponse> {
    if chunks.is_empty()
        || chunks.len() > MAX_CHUNKS
        || chunks
            .iter()
            .any(|chunk| !chunk.valid(MAX_CHUNK_BYTES as u64))
    {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "invalid chunk digests or count",
        ));
    }
    Ok(())
}

fn storage_error(error: String) -> ErrorResponse {
    error_response(StatusCode::SERVICE_UNAVAILABLE, error)
}

fn persistence_error(state: &SharedState, error: String) -> ErrorResponse {
    if is_outbox_full_error(&error) {
        Box::new(capacity_shed_response(
            &state.metrics,
            "outbox",
            "server is shedding writes while replication catches up",
        ))
    } else {
        storage_error(error)
    }
}

async fn json_body<T: serde::de::DeserializeOwned>(
    state: &SharedState,
    request: Request,
) -> Result<(T, Option<crate::memory::MemoryPermit>), ErrorResponse> {
    let permit = state
        .memory
        .try_acquire_reapi_materialization(JSON_BYTES * 4)
        .map_err(|()| overloaded_response("server is limiting chunk metadata memory"))?;
    let bytes = to_bytes(request.into_body(), JSON_BYTES)
        .await
        .map_err(|_| error_response(StatusCode::PAYLOAD_TOO_LARGE, "chunk metadata too large"))?;
    let decoded = serde_json::from_slice(&bytes)
        .map_err(|_| error_response(StatusCode::BAD_REQUEST, "invalid chunk metadata"))?;
    Ok((decoded, permit))
}

pub(super) async fn capabilities(Query(params): Query<HashMap<String, String>>) -> Response {
    if let Err(response) = namespace(&params) {
        return *response;
    }
    Json(serde_json::json!({
        "version": 1,
        "download_version": 1,
        "algorithm": "fastcdc2020",
        "average_chunk_bytes": 524288,
        "seed": 0,
        "normalization": 2,
        "minimum_blob_bytes": MAX_CHUNK_BYTES,
        "maximum_chunk_bytes": MAX_CHUNK_BYTES,
        "maximum_chunks": MAX_CHUNKS
    }))
    .into_response()
}

pub(super) async fn missing(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    match missing_inner(&params, &state, request).await {
        Ok(response) => response,
        Err(response) => *response,
    }
}

async fn missing_inner(
    params: &HashMap<String, String>,
    state: &SharedState,
    request: Request,
) -> Result<Response, ErrorResponse> {
    let namespace = namespace(params)?;
    let producer = producer(params)?;
    let (body, permit) = json_body::<MissingRequest>(state, request).await?;
    validate_chunks(&body.chunks)?;
    let mut missing = Vec::new();
    for chunk in body.chunks {
        if !state
            .store
            .artifact_exists(producer, &namespace.namespace_id, &chunk.key())
            .await
            .map_err(storage_error)?
        {
            missing.push(chunk);
        }
    }
    let mut response = Json(serde_json::json!({"missing": missing})).into_response();
    if let Some(permit) = permit {
        attach_materialized_response_permit(&mut response, permit);
    }
    Ok(response)
}

pub(super) async fn upload(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    match upload_inner(&params, &state, request).await {
        Ok(response) => response,
        Err(response) => *response,
    }
}

async fn upload_inner(
    params: &HashMap<String, String>,
    state: &SharedState,
    request: Request,
) -> Result<Response, ErrorResponse> {
    let namespace = namespace(params)?;
    let producer = producer(params)?;
    let digest = ChunkDigest {
        hash: params.get("hash").cloned().unwrap_or_default(),
        size: params
            .get("size")
            .and_then(|value| value.parse().ok())
            .unwrap_or_default(),
    };
    if !digest.valid(MAX_CHUNK_BYTES as u64) {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "invalid chunk digest",
        ));
    }
    let _permit = state
        .memory
        .try_acquire_reapi_materialization(MAX_CHUNK_BYTES * 2)
        .map_err(|()| overloaded_response("server is limiting chunk upload memory"))?;
    let bytes = to_bytes(request.into_body(), MAX_CHUNK_BYTES)
        .await
        .map_err(|_| error_response(StatusCode::PAYLOAD_TOO_LARGE, "chunk too large"))?;
    if bytes.len() as u64 != digest.size || hex::encode(Sha256::digest(&bytes)) != digest.hash {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "chunk digest mismatch",
        ));
    }
    state
        .store
        .persist_artifact_from_bytes_and_enqueue(
            producer,
            &namespace.namespace_id,
            &digest.key(),
            "application/octet-stream",
            &bytes,
            &replication_targets(state),
        )
        .await
        .map_err(|error| persistence_error(state, error))?;
    state.notify.notify_one();
    Ok(StatusCode::NO_CONTENT.into_response())
}

pub(super) async fn complete(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
    request: Request,
) -> Response {
    match complete_inner(&params, &state, request).await {
        Ok(response) => response,
        Err(response) => *response,
    }
}

async fn complete_inner(
    params: &HashMap<String, String>,
    state: &SharedState,
    request: Request,
) -> Result<Response, ErrorResponse> {
    let namespace = namespace(params)?;
    let producer = producer(params)?;
    let (body, _permit) = json_body::<CompleteRequest>(state, request).await?;
    validate_chunks(&body.chunks)?;
    let (key, max_size) = match producer {
        ArtifactProducer::Module => (
            ModuleQuery::from_params(params)
                .map_err(|error| error_response(StatusCode::BAD_REQUEST, error))?
                .artifact_key(),
            MAX_MODULE_TOTAL_BYTES,
        ),
        _ => {
            let key = required_param(params, "cache_key")
                .map_err(|error| error_response(StatusCode::BAD_REQUEST, error))?;
            if key.len() > 128 || !key.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                return Err(error_response(
                    StatusCode::BAD_REQUEST,
                    "invalid Gradle cache key",
                ));
            }
            (key, MAX_GRADLE_BYTES)
        }
    };
    if !body.blob.valid(max_size)
        || body.chunks.iter().map(|chunk| chunk.size).sum::<u64>() != body.blob.size
    {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "invalid artifact size or digest",
        ));
    }
    let reservation = state
        .tmp_staging_budget
        .try_reserve(body.blob.size)
        .map_err(storage_error)?;
    let staging_memory =
        crate::file_cache::reserve_foreground_staging(&state.memory, body.blob.size)
            .await
            .map_err(|_| overloaded_response("server is limiting artifact staging memory"))?;
    let file_cache_policy = staging_memory.file_cache_policy();
    let directory = state.config.tmp_dir.join("uploads");
    state
        .io
        .create_dir_all(&directory)
        .await
        .map_err(storage_error)?;
    let path = temp_file_path(&directory, "chunk-complete");
    let mut cleanup = TempFileCleanup::new(path.clone(), reservation);
    let mut output = state.io.create_file(&path).await.map_err(storage_error)?;
    let mut hasher = Sha256::new();
    let mut written = 0u64;
    let mut advised_through = 0u64;
    for chunk in &body.chunks {
        let manifest = state
            .store
            .fetch_artifact(producer, &namespace.namespace_id, &chunk.key())
            .await
            .map_err(storage_error)?
            .ok_or_else(|| {
                error_response(StatusCode::CONFLICT, "chunk is missing; retry upload")
            })?;
        if manifest.size != chunk.size {
            return Err(error_response(StatusCode::CONFLICT, "chunk size changed"));
        }
        let mut reader = state
            .store
            .open_artifact_reader_range_tolerating_promotion_reader_only(&manifest, 0, None)
            .await
            .map_err(storage_error)?
            .ok_or_else(|| {
                error_response(StatusCode::CONFLICT, "chunk was evicted; retry upload")
            })?;
        let mut chunk_hasher = Sha256::new();
        let mut read = 0u64;
        loop {
            let bytes = reader
                .read_chunk_owned(COPY_BYTES)
                .await
                .map_err(|error| storage_error(error.to_string()))?;
            if bytes.is_empty() {
                break;
            }
            read += bytes.len() as u64;
            if read > chunk.size {
                return Err(error_response(StatusCode::CONFLICT, "chunk size mismatch"));
            }
            chunk_hasher.update(&bytes);
            hasher.update(&bytes);
            output
                .write_all(&bytes)
                .await
                .map_err(|error| storage_error(error.to_string()))?;
            written += bytes.len() as u64;
            if file_cache_policy.should_drop(
                state.memory.should_reclaim_file_cache(),
                state.memory.transient_reserved_bytes(),
            ) && written - advised_through
                >= crate::file_cache::FOREGROUND_FILE_CACHE_DROP_INTERVAL_BYTES
            {
                output = crate::utils::drop_staging_cache_range(
                    output,
                    &path,
                    advised_through,
                    written - advised_through,
                    &state.io,
                )
                .await
                .map_err(storage_error)?;
                advised_through = written;
            }
        }
        if read != chunk.size || hex::encode(chunk_hasher.finalize()) != chunk.hash {
            return Err(error_response(
                StatusCode::CONFLICT,
                "chunk integrity check failed",
            ));
        }
    }
    if hex::encode(hasher.finalize()) != body.blob.hash {
        return Err(error_response(
            StatusCode::BAD_REQUEST,
            "artifact digest mismatch",
        ));
    }
    output
        .flush()
        .await
        .map_err(|error| storage_error(error.to_string()))?;
    drop(output);
    // Keep the recipe binding in metadata that old peers already preserve.
    // The media type stays application/octet-stream, including for old clients.
    // A content digest, unlike a timestamp, cannot alias a concurrent write.
    let content_type = format!(
        "application/octet-stream; tuist-chunks-sha256={}",
        body.blob.hash
    );
    let recipe_bytes =
        serde_json::to_vec(&body).map_err(|error| storage_error(error.to_string()))?;
    state
        .store
        .persist_artifact_from_bytes_and_enqueue(
            producer,
            &namespace.namespace_id,
            &recipe_key(&body.blob),
            "application/json",
            &recipe_bytes,
            &replication_targets(state),
        )
        .await
        .map_err(|error| persistence_error(state, error))?;
    let persisted = state
        .store
        .persist_artifact_from_path_and_enqueue(
            producer,
            &namespace.namespace_id,
            &key,
            &content_type,
            StagedArtifactPath::new(&path, file_cache_policy),
            &replication_targets(state),
        )
        .await
        .map_err(|error| persistence_error(state, error))?;
    cleanup.remove_and_disarm(&state.io).await;
    state.notify.notify_one();
    state
        .metrics
        .record_artifact_write(producer, "ok", persisted.manifest.size);
    if !persisted.already_present {
        record_usage_event(
            state,
            producer,
            "upload",
            Some(&namespace.usage_context()),
            persisted.manifest.size,
        );
    }
    record_project_scoped_cache_event(
        state,
        producer,
        "upload",
        namespace.project_analytics_context(),
        &key,
        persisted.manifest.size,
    );
    Ok(StatusCode::NO_CONTENT.into_response())
}

fn recipe_key(blob: &ChunkDigest) -> String {
    format!("transfer_recipes/v1/{}/{}", blob.hash, blob.size)
}

pub(super) async fn manifest(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    match manifest_inner(&params, &state).await {
        Ok(response) => response,
        Err(response) => *response,
    }
}

async fn manifest_inner(
    params: &HashMap<String, String>,
    state: &SharedState,
) -> Result<Response, ErrorResponse> {
    let namespace = namespace(params)?;
    let producer = producer(params)?;
    let key = if producer == ArtifactProducer::Module {
        ModuleQuery::from_params(params)
            .map_err(|error| error_response(StatusCode::BAD_REQUEST, error))?
            .artifact_key()
    } else {
        required_param(params, "cache_key")
            .map_err(|error| error_response(StatusCode::BAD_REQUEST, error))?
    };
    let artifact = state
        .store
        .fetch_artifact_for_serving(producer, &namespace.namespace_id, &key)
        .await
        .map_err(storage_error)?
        .ok_or_else(|| error_response(StatusCode::NOT_FOUND, "artifact missing"))?;
    let hash = artifact
        .content_type
        .strip_prefix("application/octet-stream; tuist-chunks-sha256=")
        .ok_or_else(|| error_response(StatusCode::NOT_FOUND, "artifact has no chunk manifest"))?;
    let blob = ChunkDigest {
        hash: hash.into(),
        size: artifact.size,
    };
    if !blob.valid(MAX_MODULE_TOTAL_BYTES) {
        return Err(error_response(
            StatusCode::NOT_FOUND,
            "invalid manifest binding",
        ));
    }
    let recipe = state
        .store
        .fetch_artifact_for_serving(producer, &namespace.namespace_id, &recipe_key(&blob))
        .await
        .map_err(storage_error)?
        .ok_or_else(|| error_response(StatusCode::NOT_FOUND, "chunk manifest missing"))?;
    if recipe.size > JSON_BYTES as u64 {
        return Err(error_response(
            StatusCode::NOT_FOUND,
            "chunk manifest too large",
        ));
    }
    let permit = state
        .memory
        .try_acquire_reapi_materialization(JSON_BYTES * 4)
        .map_err(|()| overloaded_response("server is limiting chunk metadata memory"))?;
    let bytes = state
        .store
        .read_artifact_bytes_tolerating_promotion(&recipe)
        .await
        .map_err(storage_error)?
        .ok_or_else(|| error_response(StatusCode::NOT_FOUND, "chunk manifest evicted"))?;
    let decoded: CompleteRequest = serde_json::from_slice(&bytes)
        .map_err(|_| error_response(StatusCode::NOT_FOUND, "invalid chunk manifest"))?;
    validate_chunks(&decoded.chunks)?;
    if decoded.blob.hash != blob.hash
        || decoded.blob.size != blob.size
        || decoded.chunks.iter().map(|chunk| chunk.size).sum::<u64>() != blob.size
    {
        return Err(error_response(
            StatusCode::NOT_FOUND,
            "chunk manifest mismatch",
        ));
    }
    let mut response = Json(decoded).into_response();
    if let Some(permit) = permit {
        attach_materialized_response_permit(&mut response, permit);
    }
    Ok(response)
}

pub(super) async fn download(
    Query(params): Query<HashMap<String, String>>,
    State(state): State<SharedState>,
) -> Response {
    let (namespace, producer) =
        match namespace(&params).and_then(|namespace| Ok((namespace, producer(&params)?))) {
            Ok(value) => value,
            Err(response) => return *response,
        };
    let digest = ChunkDigest {
        hash: params.get("hash").cloned().unwrap_or_default(),
        size: params
            .get("size")
            .and_then(|size| size.parse().ok())
            .unwrap_or_default(),
    };
    if !digest.valid(MAX_CHUNK_BYTES as u64) {
        return *error_response(StatusCode::BAD_REQUEST, "invalid chunk digest");
    }
    get_artifact(
        state,
        producer,
        &namespace.namespace_id,
        &digest.key(),
        None,
        None,
        Some(namespace.usage_context()),
        RangeRequest::default(),
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::test_context;
    use reqwest::Client;
    use serde_json::{Value, json};

    #[tokio::test]
    async fn chunk_routes_require_authorization_in_the_requested_project() {
        use crate::auth::{AuthEngine, config::AuthConfig, tuist::JwtVerifier};
        use crate::test_support::test_context_with_auth;
        use tower::ServiceExt;
        let secret = "chunking-authorization-test";
        let auth = Arc::new(
            AuthEngine::new(
                AuthConfig {
                    base_url: "http://127.0.0.1:1".into(),
                    connect_timeout: Duration::from_millis(50),
                    request_timeout: Duration::from_millis(50),
                    verifier: Some(JwtVerifier {
                        algorithm: jsonwebtoken::Algorithm::HS256,
                        keys: JwtVerifier::secret_keys(secret),
                        issuer: None,
                        audiences: Vec::new(),
                    }),
                    introspection: None,
                    cache_max_entries: 128,
                },
                crate::metrics::Metrics::new("test".into(), "test-tenant".into()),
            )
            .unwrap(),
        );
        let context = test_context_with_auth(|_| {}, Some(auth)).await;
        let app = public_router(context.state.clone());
        let token = jsonwebtoken::encode(&jsonwebtoken::Header::new(jsonwebtoken::Algorithm::HS256), &json!({
            "sub": "reader", "type": "subject", "scopes": [],
            "cache_grants": {"project": {"read": ["test-tenant/project"]}}, "exp": 4102444800_u64,
        }), &jsonwebtoken::EncodingKey::from_secret(secret.as_bytes())).unwrap();
        for (operation, method) in [
            ("capabilities", "GET"),
            ("manifest", "GET"),
            ("download", "GET"),
            ("missing", "POST"),
            ("upload", "PUT"),
            ("complete", "POST"),
        ] {
            let uri = format!(
                "/api/cache/chunks/{operation}?tenant_id=test-tenant&namespace_id=project&kind=gradle"
            );
            let unauthenticated = Request::builder()
                .method(method)
                .uri(&uri)
                .body(Body::empty())
                .unwrap();
            assert_eq!(
                app.clone().oneshot(unauthenticated).await.unwrap().status(),
                StatusCode::UNAUTHORIZED
            );
            let read_only = Request::builder()
                .method(method)
                .uri(&uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap();
            let status = app.clone().oneshot(read_only).await.unwrap().status();
            if operation == "capabilities" {
                assert_eq!(status, StatusCode::OK);
            } else if operation == "manifest" || operation == "download" {
                assert_eq!(status, StatusCode::BAD_REQUEST);
            } else {
                assert!(
                    matches!(
                        status,
                        StatusCode::FORBIDDEN | StatusCode::SERVICE_UNAVAILABLE
                    ),
                    "{operation}: {status}"
                );
            }
            let wrong_tenant = Request::builder()
                .method(method)
                .uri(uri.replace("test-tenant", "other-tenant"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap();
            assert_eq!(
                app.clone().oneshot(wrong_tenant).await.unwrap().status(),
                StatusCode::FORBIDDEN
            );
        }
    }

    fn digest(bytes: &[u8]) -> Value {
        json!({"hash": hex::encode(Sha256::digest(bytes)), "size": bytes.len()})
    }

    #[tokio::test]
    async fn chunked_uploads_are_readable_through_legacy_routes_over_http() {
        let context = test_context(|_| {}).await;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let app = public_router(context.state.clone());
        let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        let client = Client::new();
        for kind in ["module", "gradle"] {
            let query = format!("tenant_id=test-tenant&namespace_id=project&kind={kind}");
            let chunks = [b"first chunk".as_slice(), b"second chunk".as_slice()];
            let digests: Vec<_> = chunks.iter().map(|bytes| digest(bytes)).collect();
            let url = |operation: &str| format!("{base}/api/cache/chunks/{operation}?{query}");
            let missing: Value = client
                .post(url("missing"))
                .json(&json!({"chunks": digests}))
                .send()
                .await
                .unwrap()
                .json()
                .await
                .unwrap();
            assert_eq!(missing["missing"], json!(digests));
            for (bytes, digest) in chunks.iter().zip(&digests) {
                let response = client
                    .put(format!(
                        "{}&hash={}&size={}",
                        url("upload"),
                        digest["hash"].as_str().unwrap(),
                        bytes.len()
                    ))
                    .body(bytes.to_vec())
                    .send()
                    .await
                    .unwrap();
                assert_eq!(response.status(), StatusCode::NO_CONTENT);
            }
            let missing: Value = client
                .post(url("missing"))
                .json(&json!({"chunks": digests}))
                .send()
                .await
                .unwrap()
                .json()
                .await
                .unwrap();
            assert_eq!(missing["missing"], json!([]));
            let isolated: Value = client.post(format!("{base}/api/cache/chunks/missing?tenant_id=test-tenant&namespace_id=other&kind={kind}"))
                .json(&json!({"chunks": digests})).send().await.unwrap().json().await.unwrap();
            assert_eq!(isolated["missing"], json!(digests));
            let bytes = chunks.concat();
            let target = "cache_key=abcdef&hash=module-hash&name=Framework&cache_category=builds";
            let complete = json!({"blob": digest(&bytes), "chunks": digests});
            let response = client
                .post(format!("{}&{target}", url("complete")))
                .json(&complete)
                .send()
                .await
                .unwrap();
            assert_eq!(
                response.status(),
                StatusCode::NO_CONTENT,
                "{}",
                response.text().await.unwrap()
            );
            let manifest: Value = client
                .get(format!("{}&{target}", url("manifest")))
                .send()
                .await
                .unwrap()
                .json()
                .await
                .unwrap();
            assert_eq!(manifest, complete);
            for (chunk, digest) in chunks.iter().zip(&digests) {
                let endpoint = format!(
                    "{}&hash={}&size={}",
                    url("download"),
                    digest["hash"].as_str().unwrap(),
                    chunk.len()
                );
                let response = client.get(&endpoint).send().await.unwrap();
                assert_eq!(response.status(), StatusCode::OK);
                assert_eq!(response.bytes().await.unwrap().as_ref(), *chunk);
                assert_eq!(
                    client
                        .get(endpoint.replace("namespace_id=project", "namespace_id=other"))
                        .send()
                        .await
                        .unwrap()
                        .status(),
                    StatusCode::NOT_FOUND
                );
            }
            let path = if kind == "gradle" {
                "gradle/abcdef"
            } else {
                "module/module-hash"
            };
            let response = client
                .get(format!("{base}/api/cache/{path}?{query}&{target}"))
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            assert_eq!(response.bytes().await.unwrap().as_ref(), bytes);
            let response = client
                .get(format!("{base}/api/cache/{path}?{query}&{target}"))
                .header("Range", "bytes=3-9")
                .send()
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::PARTIAL_CONTENT);
            assert_eq!(response.bytes().await.unwrap().as_ref(), &bytes[3..10]);
            // A later whole upload has no binding, so the older recipe cannot
            // make the read return the previous artifact even if sizes match.
            tokio::time::sleep(Duration::from_millis(2)).await;
            let key = if kind == "gradle" {
                "abcdef".to_string()
            } else {
                ModuleQuery::from_params(&HashMap::from([
                    ("tenant_id".into(), "test-tenant".into()),
                    ("namespace_id".into(), "project".into()),
                    ("hash".into(), "module-hash".into()),
                    ("name".into(), "Framework".into()),
                    ("cache_category".into(), "builds".into()),
                ]))
                .unwrap()
                .artifact_key()
            };
            context
                .state
                .store
                .persist_artifact_from_bytes_and_enqueue(
                    if kind == "gradle" {
                        ArtifactProducer::Gradle
                    } else {
                        ArtifactProducer::Module
                    },
                    "project",
                    &key,
                    "application/octet-stream",
                    &vec![b'x'; bytes.len()],
                    &[],
                )
                .await
                .unwrap();
            assert_eq!(
                client
                    .get(format!("{}&{target}", url("manifest")))
                    .send()
                    .await
                    .unwrap()
                    .status(),
                StatusCode::NOT_FOUND
            );
        }
        server.abort();
    }

    #[tokio::test]
    async fn incomplete_or_corrupt_uploads_never_publish_an_artifact() {
        use tower::ServiceExt;
        let context = test_context(|_| {}).await;
        let shed = persistence_error(
            &context.state,
            "replication outbox capacity exhausted: raced with another upload".into(),
        );
        assert_eq!(shed.status(), StatusCode::TOO_MANY_REQUESTS);
        assert!(shed.headers().contains_key("retry-after"));
        let app = public_router(context.state.clone());
        let query = "tenant_id=test-tenant&namespace_id=project&kind=gradle&cache_key=abcd";
        let chunk = digest(b"payload");
        let request = || {
            Request::builder()
                .method("POST")
                .uri(format!("/api/cache/chunks/complete?{query}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"blob": chunk, "chunks": [chunk]}).to_string(),
                ))
                .unwrap()
        };
        let response = app.clone().oneshot(request()).await.unwrap();
        assert_eq!(response.status(), StatusCode::CONFLICT);
        let wrong = Request::builder()
            .method("PUT")
            .uri(format!(
                "/api/cache/chunks/upload?{query}&hash={}&size=7",
                chunk["hash"].as_str().unwrap()
            ))
            .body(Body::from("corrupt"))
            .unwrap();
        assert_eq!(
            app.clone().oneshot(wrong).await.unwrap().status(),
            StatusCode::BAD_REQUEST
        );
        assert!(
            !context
                .state
                .store
                .artifact_exists(ArtifactProducer::Gradle, "project", "abcd")
                .await
                .unwrap()
        );
        let good = Request::builder()
            .method("PUT")
            .uri(format!(
                "/api/cache/chunks/upload?{query}&hash={}&size=7",
                chunk["hash"].as_str().unwrap()
            ))
            .body(Body::from("payload"))
            .unwrap();
        assert_eq!(
            app.clone().oneshot(good).await.unwrap().status(),
            StatusCode::NO_CONTENT
        );
        let wrong_blob = Request::builder()
            .method("POST")
            .uri(format!("/api/cache/chunks/complete?{query}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({"blob": digest(b"changed"), "chunks": [chunk]}).to_string(),
            ))
            .unwrap();
        assert_eq!(
            app.clone().oneshot(wrong_blob).await.unwrap().status(),
            StatusCode::BAD_REQUEST
        );
        assert!(
            !context
                .state
                .store
                .artifact_exists(ArtifactProducer::Gradle, "project", "abcd")
                .await
                .unwrap()
        );
        assert_eq!(
            app.oneshot(request()).await.unwrap().status(),
            StatusCode::NO_CONTENT
        );
    }

    #[test]
    fn digest_bounds_and_authorization_are_explicit() {
        assert!(validate_chunks(&[]).is_err());
        assert!(
            validate_chunks(&[ChunkDigest {
                hash: "a".repeat(64),
                size: 0
            }])
            .is_err()
        );
        assert!(
            validate_chunks(&[ChunkDigest {
                hash: "A".repeat(64),
                size: 1
            }])
            .is_err()
        );
        assert!(
            validate_chunks(&[ChunkDigest {
                hash: "a".repeat(64),
                size: MAX_CHUNK_BYTES as u64 + 1
            }])
            .is_err()
        );
        assert!(
            validate_chunks(&vec![
                ChunkDigest {
                    hash: "a".repeat(64),
                    size: 1
                };
                MAX_CHUNKS + 1
            ])
            .is_err()
        );
        assert!(namespace(&HashMap::from([("tenant_id".into(), "tenant".into())])).is_err());
        for route in [
            ROUTE_CHUNK_CAPABILITIES,
            ROUTE_CHUNK_MISSING,
            ROUTE_CHUNK_UPLOAD,
            ROUTE_CHUNK_COMPLETE,
            ROUTE_CHUNK_MANIFEST,
            ROUTE_CHUNK_DOWNLOAD,
        ] {
            assert!(!skips_authorization(route));
        }
    }
}
