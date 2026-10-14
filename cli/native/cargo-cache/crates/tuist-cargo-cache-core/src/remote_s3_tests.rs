use super::*;
use crate::*;

/// An S3 error document, as a store would send one.
fn s3_error_body(code: &str) -> String {
    format!("<?xml version=\"1.0\"?><Error><Code>{code}</Code><Message>no</Message></Error>")
}

fn credentials() -> S3Credentials {
    S3Credentials {
        access_key_id: "AKIDEXAMPLE".into(),
        secret_access_key: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY".into(),
        session_token: None,
    }
}

fn config(server: &mockito::ServerGuard) -> S3RemoteCacheConfig {
    S3RemoteCacheConfig {
        bucket: "cache-bucket".into(),
        prefix: String::new(),
        namespace: "acme".into(),
        region: "us-east-1".into(),
        endpoint: Some(server.url().parse().unwrap()),
        force_path_style: None,
        conditional_writes: S3ConditionalWrites::Auto,
        credentials: credentials(),
        connect_timeout: Duration::from_secs(1),
        read_timeout: Duration::from_secs(1),
        download_timeout: Duration::from_secs(1),
        retries: 0,
    }
}

fn test_store(server: &mockito::ServerGuard) -> S3RemoteCache {
    S3RemoteCache::new(config(server)).unwrap()
}

fn test_store_with(
    server: &mockito::ServerGuard,
    download_timeout: Duration,
    retries: i64,
) -> S3RemoteCache {
    S3RemoteCache::new(S3RemoteCacheConfig {
        download_timeout,
        retries,
        ..config(server)
    })
    .unwrap()
}

/// The key a blob of these bytes lands on, under the test configuration.
fn blob_path(digest: &CacheDigest) -> String {
    format!(
        "/cache-bucket/acme/v1/blobs/{}/{}/{}",
        digest.algorithm, digest.hash, digest.size
    )
}

#[tokio::test]
async fn a_blob_round_trips_through_its_content_addressed_key() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"a cached object file";
    let digest = CacheDigest::blake3(contents);
    let request = server
        .mock("GET", blob_path(&digest).as_str())
        .match_header("x-amz-content-sha256", mockito::Matcher::Any)
        .match_header("x-amz-date", mockito::Matcher::Any)
        .match_header(
            "authorization",
            mockito::Matcher::Regex(
                "^AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/[0-9]{8}/us-east-1/s3/aws4_request, \
                 SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=[0-9a-f]{64}$"
                    .into(),
            ),
        )
        .with_status(200)
        .with_body(contents)
        .expect(1)
        .create_async()
        .await;
    let staging = tempfile::tempdir().unwrap();

    let file = test_store(&server)
        .get_blob_file(&digest, staging.path())
        .await
        .unwrap();

    assert_eq!(fs::read(file.path()).unwrap(), contents);
    request.assert_async().await;
}

#[tokio::test]
async fn a_blob_that_fails_verification_is_refused() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"what was asked for");
    // The same length as what was asked for, so the size guard cannot reject it
    // first and verification is what does.
    server
        .mock("GET", blob_path(&digest).as_str())
        .with_status(200)
        .with_body(b"something else!!!!")
        .create_async()
        .await;
    let staging = tempfile::tempdir().unwrap();

    let error = test_store(&server)
        .get_blob_file(&digest, staging.path())
        .await
        .unwrap_err();

    assert!(error.to_string().contains("failed digest verification"));
}

#[tokio::test]
async fn a_blob_larger_than_its_digest_stops_being_read() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"small");
    server
        .mock("GET", blob_path(&digest).as_str())
        .with_status(200)
        .with_body(vec![b'x'; 4096])
        .create_async()
        .await;
    let staging = tempfile::tempdir().unwrap();

    let error = test_store(&server)
        .get_blob_file(&digest, staging.path())
        .await
        .unwrap_err();

    assert!(
        error
            .to_string()
            .contains("exceeded the size of its digest")
    );
}

#[tokio::test]
async fn storing_a_blob_writes_it_create_only() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"a published object";
    let digest = CacheDigest::blake3(contents);
    let request = server
        .mock("PUT", blob_path(&digest).as_str())
        .match_header("if-none-match", "*")
        .match_body(contents.to_vec())
        .with_status(200)
        .expect(1)
        .create_async()
        .await;

    test_store(&server)
        .put_blob(&BlobUpload {
            digest,
            source: BlobSource::Bytes(contents.to_vec()),
        })
        .await
        .unwrap();

    request.assert_async().await;
}

#[tokio::test]
async fn a_blob_the_store_already_holds_is_not_an_error() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"already stored";
    let digest = CacheDigest::blake3(contents);
    server
        .mock("PUT", blob_path(&digest).as_str())
        .with_status(412)
        .with_body(s3_error_body("PreconditionFailed"))
        .create_async()
        .await;

    // The key is the content address of these bytes, so an object already
    // sitting there holds exactly what this upload would have written.
    test_store(&server)
        .put_blob(&BlobUpload {
            digest,
            source: BlobSource::Bytes(contents.to_vec()),
        })
        .await
        .unwrap();
}

#[tokio::test]
async fn a_conflicting_conditional_write_is_retried() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"contended object";
    let digest = CacheDigest::blake3(contents);
    let conflict = server
        .mock("PUT", blob_path(&digest).as_str())
        .with_status(409)
        .with_body(s3_error_body("ConditionalRequestConflict"))
        .expect(1)
        .create_async()
        .await;
    let stored = server
        .mock("PUT", blob_path(&digest).as_str())
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let mut settings = config(&server);
    settings.retries = 1;

    S3RemoteCache::new(settings)
        .unwrap()
        .put_blob(&BlobUpload {
            digest,
            source: BlobSource::Bytes(contents.to_vec()),
        })
        .await
        .unwrap();

    conflict.assert_async().await;
    stored.assert_async().await;
}

#[tokio::test]
async fn a_file_backed_blob_is_streamed_with_its_length() {
    let mut server = mockito::Server::new_async().await;
    let contents = vec![b'z'; 128 * 1024];
    let digest = CacheDigest::blake3(&contents);
    let request = server
        .mock("PUT", blob_path(&digest).as_str())
        .match_header("content-length", contents.len().to_string().as_str())
        // A streamed body is not hashed, so the signature covers everything
        // about the request except bytes TLS and the content address stand
        // behind.
        .match_header("x-amz-content-sha256", "UNSIGNED-PAYLOAD")
        .match_body(contents.to_vec())
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let file = tempfile::NamedTempFile::new().unwrap();
    fs::write(file.path(), &contents).unwrap();

    test_store(&server)
        .put_blob(&BlobUpload {
            digest,
            source: BlobSource::Path(file.path().to_path_buf()),
        })
        .await
        .unwrap();

    request.assert_async().await;
}

#[tokio::test]
async fn a_missing_action_result_is_a_miss_rather_than_an_error() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"an action");
    server
        .mock(
            "GET",
            format!(
                "/cache-bucket/acme/v1/action-results/blake3/{}/{}",
                action.hash, action.size
            )
            .as_str(),
        )
        .with_status(404)
        .with_body(s3_error_body("NoSuchKey"))
        .create_async()
        .await;

    assert!(
        test_store(&server)
            .get_action_result(&action)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn an_action_result_naming_another_action_is_refused() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"an action");
    let other = CacheDigest::blake3(b"a different action");
    server
        .mock(
            "GET",
            format!(
                "/cache-bucket/acme/v1/action-results/blake3/{}/{}",
                action.hash, action.size
            )
            .as_str(),
        )
        .with_status(200)
        .with_body(
            serde_json::to_vec(&RemoteActionResult {
                action: other,
                metadata: None,
                output_root: None,
                version: 1,
            })
            .unwrap(),
        )
        .create_async()
        .await;

    let error = test_store(&server)
        .get_action_result(&action)
        .await
        .unwrap_err();

    assert!(
        error
            .to_string()
            .contains("does not match requested action")
    );
}

/// The key a task action manifest lands on.
fn manifest_path(key: &CacheDigest) -> String {
    format!(
        "/cache-bucket/acme/v1/action-manifests/blake3/{}/{}",
        key.hash, key.size
    )
}

#[tokio::test]
async fn a_manifest_carries_the_entity_tag_its_update_must_send_back() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    server
        .mock("GET", manifest_path(&key).as_str())
        .with_status(200)
        .with_header("etag", "\"d41d8cd98f00b204e9800998ecf8427e\"")
        .with_body("{}")
        .create_async()
        .await;
    let update = server
        .mock("PUT", manifest_path(&key).as_str())
        .match_header("if-match", "\"d41d8cd98f00b204e9800998ecf8427e\"")
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let store = test_store(&server);

    let manifest = store.get_action_manifest(&key).await.unwrap().unwrap();
    assert_eq!(manifest.etag, "d41d8cd98f00b204e9800998ecf8427e");

    let outcome = store
        .put_action_manifest(&key, b"{}", Some(&manifest.etag))
        .await
        .unwrap();

    assert_eq!(outcome, ManifestPutOutcome::Stored);
    update.assert_async().await;
}

#[tokio::test]
async fn a_manifest_that_moved_reports_a_precondition_failure() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a contended task");
    server
        .mock("PUT", manifest_path(&key).as_str())
        .match_header("if-match", "\"stale\"")
        .with_status(412)
        .with_body(s3_error_body("PreconditionFailed"))
        .create_async()
        .await;

    let outcome = test_store(&server)
        .put_action_manifest(&key, b"{}", Some("stale"))
        .await
        .unwrap();

    // The agent answers this by re-reading, merging, and trying again, which is
    // what keeps a concurrent writer's predictions.
    assert_eq!(outcome, ManifestPutOutcome::PreconditionFailed);
}

#[tokio::test]
async fn a_first_manifest_is_written_create_only() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a new task");
    let request = server
        .mock("PUT", manifest_path(&key).as_str())
        .match_header("if-none-match", "*")
        .with_status(200)
        .expect(1)
        .create_async()
        .await;

    let outcome = test_store(&server)
        .put_action_manifest(&key, b"{}", None)
        .await
        .unwrap();

    assert_eq!(outcome, ManifestPutOutcome::Stored);
    request.assert_async().await;
}

#[tokio::test]
async fn a_retryable_status_is_retried() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"an object the store was too busy for";
    let digest = CacheDigest::blake3(contents);
    // S3 answers 503 SlowDown for a prefix under load and asks the client to
    // try again. The protocol backend retries these; so must this one.
    let busy = server
        .mock("PUT", blob_path(&digest).as_str())
        .with_status(503)
        .with_body(s3_error_body("SlowDown"))
        .expect(1)
        .create_async()
        .await;
    let stored = server
        .mock("PUT", blob_path(&digest).as_str())
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let mut settings = config(&server);
    settings.retries = 1;

    S3RemoteCache::new(settings)
        .unwrap()
        .put_blob(&BlobUpload {
            digest,
            source: BlobSource::Bytes(contents.to_vec()),
        })
        .await
        .unwrap();

    busy.assert_async().await;
    stored.assert_async().await;
}

#[tokio::test]
async fn a_store_that_does_not_implement_something_else_is_not_retried_forever() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    // 501 is not transient: a store that does not implement something will not
    // implement it a moment later.
    let refusals = server
        .mock("PUT", manifest_path(&key).as_str())
        .with_status(501)
        .with_body(s3_error_body("NotImplemented"))
        .expect(2)
        .create_async()
        .await;
    let mut settings = config(&server);
    settings.retries = 3;

    let error = S3RemoteCache::new(settings)
        .unwrap()
        .put_action_manifest(&key, b"{}", None)
        .await
        .unwrap_err();

    // One conditional attempt, one unconditional retry, and no more.
    refusals.assert_async().await;
    assert!(error.to_string().contains("failed to update"));
}

#[tokio::test]
async fn a_store_without_conditional_writes_is_used_without_them() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    let refused = server
        .mock("PUT", manifest_path(&key).as_str())
        .match_header("if-none-match", "*")
        .with_status(501)
        .with_body(s3_error_body("NotImplemented"))
        .expect(1)
        .create_async()
        .await;
    let unconditional = server
        .mock("PUT", manifest_path(&key).as_str())
        .match_header("if-none-match", mockito::Matcher::Missing)
        .with_status(200)
        .expect(2)
        .create_async()
        .await;
    let store = test_store(&server);

    assert_eq!(
        store.put_action_manifest(&key, b"{}", None).await.unwrap(),
        ManifestPutOutcome::Stored
    );
    // Having learned it once, the store stops asking for the rest of the
    // session rather than spending a refused round trip on every write.
    assert_eq!(
        store.put_action_manifest(&key, b"{}", None).await.unwrap(),
        ManifestPutOutcome::Stored
    );

    refused.assert_async().await;
    unconditional.assert_async().await;
}

#[tokio::test]
async fn conditionals_stay_on_when_dropping_them_does_not_help() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    // An intermediary answers 501 for a reason that has nothing to do with the
    // condition, so the unconditional retry fails too. Concluding the store
    // cannot do conditional writes would turn every later manifest update into
    // a last-writer-wins one on no evidence.
    server
        .mock("PUT", manifest_path(&key).as_str())
        .with_status(501)
        .with_body(s3_error_body("NotImplemented"))
        .expect_at_least(2)
        .create_async()
        .await;
    let store = test_store(&server);

    assert!(store.put_action_manifest(&key, b"{}", None).await.is_err());

    assert!(store.conditionals_enabled());
}

#[tokio::test]
async fn a_store_that_dislikes_a_request_is_not_mistaken_for_one_without_conditionals() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    server
        .mock("PUT", manifest_path(&key).as_str())
        .with_status(400)
        .with_body(s3_error_body("InvalidRequest"))
        .create_async()
        .await;
    let store = test_store(&server);

    let error = store
        .put_action_manifest(&key, b"{}", None)
        .await
        .unwrap_err();

    assert!(error.to_string().contains("InvalidRequest"));
    assert!(store.conditionals_enabled());
}

#[tokio::test]
async fn requiring_conditional_writes_refuses_a_store_without_them() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"a task");
    server
        .mock("PUT", manifest_path(&key).as_str())
        .with_status(501)
        .with_body(s3_error_body("NotImplemented"))
        .create_async()
        .await;
    let mut settings = config(&server);
    settings.conditional_writes = S3ConditionalWrites::Required;

    let error = S3RemoteCache::new(settings)
        .unwrap()
        .put_action_manifest(&key, b"{}", None)
        .await
        .unwrap_err();

    assert!(
        error
            .to_string()
            .contains("conditional writes are required")
    );
}

#[tokio::test]
async fn a_reachable_bucket_passes_the_connection_probe() {
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(404)
        .expect(1)
        .create_async()
        .await;

    // A bucket that answers at all has proved the endpoint, the credentials,
    // and its own existence. Whether this key is present says nothing.
    test_store(&server).check_connection().await.unwrap();

    request.assert_async().await;
}

#[tokio::test]
async fn rejected_credentials_are_named_in_the_connection_probe() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(403)
        .with_body(s3_error_body("SignatureDoesNotMatch"))
        .create_async()
        .await;

    let error = test_store(&server).check_connection().await.unwrap_err();

    assert!(error.to_string().contains("AWS_ACCESS_KEY_ID"));
}

#[tokio::test]
async fn a_least_privilege_policy_still_passes_the_connection_probe() {
    let mut server = mockito::Server::new_async().await;
    // Without s3:ListBucket, S3 refuses a read of an absent object rather than
    // reporting it absent -- and the probe key is never written. A working
    // configuration must not be reported as broken credentials.
    server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(403)
        .with_body(s3_error_body("AccessDenied"))
        .create_async()
        .await;

    test_store(&server).check_connection().await.unwrap();
}

#[tokio::test]
async fn a_refused_read_is_a_miss_rather_than_a_failed_build() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"an action");
    let path = format!(
        "/cache-bucket/acme/v1/action-results/blake3/{}/{}",
        action.hash, action.size
    );
    server
        .mock("GET", path.as_str())
        .with_status(403)
        .with_body(s3_error_body("AccessDenied"))
        .create_async()
        .await;

    // Every cold lookup under a least-privilege policy arrives this way, so
    // reporting them as errors would make such a policy unusable.
    assert!(
        test_store(&server)
            .get_action_result(&action)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn credentials_s3_itself_rejected_are_not_mistaken_for_a_miss() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"an action");
    let path = format!(
        "/cache-bucket/acme/v1/action-results/blake3/{}/{}",
        action.hash, action.size
    );
    server
        .mock("GET", path.as_str())
        .with_status(403)
        .with_body(s3_error_body("InvalidAccessKeyId"))
        .create_async()
        .await;

    // A request that never authenticated says nothing about the object, and
    // swallowing it would leave a permanently cold cache with no explanation.
    let error = test_store(&server)
        .get_action_result(&action)
        .await
        .unwrap_err();

    assert!(error.to_string().contains("InvalidAccessKeyId"));
}

#[tokio::test]
async fn a_bucket_in_another_region_says_which_one() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(301)
        .with_header("x-amz-bucket-region", "eu-west-1")
        .create_async()
        .await;

    let error = test_store(&server).check_connection().await.unwrap_err();

    assert!(error.to_string().contains("eu-west-1"));
}

#[tokio::test]
async fn temporary_credentials_send_their_session_token() {
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("x-amz-security-token", "session-token")
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let mut settings = config(&server);
    settings.credentials.session_token = Some("session-token".into());

    S3RemoteCache::new(settings)
        .unwrap()
        .check_connection()
        .await
        .unwrap();

    request.assert_async().await;
}

#[tokio::test]
async fn extensions_a_bucket_cannot_serve_report_themselves_absent() {
    let server = mockito::Server::new_async().await;
    let store = test_store(&server);
    let digest = CacheDigest::blake3(b"anything");
    let staging = tempfile::tempdir().unwrap();

    // Reporting absence is what routes the agent and the upload queue to the
    // per-object requests every version of the protocol has made.
    assert!(store.action_batch_limit().await.unwrap().is_none());
    assert!(store.blob_pack_upload_limits().await.unwrap().is_none());
    assert!(
        store
            .get_action_results(std::slice::from_ref(&digest))
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        store
            .get_blob_pack(std::slice::from_ref(&digest), staging.path())
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        store
            .put_blob_pack(&[BlobUpload {
                digest,
                source: BlobSource::Bytes(Vec::new()),
            }])
            .await
            .unwrap()
            .is_none()
    );

    // An empty request is answered rather than declined, matching the protocol
    // client, so a caller with nothing to do does not fall back for no reason.
    assert_eq!(
        store.get_action_results(&[]).await.unwrap(),
        Some(Vec::new())
    );
    assert!(store.put_blob_pack(&[]).await.unwrap().is_some());
}

#[test]
fn buckets_are_addressed_by_host_on_aws_and_by_path_elsewhere() {
    let addressed = |bucket: &str, endpoint: Option<&str>, force: Option<bool>| {
        base_url(&S3RemoteCacheConfig {
            bucket: bucket.into(),
            endpoint: endpoint.map(|endpoint| endpoint.parse().unwrap()),
            force_path_style: force,
            ..S3RemoteCacheConfig {
                bucket: bucket.into(),
                prefix: String::new(),
                namespace: "acme".into(),
                region: "us-west-2".into(),
                endpoint: None,
                force_path_style: None,
                conditional_writes: S3ConditionalWrites::Auto,
                credentials: credentials(),
                connect_timeout: Duration::from_secs(1),
                read_timeout: Duration::from_secs(1),
                download_timeout: Duration::from_secs(1),
                retries: 0,
            }
        })
        .unwrap()
        .to_string()
    };

    assert_eq!(
        addressed("cache", None, None),
        "https://cache.s3.us-west-2.amazonaws.com/"
    );
    // A dot in the name is not covered by the wildcard certificate that makes
    // host addressing work, so such a bucket is addressed by path.
    assert_eq!(
        addressed("cache.example.com", None, None),
        "https://s3.us-west-2.amazonaws.com/cache.example.com/"
    );
    assert_eq!(
        addressed("cache", None, Some(true)),
        "https://s3.us-west-2.amazonaws.com/cache/"
    );
    assert_eq!(
        addressed("cache", Some("http://127.0.0.1:9000"), None),
        "http://127.0.0.1:9000/cache/"
    );
    assert_eq!(
        addressed(
            "cache",
            Some("https://account.r2.cloudflarestorage.com"),
            None
        ),
        "https://account.r2.cloudflarestorage.com/cache/"
    );
    assert_eq!(
        addressed("cache", Some("https://store.example.com"), Some(false)),
        "https://cache.store.example.com/"
    );
    // An endpoint's own path survives being addressed by host.
    assert_eq!(
        addressed("cache", Some("https://gateway.example.com/s3"), Some(false)),
        "https://cache.gateway.example.com/s3/"
    );
    assert_eq!(
        addressed("cache", Some("https://gateway.example.com/s3"), None),
        "https://gateway.example.com/s3/cache/"
    );
}

#[test]
fn keys_are_laid_out_under_the_prefix_namespace_and_layout_version() {
    let server = mockito::Server::new();
    let mut settings = config(&server);
    settings.prefix = "/teams/backend/".into();
    let store = S3RemoteCache::new(settings).unwrap();
    let digest = CacheDigest {
        algorithm: "blake3".into(),
        hash: "a".repeat(64),
        size: 7,
    };

    assert!(
        store
            .object_url(ObjectKind::Blob, &digest)
            .unwrap()
            .path()
            .ends_with(&format!(
                "/cache-bucket/teams/backend/acme/v1/blobs/blake3/{}/7",
                digest.hash
            ))
    );
}

#[test]
fn a_namespace_that_could_escape_its_prefix_is_refused() {
    let server = mockito::Server::new();
    let refused = |namespace: &str| {
        let mut settings = config(&server);
        settings.namespace = namespace.into();
        match S3RemoteCache::new(settings) {
            Err(error) => error.to_string(),
            Ok(_) => panic!("namespace {namespace:?} should have been refused"),
        }
    };

    // The protocol carries the namespace in a header a server interprets. In a
    // bucket it is part of the key, so it has to stay inside its own prefix.
    assert!(refused("../other").contains("relative path segment"));
    assert!(refused("acme//backend").contains("empty path segment"));
    assert!(refused("/acme").contains("must not start or end with a slash"));
    assert!(refused("").contains("must not be empty"));
    assert!(refused("acme backend").contains("must use only letters"));
    // A namespace naming more than one level is ordinary and stays allowed.
    let mut settings = config(&server);
    settings.namespace = "acme/backend".into();
    assert!(S3RemoteCache::new(settings).map(drop).is_ok());
}

#[test]
fn error_codes_are_read_out_of_an_s3_error_document() {
    assert_eq!(error_code(&s3_error_body("NoSuchKey")), Some("NoSuchKey"));
    assert_eq!(error_code("not xml at all"), None);
    assert_eq!(error_code("<Error><Code></Code></Error>"), None);
    // A code at the very end of the document is still found: nothing may trim
    // the tail off a body before scanning it.
    assert_eq!(
        error_code("<Code>AccessDenied</Code>"),
        Some("AccessDenied")
    );
    assert_eq!(error_code(&"é".repeat(16 * 1024)), None);
}

/// The bucket backend reads `download_timeout` exactly as the protocol backend
/// does: a deadline for the whole download, not a budget each attempt gets
/// afresh. A `503` is what a store sends for a prefix under load and is
/// retryable, so four retries would otherwise sleep at least
/// 100ms + 500ms + 2s + 7.5s; returning well inside that shows the deadline cut
/// the retry loop short instead of restarting with every attempt.
#[tokio::test]
async fn blob_download_timeout_spans_retries_rather_than_one_attempt() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"retried blob");
    let request = server
        .mock("GET", blob_path(&digest).as_str())
        .with_status(503)
        .with_body(s3_error_body("SlowDown"))
        .expect_at_least(1)
        .create_async()
        .await;
    let store = test_store_with(&server, Duration::from_millis(200), 4);
    let staging = tempfile::tempdir().unwrap();

    let started = Instant::now();
    let error = store
        .get_blob_file(&digest, staging.path())
        .await
        .err()
        .unwrap();
    let elapsed = started.elapsed();

    assert!(
        error
            .to_string()
            .contains("exceeded its 200ms budget across all attempts"),
        "{error}"
    );
    assert!(elapsed < Duration::from_secs(5), "took {elapsed:?}");
    request.assert_async().await;
}

/// The control for the test above: the same store, given a budget large enough
/// to cover the whole retry loop, spends every retry and fails with the store's
/// own error rather than a timeout.
#[tokio::test]
async fn transient_failures_exhaust_retries_within_a_generous_deadline() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"retried blob");
    let request = server
        .mock("GET", blob_path(&digest).as_str())
        .with_status(503)
        .with_body(s3_error_body("SlowDown"))
        .expect(2)
        .create_async()
        .await;
    let store = test_store_with(&server, Duration::from_secs(30), 1);
    let staging = tempfile::tempdir().unwrap();

    let error = store
        .get_blob_file(&digest, staging.path())
        .await
        .err()
        .unwrap();

    assert!(!error.to_string().contains("budget"), "{error}");
    request.assert_async().await;
}

/// A metadata service double whose role credentials stay valid for centuries.
/// The second value is the credentials lookup, which should happen once.
async fn metadata_service() -> (mockito::ServerGuard, mockito::Mock) {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("PUT", "/latest/api/token")
        .with_body("session-token")
        .create_async()
        .await;
    server
        .mock("GET", "/latest/meta-data/iam/security-credentials/")
        .with_body("build-runner")
        .create_async()
        .await;
    let lookup = server
        .mock(
            "GET",
            "/latest/meta-data/iam/security-credentials/build-runner",
        )
        .with_body(
            r#"{"Code":"Success","AccessKeyId":"ASIARENEWED","SecretAccessKey":"renewed-secret","Token":"renewed-token","Expiration":"2999-01-01T00:00:00Z"}"#,
        )
        .expect(1)
        .create_async()
        .await;
    (server, lookup)
}

fn signed_with(access_key_id: &str) -> mockito::Matcher {
    mockito::Matcher::Regex(format!("Credential={access_key_id}/"))
}

/// The instance role credentials the store currently signs with.
async fn signing_key(store: &S3RemoteCache) -> String {
    store.credentials.current().await.access_key_id
}

/// Wait for something a background renewal does, which no request waits for.
async fn eventually(mut done: impl AsyncFnMut() -> bool) {
    for _ in 0..200 {
        if done().await {
            return;
        }
        tokio::time::sleep(Duration::from_millis(25)).await;
    }
    panic!("the background renewal did not finish");
}

#[tokio::test]
async fn lapsed_instance_role_credentials_are_renewed_before_signing() {
    let (metadata, lookup) = metadata_service().await;
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("authorization", signed_with("ASIARENEWED"))
        .match_header("x-amz-security-token", "renewed-token")
        .with_status(200)
        .expect(2)
        .create_async()
        .await;
    // Already expired: nothing valid is left to sign with, so the first
    // request waits for the renewal.
    let expires_at = SystemTime::now() - Duration::from_secs(1);
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
        expires_at,
    );

    store.check_connection().await.unwrap();
    // The renewed credentials are good for far longer, so no second lookup.
    store.check_connection().await.unwrap();

    request.assert_async().await;
    lookup.assert_async().await;
}

#[tokio::test]
async fn credentials_inside_the_renewal_margin_are_renewed_in_the_background() {
    let (metadata, lookup) = metadata_service().await;
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("authorization", signed_with("AKIDEXAMPLE"))
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
        SystemTime::now() + Duration::from_secs(60),
    );

    // Still valid, so this request signs with what is held.
    store.check_connection().await.unwrap();
    request.assert_async().await;

    eventually(async || lookup.matched_async().await).await;
    eventually(async || signing_key(&store).await == "ASIARENEWED").await;
}

#[tokio::test]
async fn a_metadata_service_that_hangs_does_not_stall_requests() {
    // Accepts connections and never answers.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let held = tokio::spawn(async move {
        let mut connections = Vec::new();
        while let Ok((connection, _)) = listener.accept().await {
            connections.push(connection);
        }
    });
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("authorization", signed_with("AKIDEXAMPLE"))
        .with_status(200)
        .expect(3)
        .create_async()
        .await;
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(format!("http://{address}").parse().unwrap()).unwrap(),
        SystemTime::now() + Duration::from_secs(60),
    );

    let started = Instant::now();
    for _ in 0..3 {
        store.check_connection().await.unwrap();
    }
    held.abort();

    // A lookup takes seconds to give up on a service like this one.
    assert!(started.elapsed() < Duration::from_millis(900));
    request.assert_async().await;
}

#[tokio::test]
async fn credentials_with_time_left_are_not_renewed() {
    let mut metadata = mockito::Server::new_async().await;
    let lookup = metadata
        .mock("PUT", "/latest/api/token")
        .expect(0)
        .create_async()
        .await;
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("authorization", signed_with("AKIDEXAMPLE"))
        .with_status(200)
        .expect(1)
        .create_async()
        .await;
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
        SystemTime::now() + Duration::from_secs(3_600),
    );

    store.check_connection().await.unwrap();

    request.assert_async().await;
    lookup.assert_async().await;
}

#[tokio::test]
async fn a_failed_renewal_keeps_the_current_credentials_and_backs_off() {
    let mut metadata = mockito::Server::new_async().await;
    // The lookup itself retries a failing service before giving up.
    let lookup = metadata
        .mock("PUT", "/latest/api/token")
        .with_status(500)
        .expect(3)
        .create_async()
        .await;
    let mut server = mockito::Server::new_async().await;
    let request = server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .match_header("authorization", signed_with("AKIDEXAMPLE"))
        .with_status(200)
        .expect(4)
        .create_async()
        .await;
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
        SystemTime::now() + Duration::from_secs(60),
    );

    for _ in 0..3 {
        store.check_connection().await.unwrap();
    }
    eventually(async || lookup.matched_async().await).await;
    // Once the failed renewal is over, the service is left alone for a while.
    eventually(async || {
        let CredentialSource::InstanceRole(role) = &store.credentials else {
            unreachable!()
        };
        role.state.lock().unwrap().retry_at.is_some()
    })
    .await;
    store.check_connection().await.unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;

    request.assert_async().await;
    lookup.assert_async().await;
}

#[tokio::test]
async fn rejected_credentials_name_where_they_came_from() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(403)
        .with_body(s3_error_body("InvalidAccessKeyId"))
        .create_async()
        .await;

    let from_environment = test_store(&server)
        .check_connection()
        .await
        .unwrap_err()
        .to_string();
    assert!(
        from_environment.contains("AWS_ACCESS_KEY_ID"),
        "{from_environment}"
    );

    let (metadata, _) = metadata_service().await;
    let from_role = test_store(&server)
        .with_instance_role(
            InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
            SystemTime::now() + Duration::from_secs(3_600),
        )
        .check_connection()
        .await
        .unwrap_err()
        .to_string();
    assert!(from_role.contains("instance role"), "{from_role}");
    assert!(!from_role.contains("AWS_ACCESS_KEY_ID"), "{from_role}");
}

#[tokio::test]
async fn bad_request_token_errors_are_rejected_with_environment_hint() {
    for code in ["ExpiredToken", "TokenRefreshRequired", "InvalidToken"] {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
            .with_status(400)
            .with_body(s3_error_body(code))
            .create_async()
            .await;
        let error = test_store(&server)
            .check_connection()
            .await
            .unwrap_err()
            .to_string();
        assert!(error.contains(code), "{code}: {error}");
        assert!(error.contains("AWS_ACCESS_KEY_ID"), "{code}: {error}");
    }
}

#[tokio::test]
async fn unrelated_bad_request_fails_the_connection_probe_without_a_credential_hint() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
        .with_status(400)
        .with_body(s3_error_body("InvalidRequest"))
        .create_async()
        .await;

    let error = test_store(&server)
        .check_connection()
        .await
        .unwrap_err()
        .to_string();

    assert!(error.contains("failed to connect to"), "{error}");
    assert!(error.contains("400"), "{error}");
    assert!(error.contains("InvalidRequest"), "{error}");
    assert!(!error.contains("rejected these credentials"), "{error}");
    assert!(!error.contains("AWS_ACCESS_KEY_ID"), "{error}");
}

#[tokio::test]
async fn expired_role_credentials_name_renewal_and_clocks_not_permissions() {
    for status in [400, 403] {
        let mut server = mockito::Server::new_async().await;
        server
            .mock("GET", "/cache-bucket/acme/v1/connectivity-probe")
            .with_status(status)
            .with_body(s3_error_body("ExpiredToken"))
            .create_async()
            .await;
        let (metadata, _) = metadata_service().await;
        let store = test_store(&server).with_instance_role(
            InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
            SystemTime::now() + Duration::from_secs(3_600),
        );

        let error = store.check_connection().await.unwrap_err().to_string();

        // The message must not depend on the credentials held now, which a
        // renewal may have replaced since the rejected request was signed.
        assert!(error.contains("renewal warning"), "{status}: {error}");
        assert!(error.contains("clocks"), "{status}: {error}");
        assert!(!error.contains("permissions"), "{status}: {error}");
    }
}

#[tokio::test]
async fn renewal_resumes_once_the_backoff_ends() {
    let mut metadata = mockito::Server::new_async().await;
    let failing = metadata
        .mock("PUT", "/latest/api/token")
        .with_status(500)
        .expect(3)
        .create_async()
        .await;
    metadata
        .mock("PUT", "/latest/api/token")
        .with_body("session-token")
        .create_async()
        .await;
    metadata
        .mock("GET", "/latest/meta-data/iam/security-credentials/")
        .with_body("build-runner")
        .create_async()
        .await;
    metadata
        .mock(
            "GET",
            "/latest/meta-data/iam/security-credentials/build-runner",
        )
        .with_body(
            r#"{"Code":"Success","AccessKeyId":"ASIARENEWED","SecretAccessKey":"renewed-secret","Token":"renewed-token","Expiration":"2999-01-01T00:00:00Z"}"#,
        )
        .create_async()
        .await;
    let server = mockito::Server::new_async().await;
    let store = test_store(&server).with_instance_role(
        InstanceRoleCredentials::new(metadata.url().parse().unwrap()).unwrap(),
        SystemTime::now() + Duration::from_secs(60),
    );
    let CredentialSource::InstanceRole(role) = &store.credentials else {
        unreachable!()
    };

    // The first renewal fails and starts the backoff.
    assert_eq!(signing_key(&store).await, "AKIDEXAMPLE");
    eventually(async || failing.matched_async().await).await;
    eventually(async || {
        !role.renewing.load(Ordering::Acquire) && role.state.lock().unwrap().retry_at.is_some()
    })
    .await;
    // During the backoff nothing is asked, so the failed set is still held.
    assert_eq!(signing_key(&store).await, "AKIDEXAMPLE");
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert_eq!(signing_key(&store).await, "AKIDEXAMPLE");

    // Once the backoff has passed, the next request renews again.
    role.state.lock().unwrap().retry_at = Some(Instant::now());
    signing_key(&store).await;
    eventually(async || signing_key(&store).await == "ASIARENEWED").await;
}
