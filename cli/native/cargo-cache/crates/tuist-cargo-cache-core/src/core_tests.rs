use super::*;
use crate::*;

#[test]
fn protocol_json_uses_jcs_key_and_number_encoding() {
    let value = serde_json::json!({"z": 1.0e30, "a": {"d": true, "c": null}});
    assert_eq!(
        canonical_json(&value).unwrap(),
        br#"{"a":{"c":null,"d":true},"z":1e+30}"#
    );
}

#[test]
fn dns_errors_are_not_transient() {
    #[derive(Debug)]
    struct DnsError;

    impl std::fmt::Display for DnsError {
        fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter.write_str("dns error")
        }
    }

    impl std::error::Error for DnsError {}

    let error = eyre::Report::new(DnsError);
    assert!(is_dns_error(error.as_ref()));
    assert!(!is_transient(&error));
}

#[test]
fn cache_digest_verifies_its_declared_algorithm() {
    let bytes = b"remote cache blob";
    let sha256 = CacheDigest {
        algorithm: "sha256".into(),
        hash: hex::encode(sha2::Sha256::digest(bytes)),
        size: bytes.len() as u64,
    };
    assert!(sha256.matches_bytes(bytes).unwrap());
    assert!(!sha256.matches_bytes(b"different").unwrap());

    let file = tempfile::NamedTempFile::new().unwrap();
    fs::write(file.path(), bytes).unwrap();
    assert!(sha256.matches_file(file.path()).unwrap());
    assert_eq!(
        CacheDigest::blake3_file(file.path()).unwrap().size,
        bytes.len() as u64
    );
    assert!(
        CacheDigest::blake3_file(file.path())
            .unwrap()
            .matches_bytes(bytes)
            .unwrap()
    );
}

#[test]
fn action_result_keys_require_blake3() {
    let client = HttpRemoteCache::new(RemoteCacheConfig {
        base_url: "http://127.0.0.1:1".parse().unwrap(),
        namespace: "test".into(),
        token: None,
        token_file: None,
        oidc_audience: None,
        connect_timeout: Duration::from_secs(1),
        read_timeout: Duration::from_secs(1),
        download_timeout: Duration::from_secs(1),
        retries: 0,
    })
    .unwrap();
    let action = CacheDigest {
        algorithm: "sha256".into(),
        hash: "0".repeat(64),
        size: 0,
    };

    assert!(
        client
            .action_result_endpoint(&action)
            .unwrap_err()
            .to_string()
            .contains("must use blake3")
    );
}

#[tokio::test]
async fn action_upload_is_idempotent_when_result_already_exists() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"existing action");
    let endpoint = format!("/v1/action-results/blake3/{}/{}", action.hash, action.size);
    let upload = server
        .mock("PUT", endpoint.as_str())
        .match_header("if-none-match", "*")
        .with_status(409)
        .with_body(r#"{"error":"an immutable action result already exists"}"#)
        .expect(1)
        .create_async()
        .await;
    let result = RemoteActionResult {
        action,
        metadata: None,
        output_root: None,
        version: 1,
    };

    test_client(&server)
        .put_action_result(&result)
        .await
        .unwrap();

    upload.assert_async().await;
}

#[tokio::test]
async fn action_upload_errors_include_a_bounded_server_response() {
    let mut server = mockito::Server::new_async().await;
    let action = CacheDigest::blake3(b"rejected action");
    let endpoint = format!("/v1/action-results/blake3/{}/{}", action.hash, action.size);
    let mut response = "invalid rustc action: unexpected field `linker`".to_string();
    response.push_str(&"x".repeat(MAX_REMOTE_ERROR_BYTES));
    response.push_str("unbounded-tail");
    let upload = server
        .mock("PUT", endpoint.as_str())
        .with_status(422)
        .with_body(response)
        .create_async()
        .await;
    let result = RemoteActionResult {
        action,
        metadata: None,
        output_root: None,
        version: 1,
    };

    let error = test_client(&server)
        .put_action_result(&result)
        .await
        .unwrap_err()
        .to_string();

    assert!(error.contains("422 Unprocessable Entity"), "{error}");
    assert!(error.contains("unexpected field `linker`"), "{error}");
    assert!(error.contains("(truncated)"), "{error}");
    assert!(!error.contains("unbounded-tail"), "{error}");
    upload.assert_async().await;
}

#[tokio::test]
async fn joins_an_advertised_action_promise() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "action_promises": true })).await;
    let invocation = CacheDigest::blake3(b"rustc invocation");
    let endpoint = format!(
        "/v1/action-promises/blake3/{}/{}",
        invocation.hash, invocation.size
    );
    let join = server
        .mock("POST", endpoint.as_str())
        .match_header(PROTOCOL_HEADER, "1")
        .match_header(NAMESPACE_HEADER, "test")
        .match_header("content-type", ACTION_PROMISE_MEDIA_TYPE)
        .match_body(mockito::Matcher::Json(
            serde_json::json!({"adapter":"rustc"}),
        ))
        .with_status(200)
        .with_header("content-type", ACTION_PROMISE_MEDIA_TYPE)
        .with_body(r#"{"state":"claimed","claim":"lease-1"}"#)
        .create_async()
        .await;

    assert_eq!(
        test_client(&server)
            .join_action_promise(&invocation, "rustc")
            .await
            .unwrap(),
        Some(ActionPromiseState::Claimed {
            claim: "lease-1".into()
        })
    );
    join.assert_async().await;
}

#[tokio::test]
async fn completes_an_action_promise_with_a_bound_prediction() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "action_promises": true })).await;
    let invocation = CacheDigest::blake3(b"cc invocation");
    let prediction = ActionPrediction {
        invocation: invocation.clone(),
        action: CacheDigest::blake3(b"cc action"),
        adapter: "cc".into(),
        payload: "{}".into(),
    };
    let completion = ActionPromiseCompletion {
        claim: "lease-2".into(),
        prediction: prediction.clone(),
    };
    let endpoint = format!(
        "/v1/action-promises/blake3/{}/{}",
        invocation.hash, invocation.size
    );
    let complete = server
        .mock("PUT", endpoint.as_str())
        .match_header("content-type", ACTION_PROMISE_MEDIA_TYPE)
        .match_body(mockito::Matcher::Json(
            serde_json::to_value(&completion).unwrap(),
        ))
        .with_status(204)
        .create_async()
        .await;

    assert!(
        test_client(&server)
            .complete_action_promise(&invocation, &completion)
            .await
            .unwrap()
    );
    complete.assert_async().await;
}

#[tokio::test]
async fn does_not_probe_action_promises_without_the_capability() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({})).await;
    let invocation = CacheDigest::blake3(b"uncoordinated invocation");
    assert_eq!(
        test_client(&server)
            .join_action_promise(&invocation, "rustc")
            .await
            .unwrap(),
        None
    );
}

#[tokio::test]
async fn downloads_negotiated_blob_packs_and_omits_missing_objects() {
    let mut server = mockito::Server::new_async().await;
    let first_bytes = b"first packed blob";
    let second_bytes = b"second packed blob";
    let first = CacheDigest::blake3(first_bytes);
    let second = CacheDigest::blake3(second_bytes);
    let missing = CacheDigest::blake3(b"missing packed blob");
    let capabilities = server
        .mock("GET", "/v1/capabilities")
        .match_header(PROTOCOL_HEADER, "1")
        .match_header(AUTHORIZATION.as_str(), "Bearer test-token")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_packs":true},
                "limits":{"max_batch_items":100,"max_pack_bytes":1024}
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;
    let packed = encode_blob_pack(&[
        (&first, first_bytes.as_slice()),
        (&second, second_bytes.as_slice()),
    ]);
    let packed_len = packed.len().to_string();
    let packed_blobs = 2.to_string();
    let packed_payload_bytes = (first.size + second.size).to_string();
    let request = server
        .mock("POST", "/v1/blobs:pack")
        .match_header(PROTOCOL_HEADER, "1")
        .match_header(NAMESPACE_HEADER, "test")
        .match_header("content-type", DIGEST_LIST_MEDIA_TYPE)
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_header("content-length", &packed_len)
        .with_header(BLOB_PACK_BLOBS_HEADER, &packed_blobs)
        .with_header(BLOB_PACK_BYTES_HEADER, &packed_payload_bytes)
        .with_body(packed)
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let pack = client
        .get_blob_pack(
            &[first.clone(), missing, second.clone(), first.clone()],
            staging.path(),
        )
        .await
        .unwrap()
        .unwrap();

    assert_eq!(pack.requests, 1);
    assert_eq!(pack.blob_count, 2);
    assert_eq!(pack.payload_bytes, first.size + second.size);
    assert_eq!(
        pack.framed_bytes,
        BLOB_PACK_MAGIC.len() as u64 + 2 * BLOB_PACK_HEADER_BYTES + first.size + second.size
    );
    assert_eq!(pack.blobs.len(), 2);
    assert_eq!(fs::read(&pack.blobs[0].1).unwrap(), first_bytes);
    assert_eq!(fs::read(&pack.blobs[1].1).unwrap(), second_bytes);
    capabilities.assert_async().await;
    request.assert_async().await;
}

#[tokio::test]
async fn rejects_mismatched_blob_pack_metadata() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"packed blob";
    let digest = CacheDigest::blake3(contents);
    mock_blob_pack_capabilities(&mut server).await;
    server
        .mock("POST", "/v1/blobs:pack")
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_header(BLOB_PACK_BLOBS_HEADER, "2")
        .with_body(encode_blob_pack(&[(&digest, contents.as_slice())]))
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let error = client
        .get_blob_pack(&[digest], staging.path())
        .await
        .err()
        .unwrap();

    assert!(error.to_string().contains("blob count metadata mismatch"));
}

#[tokio::test]
async fn rejects_malformed_blob_pack_metadata() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"packed blob";
    let digest = CacheDigest::blake3(contents);
    mock_blob_pack_capabilities(&mut server).await;
    server
        .mock("POST", "/v1/blobs:pack")
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_header(BLOB_PACK_BYTES_HEADER, "not-a-number")
        .with_body(encode_blob_pack(&[(&digest, contents.as_slice())]))
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let error = client
        .get_blob_pack(&[digest], staging.path())
        .await
        .err()
        .unwrap();

    assert!(error.to_string().contains("not an unsigned integer"));
}

#[tokio::test]
async fn rejects_unrequested_blob_pack_frames() {
    let mut server = mockito::Server::new_async().await;
    let requested = CacheDigest::blake3(b"requested");
    let injected_bytes = b"not requested";
    let injected = CacheDigest::blake3(injected_bytes);
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_packs":true},
                "limits":{"max_batch_items":100,"max_pack_bytes":1024}
            })
            .to_string(),
        )
        .create_async()
        .await;
    server
        .mock("POST", "/v1/blobs:pack")
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_body(encode_blob_pack(&[(&injected, injected_bytes.as_slice())]))
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let error = client
        .get_blob_pack(&[requested], staging.path())
        .await
        .err()
        .unwrap();

    assert!(error.to_string().contains("unrequested digest"));
}

#[tokio::test]
async fn falls_back_when_blob_packs_are_not_advertised() {
    let mut server = mockito::Server::new_async().await;
    let capabilities = server
        .mock("GET", "/v1/capabilities")
        .with_status(404)
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    assert!(
        client
            .get_blob_pack(&[CacheDigest::blake3(b"blob")], staging.path())
            .await
            .unwrap()
            .is_none()
    );
    capabilities.assert_async().await;
}

#[tokio::test]
async fn connection_check_requires_a_capabilities_endpoint() {
    let mut server = mockito::Server::new_async().await;
    let capabilities = server
        .mock("GET", "/v1/capabilities")
        .with_status(404)
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let error = client.check_connection().await.unwrap_err();

    assert!(error.to_string().contains("404"));
    capabilities.assert_async().await;
}

#[tokio::test]
async fn disables_blob_packs_when_the_advertised_endpoint_is_unavailable() {
    let mut server = mockito::Server::new_async().await;
    let capabilities = server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_packs":true},
                "limits":{"max_batch_items":100,"max_pack_bytes":1024}
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;
    let request = server
        .mock("POST", "/v1/blobs:pack")
        .with_status(404)
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();
    let digest = CacheDigest::blake3(b"blob");

    assert!(
        client
            .get_blob_pack(std::slice::from_ref(&digest), staging.path())
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        client
            .get_blob_pack(&[digest], staging.path())
            .await
            .unwrap()
            .is_none()
    );
    capabilities.assert_async().await;
    request.assert_async().await;
}

#[tokio::test]
async fn stops_reading_once_failed_reads_exhaust_the_stall_budget() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"unreachable blob");
    // `expect(1)` is the assertion: the second read must not reach the server.
    // Without a stall budget every object pays the download deadline again, so
    // an unhealthy remote can outlast the build it is meant to accelerate.
    let request = server
        .mock(
            "GET",
            format!("/v1/blobs/blake3/{}/{}", digest.hash, digest.size).as_str(),
        )
        .with_status(503)
        .expect(1)
        .create_async()
        .await;
    let client = test_client_with_stall_budget(
        &server,
        Duration::from_millis(50),
        0,
        Duration::from_nanos(1),
    );
    let staging = tempfile::tempdir().unwrap();

    let _ = client
        .get_blob_file(&digest, staging.path())
        .await
        .expect_err("the first read fails against a 503");

    let error = client
        .get_blob_file(&digest, staging.path())
        .await
        .expect_err("the second read is abandoned rather than attempted");
    assert!(
        error.to_string().contains("reads were abandoned"),
        "{error}"
    );
    // Packs degrade to "unsupported", which callers already treat as a miss.
    assert!(
        client
            .get_blob_pack(&[digest], staging.path())
            .await
            .unwrap()
            .is_none()
    );
    request.assert_async().await;
}

#[tokio::test]
async fn a_zero_stall_budget_keeps_reading() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"still tried");
    let request = server
        .mock(
            "GET",
            format!("/v1/blobs/blake3/{}/{}", digest.hash, digest.size).as_str(),
        )
        .with_status(503)
        .expect(2)
        .create_async()
        .await;
    let client = test_client_with(&server, Duration::from_millis(50), 0);
    let staging = tempfile::tempdir().unwrap();

    for _ in 0..2 {
        let _ = client
            .get_blob_file(&digest, staging.path())
            .await
            .expect_err("every read fails against a 503");
    }

    request.assert_async().await;
}

#[tokio::test]
async fn rejects_truncated_blob_pack_frames() {
    let mut server = mockito::Server::new_async().await;
    let contents = b"complete blob";
    let digest = CacheDigest::blake3(contents);
    let mut pack = encode_blob_pack(&[(&digest, contents.as_slice())]);
    pack.truncate(pack.len() - 3);
    mock_blob_pack_capabilities(&mut server).await;
    server
        .mock("POST", "/v1/blobs:pack")
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_body(pack)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let error = match client.get_blob_pack(&[digest], staging.path()).await {
        Err(error) => error,
        Ok(_) => panic!("truncated pack should be rejected"),
    };

    assert!(
        error
            .to_string()
            .contains("ended before a blob was complete")
    );
}

#[tokio::test]
async fn rejects_blob_pack_frames_with_corrupt_content() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"expected");
    let corrupt = b"corrupt!";
    let pack = encode_blob_pack(&[(&digest, corrupt.as_slice())]);
    mock_blob_pack_capabilities(&mut server).await;
    server
        .mock("POST", "/v1/blobs:pack")
        .with_status(200)
        .with_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .with_body(pack)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let error = match client.get_blob_pack(&[digest], staging.path()).await {
        Err(error) => error,
        Ok(_) => panic!("corrupt pack should be rejected"),
    };

    assert!(error.to_string().contains("failed digest verification"));
}

#[test]
fn blob_pack_chunk_honors_item_and_byte_limits() {
    let first = CacheDigest::blake3(b"1234");
    let second = CacheDigest::blake3(b"5678");
    let oversized = CacheDigest::blake3(b"123456789");
    let chunk = blob_pack_chunk(
        &[first.clone(), second.clone(), first.clone(), oversized],
        BlobPackLimits {
            max_items: 10,
            max_bytes: 7,
        },
    )
    .unwrap();

    assert_eq!(chunk, vec![first]);

    let chunk = blob_pack_chunk(
        &[CacheDigest::blake3(b"a"), CacheDigest::blake3(b"b")],
        BlobPackLimits {
            max_items: 1,
            max_bytes: 100,
        },
    )
    .unwrap();
    assert_eq!(chunk.len(), 1);
}

#[test]
fn blob_pack_timeout_scales_with_declared_work() {
    let base = Duration::from_secs(10);
    let small = CacheDigest::blake3(b"small");
    assert_eq!(blob_pack_download_timeout(base, &[small]), base);

    let large = CacheDigest {
        algorithm: "blake3".into(),
        hash: "0".repeat(64),
        size: MAX_STAGED_BLOB_PACK_BYTES,
    };
    assert_eq!(
        blob_pack_download_timeout(base, &[large]),
        base.saturating_mul(4)
    );

    let many = (0..=BLOB_PACK_TIMEOUT_ITEMS_PER_UNIT)
        .map(|index| CacheDigest::blake3(index.to_string().as_bytes()))
        .collect::<Vec<_>>();
    assert_eq!(
        blob_pack_download_timeout(base, &many),
        base.saturating_mul(2)
    );
}

#[test]
fn bearer_authorization_headers_are_sensitive() {
    let header = authorization_header(Some(" test-token ")).unwrap().unwrap();
    assert_eq!(header, "Bearer test-token");
    assert!(header.is_sensitive());
    assert!(authorization_header(Some(" ")).unwrap().is_none());
}

#[tokio::test]
async fn rejects_blob_larger_than_its_digest() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"small");
    let endpoint = format!(
        "/v{PROTOCOL_VERSION}/blobs/{}/{}/{}",
        digest.algorithm, digest.hash, digest.size
    );
    server
        .mock("GET", endpoint.as_str())
        .with_status(200)
        .with_header("content-type", BLOB_MEDIA_TYPE)
        .with_body(vec![b'x'; 4096])
        .expect(2)
        .create_async()
        .await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();

    let buffered = client
        .get_blob(&digest, BLOB_MEDIA_TYPE)
        .await
        .err()
        .unwrap();
    let streamed = client
        .get_blob_file(&digest, staging.path())
        .await
        .err()
        .unwrap();

    for error in [buffered, streamed] {
        assert!(
            error
                .to_string()
                .contains("exceeded the size of its digest"),
            "unexpected error: {error}"
        );
    }
}

#[tokio::test]
async fn rejects_remote_blobs_over_client_limits_before_downloading() {
    let server = mockito::Server::new_async().await;
    let client = test_client(&server);
    let staging = tempfile::tempdir().unwrap();
    let buffered = CacheDigest {
        algorithm: "blake3".into(),
        hash: "0".repeat(64),
        size: MAX_REMOTE_JSON_BYTES + 1,
    };
    let streamed = CacheDigest {
        algorithm: "blake3".into(),
        hash: "0".repeat(64),
        size: MAX_REMOTE_BLOB_BYTES + 1,
    };

    assert!(
        client
            .get_blob(&buffered, BLOB_MEDIA_TYPE)
            .await
            .unwrap_err()
            .to_string()
            .contains("in-memory blob declared")
    );
    assert!(
        client
            .get_blob_file(&streamed, staging.path())
            .await
            .unwrap_err()
            .to_string()
            .contains("remote cache blob declared")
    );
}

#[tokio::test]
async fn rejects_oversized_capabilities() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", format!("/v{PROTOCOL_VERSION}/capabilities").as_str())
        .with_status(200)
        .with_body(vec![b'x'; MAX_REMOTE_JSON_BYTES as usize + 1])
        .create_async()
        .await;

    // Negotiation runs before any other request, so an unbounded body here
    // would exhaust the process before the other limits ever apply.
    let error = test_client(&server)
        .blob_pack_limits()
        .await
        .err()
        .unwrap()
        .to_string();
    assert!(
        error.contains("over the") || error.contains("exceeded the"),
        "unexpected error: {error}"
    );
}

#[tokio::test]
async fn caps_streaming_upload_packs_below_the_download_limit() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", format!("/v{PROTOCOL_VERSION}/capabilities").as_str())
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_packs":true,"blob_pack_uploads":true},
                "limits":{"max_batch_items":10000,"max_pack_bytes":5368709120_u64}
            })
            .to_string(),
        )
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let downloads = client.blob_pack_limits().await.unwrap().unwrap();
    let uploads = client.blob_pack_upload_limits().await.unwrap().unwrap();

    assert_eq!(downloads.max_bytes, MAX_STAGED_BLOB_PACK_BYTES);
    assert_eq!(uploads.max_bytes, MAX_UPLOAD_BLOB_PACK_BYTES);
    assert_eq!(uploads.max_items, MAX_STAGED_BLOB_PACK_ITEMS);
}

#[tokio::test]
async fn rejects_action_json_larger_than_the_limit() {
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"action");
    let oversized = vec![b'x'; MAX_REMOTE_JSON_BYTES as usize + 1];
    for kind in ["action-results", "action-manifests"] {
        server
            .mock(
                "GET",
                format!(
                    "/v{PROTOCOL_VERSION}/{kind}/{}/{}/{}",
                    key.algorithm, key.hash, key.size
                )
                .as_str(),
            )
            .with_status(200)
            // The manifest path parses the ETag before the body, so the
            // limit only gets its say once a well-formed one is present.
            .with_header("etag", &format!("\"{}\"", blake3::hash(b"any").to_hex()))
            .with_body(oversized.clone())
            .create_async()
            .await;
    }
    let client = test_client(&server);

    // Neither endpoint's body is bounded by a digest, so the limit is the
    // only thing standing between a hostile server and this process's memory.
    for error in [
        client.get_action_result(&key).await.err().unwrap(),
        client.get_action_manifest(&key).await.err().unwrap(),
    ] {
        assert!(
            error.to_string().contains("over the") || error.to_string().contains("exceeded the"),
            "unexpected error: {error}"
        );
    }
}

#[tokio::test]
async fn manifest_etags_survive_a_proxy_that_re_encodes_the_response() {
    // RFC 9110 section 8.8.3.3 obliges an intermediary that compresses a
    // response to vary the strong ETag with the coding, and Caddy does it by
    // appending the coding name. Every deployment behind such a proxy serves
    // tags that cannot be the body's digest, and they still have to reach
    // If-Match intact or no manifest can ever be updated.
    let mut server = mockito::Server::new_async().await;
    let key = CacheDigest::blake3(b"manifest");
    let body = br#"{"predictions":[],"task":"a","version":1}"#;
    let proxied = format!("{}-zstd", blake3::hash(body).to_hex());
    let path = format!(
        "/v{PROTOCOL_VERSION}/action-manifests/{}/{}/{}",
        key.algorithm, key.hash, key.size
    );
    let get = server
        .mock("GET", path.as_str())
        .with_status(200)
        .with_header("etag", &format!("\"{proxied}\""))
        .with_body(body)
        .create_async()
        .await;
    let put = server
        .mock("PUT", path.as_str())
        .match_header("if-match", format!("\"{proxied}\"").as_str())
        .with_status(204)
        .create_async()
        .await;
    let client = test_client(&server);

    let manifest = client.get_action_manifest(&key).await.unwrap().unwrap();
    assert_eq!(manifest.etag, proxied);
    assert_eq!(manifest.bytes, body);
    assert_eq!(
        client
            .put_action_manifest(&key, &manifest.bytes, Some(&manifest.etag))
            .await
            .unwrap(),
        ManifestPutOutcome::Stored
    );
    get.assert_async().await;
    put.assert_async().await;
}

#[test]
fn entity_tags_are_opaque_but_still_have_to_be_strong() {
    let hash = blake3::hash(b"manifest").to_hex().to_string();
    for accepted in [hash.clone(), format!("{hash}-zstd"), "anything".into()] {
        let header = HeaderValue::from_str(&format!("\"{accepted}\"")).unwrap();
        assert_eq!(parse_strong_etag(Some(&header)).unwrap(), accepted);
        assert!(quoted_etag(&accepted).is_ok());
    }
    // A weak validator cannot carry a conditional update, and an unquoted or
    // prematurely terminated tag is not one at all.
    for rejected in [
        format!("W/\"{hash}\""),
        hash.clone(),
        format!("\"{hash}"),
        "\"\"".into(),
        "\"quo\"te\"".into(),
    ] {
        let header = HeaderValue::from_str(&rejected).unwrap();
        assert!(
            parse_strong_etag(Some(&header)).is_err(),
            "accepted {rejected}"
        );
    }
    assert!(parse_strong_etag(None).is_err());
    assert!(quoted_etag(&"x".repeat(MAX_ETAG_BYTES + 1)).is_err());
}

#[tokio::test]
async fn uploads_compress_when_the_server_offers_zstd() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "compressors":["identity","zstd"]
            })
            .to_string(),
        )
        .create_async()
        .await;
    let payload = b"compressible cached output ".repeat(64);
    let expected = payload.clone();
    let put = server
        .mock("PUT", mockito::Matcher::Regex("^/v1/blobs/".into()))
        .match_header("content-encoding", "zstd")
        .match_request(move |request| {
            let body = request.body().expect("upload body");
            // Smaller on the wire, and decoding returns the exact payload:
            // the compression is real, not just a header.
            body.len() < expected.len()
                && zstd::decode_all(body.as_slice()).ok().as_deref() == Some(&expected[..])
        })
        .with_status(201)
        .create_async()
        .await;

    let client = test_client(&server);
    client
        .put_blob(&BlobUpload {
            digest: CacheDigest::blake3(&payload),
            source: BlobSource::Bytes(payload.clone()),
        })
        .await
        .unwrap();
    put.assert_async().await;
}

#[tokio::test]
async fn uploads_stay_identity_without_the_advertisement() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(serde_json::json!({"protocol":{"major":1}}).to_string())
        .create_async()
        .await;
    let payload = b"uncompressed cached output".to_vec();
    let put = server
        .mock("PUT", mockito::Matcher::Regex("^/v1/blobs/".into()))
        .match_body(mockito::Matcher::from(payload.clone()))
        .match_request(|request| request.header("content-encoding").is_empty())
        .with_status(201)
        .create_async()
        .await;

    let client = test_client(&server);
    client
        .put_blob(&BlobUpload {
            digest: CacheDigest::blake3(&payload),
            source: BlobSource::Bytes(payload.clone()),
        })
        .await
        .unwrap();
    put.assert_async().await;
}

#[tokio::test]
async fn downloads_decompress_zstd_responses() {
    let mut server = mockito::Server::new_async().await;
    let payload = b"compressible cached output ".repeat(64);
    let digest = CacheDigest::blake3(&payload);
    let compressed = zstd::encode_all(payload.as_slice(), 0).unwrap();
    assert!(compressed.len() < payload.len());
    server
        .mock(
            "GET",
            format!("/v1/blobs/blake3/{}/{}", digest.hash, digest.size).as_str(),
        )
        .with_status(200)
        .with_header("content-type", BLOB_MEDIA_TYPE)
        .with_header("content-encoding", "zstd")
        .with_body(compressed)
        .create_async()
        .await;

    let client = test_client(&server);
    // Digest verification runs on what the transport hands back, so this
    // passes only if the zstd body was transparently decompressed.
    let bytes = client.get_blob(&digest, BLOB_MEDIA_TYPE).await.unwrap();
    assert_eq!(bytes, payload);
}

fn test_client(server: &mockito::ServerGuard) -> HttpRemoteCache {
    test_client_with(server, Duration::from_secs(1), 0)
}

fn test_client_with(
    server: &mockito::ServerGuard,
    download_timeout: Duration,
    retries: i64,
) -> HttpRemoteCache {
    // Zero leaves the stall budget out of the way: these tests provoke read
    // failures deliberately and must keep reading afterwards.
    test_client_with_stall_budget(server, download_timeout, retries, Duration::ZERO)
}

fn test_client_with_stall_budget(
    server: &mockito::ServerGuard,
    download_timeout: Duration,
    retries: i64,
    read_stall_budget: Duration,
) -> HttpRemoteCache {
    let mut client = HttpRemoteCache::new(RemoteCacheConfig {
        base_url: server.url().parse().unwrap(),
        namespace: "test".into(),
        token: Some("test-token".into()),
        token_file: None,
        oidc_audience: None,
        connect_timeout: Duration::from_secs(1),
        read_timeout: Duration::from_secs(1),
        download_timeout,
        retries,
    })
    .unwrap();
    client.set_read_stall_budget(read_stall_budget);
    client
}

async fn mock_blob_pack_capabilities(server: &mut mockito::ServerGuard) {
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_packs":true},
                "limits":{"max_batch_items":100,"max_pack_bytes":1024}
            })
            .to_string(),
        )
        .create_async()
        .await;
}

async fn mock_capabilities(server: &mut mockito::ServerGuard, features: serde_json::Value) {
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":features,
                "limits":{"max_batch_items":100,"max_pack_bytes":1024}
            })
            .to_string(),
        )
        .create_async()
        .await;
}

/// Read a framed pack the way a server would, for asserting what was uploaded.
fn decode_blob_pack_frames(pack: &[u8]) -> Vec<(String, u64, Vec<u8>)> {
    assert_eq!(&pack[..BLOB_PACK_MAGIC.len()], BLOB_PACK_MAGIC);
    let mut frames = Vec::new();
    let mut rest = &pack[BLOB_PACK_MAGIC.len()..];
    while !rest.is_empty() {
        let algorithm = match rest[0] {
            1 => "blake3",
            2 => "sha256",
            other => panic!("unexpected pack algorithm {other}"),
        };
        let hash = hex::encode(&rest[1..33]);
        let size = u64::from_be_bytes(rest[33..41].try_into().unwrap());
        let end = 41 + size as usize;
        frames.push((format!("{algorithm}:{hash}"), size, rest[41..end].to_vec()));
        rest = &rest[end..];
    }
    frames
}

fn encode_blob_pack(entries: &[(&CacheDigest, &[u8])]) -> Vec<u8> {
    let mut pack = BLOB_PACK_MAGIC.to_vec();
    for (digest, contents) in entries {
        assert_eq!(digest.size, contents.len() as u64);
        pack.push(match digest.algorithm.as_str() {
            "blake3" => 1,
            "sha256" => 2,
            algorithm => panic!("unexpected test digest algorithm {algorithm}"),
        });
        pack.extend(hex::decode(&digest.hash).unwrap());
        pack.extend(digest.size.to_be_bytes());
        pack.extend_from_slice(contents);
    }
    pack
}

#[tokio::test]
async fn looks_up_negotiated_action_batches() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "action_batch": true })).await;
    let found = CacheDigest::blake3(b"found action");
    let missing = CacheDigest::blake3(b"missing action");
    let result = RemoteActionResult {
        action: found.clone(),
        metadata: None,
        output_root: None,
        version: 1,
    };
    let batch = server
        .mock("POST", "/v1/action-results:batch")
        .match_header("content-type", DIGEST_LIST_MEDIA_TYPE)
        .match_header("accept", ACTION_RESULT_BATCH_MEDIA_TYPE)
        .match_body(mockito::Matcher::Json(serde_json::json!({
            "digests": [found, missing],
        })))
        .with_status(200)
        .with_header("content-type", ACTION_RESULT_BATCH_MEDIA_TYPE)
        // A server answers only for what it holds, and may describe the batch
        // with fields this client does not know.
        .with_body(serde_json::json!({"results":[result],"truncated":false}).to_string())
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let results = client
        .get_action_results(&[found.clone(), missing])
        .await
        .unwrap()
        .expect("the server advertised batched lookups");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].action, found);
    batch.assert_async().await;
}

#[tokio::test]
async fn action_batches_fall_back_when_not_advertised() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({})).await;
    let batch = server
        .mock("POST", "/v1/action-results:batch")
        .expect(0)
        .create_async()
        .await;
    let client = test_client(&server);

    let action = CacheDigest::blake3(b"unbatched action");
    assert!(
        client
            .get_action_results(&[action])
            .await
            .unwrap()
            .is_none()
    );
    batch.assert_async().await;
}

#[tokio::test]
async fn action_batches_stop_after_the_endpoint_is_missing() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "action_batch": true })).await;
    // Advertised but not served: asking again every wave would cost a round
    // trip to learn the same thing.
    let batch = server
        .mock("POST", "/v1/action-results:batch")
        .with_status(404)
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let action = CacheDigest::blake3(b"absent endpoint");
    assert!(
        client
            .get_action_results(std::slice::from_ref(&action))
            .await
            .unwrap()
            .is_none()
    );
    assert!(
        client
            .get_action_results(&[action])
            .await
            .unwrap()
            .is_none()
    );
    batch.assert_async().await;
}

#[tokio::test]
async fn rejects_action_batch_results_that_were_not_requested() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "action_batch": true })).await;
    let requested = CacheDigest::blake3(b"requested action");
    // Accepting this would key cached outputs under an action this client never
    // derived.
    let unrequested = RemoteActionResult {
        action: CacheDigest::blake3(b"someone else's action"),
        metadata: None,
        output_root: None,
        version: 1,
    };
    server
        .mock("POST", "/v1/action-results:batch")
        .with_status(200)
        .with_header("content-type", ACTION_RESULT_BATCH_MEDIA_TYPE)
        .with_body(serde_json::json!({ "results": [unrequested] }).to_string())
        .create_async()
        .await;
    let client = test_client(&server);

    let error = client
        .get_action_results(&[requested])
        .await
        .expect_err("an unrequested action result was accepted");
    assert!(error.to_string().contains("unrequested action"));
}

/// A pack holds as many objects as a build compiles, and each one is opened
/// only while the stream is on it -- so a large pack neither spends a file
/// descriptor per member for the length of the request nor nests a frame per
/// member before the first byte is sent.
#[tokio::test]
async fn streams_a_pack_of_many_members_from_files() {
    let mut server = mockito::Server::new_async().await;
    server
        .mock("GET", "/v1/capabilities")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(
            serde_json::json!({
                "protocol":{"major":1},
                "features":{"blob_pack_uploads":true},
                "limits":{"max_batch_items":1000,"max_pack_bytes":1048576}
            })
            .to_string(),
        )
        .create_async()
        .await;
    let directory = tempfile::tempdir().unwrap();
    let mut uploads = Vec::new();
    let mut expected = Vec::new();
    let mut payload_bytes = 0;
    for index in 0..200 {
        let bytes = format!("packed member {index}").into_bytes();
        let digest = CacheDigest::blake3(&bytes);
        let path = directory.path().join(format!("member-{index}"));
        fs::write(&path, &bytes).unwrap();
        payload_bytes += digest.size;
        expected.push((format!("blake3:{}", digest.hash), digest.size, bytes));
        uploads.push(BlobUpload {
            digest,
            source: BlobSource::Path(path),
        });
    }
    let upload = server
        .mock("POST", "/v1/blobs:pack-upload")
        .match_header(BLOB_PACK_BLOBS_HEADER, "200")
        .match_request(move |request| decode_blob_pack_frames(request.body().unwrap()) == expected)
        .with_status(200)
        .with_body(serde_json::json!({"created":200,"existing":0}).to_string())
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let receipt = client
        .put_blob_pack(&uploads)
        .await
        .unwrap()
        .expect("the server advertised packed uploads");

    assert_eq!(receipt.created, 200);
    assert_eq!(
        payload_bytes,
        uploads.iter().map(|upload| upload.digest.size).sum::<u64>()
    );
    upload.assert_async().await;
}

#[tokio::test]
async fn pack_stream_stops_each_member_at_its_declared_size() {
    let directory = tempfile::tempdir().unwrap();
    let first_bytes = b"first packed blob";
    let second_bytes = b"second packed blob";
    let first = CacheDigest::blake3(first_bytes);
    let second = CacheDigest::blake3(second_bytes);
    let first_path = directory.path().join("first");
    let second_path = directory.path().join("second");
    fs::write(
        &first_path,
        [first_bytes.as_slice(), b"trailing bytes"].concat(),
    )
    .unwrap();
    fs::write(&second_path, second_bytes).unwrap();
    let uploads = [
        BlobUpload {
            digest: first.clone(),
            source: BlobSource::Path(first_path),
        },
        BlobUpload {
            digest: second.clone(),
            source: BlobSource::Path(second_path),
        },
    ];

    let chunks = blob_pack_stream(blob_pack_members(&uploads).unwrap())
        .try_collect::<Vec<_>>()
        .await
        .unwrap();
    let pack = chunks.concat();

    assert_eq!(
        decode_blob_pack_frames(&pack),
        vec![
            (
                format!("blake3:{}", first.hash),
                first.size,
                first_bytes.to_vec(),
            ),
            (
                format!("blake3:{}", second.hash),
                second.size,
                second_bytes.to_vec(),
            ),
        ]
    );
}

#[tokio::test]
async fn pack_stream_rejects_members_shorter_than_their_declared_size() {
    let directory = tempfile::tempdir().unwrap();
    let complete = b"complete packed blob";
    let digest = CacheDigest::blake3(complete);
    let path = directory.path().join("truncated");
    fs::write(&path, &complete[..complete.len() - 1]).unwrap();
    let uploads = [BlobUpload {
        digest,
        source: BlobSource::Path(path),
    }];

    let error = blob_pack_stream(blob_pack_members(&uploads).unwrap())
        .try_collect::<Vec<_>>()
        .await
        .expect_err("a short member was accepted");

    assert_eq!(error.kind(), std::io::ErrorKind::UnexpectedEof);
    assert!(error.to_string().contains("1 bytes remaining"));
}

#[tokio::test]
async fn uploads_negotiated_blob_packs() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(
        &mut server,
        serde_json::json!({ "blob_pack_uploads": true }),
    )
    .await;
    let first_bytes = b"first packed blob".to_vec();
    let second_bytes = b"second packed blob".to_vec();
    let first = CacheDigest::blake3(&first_bytes);
    let second = CacheDigest::blake3(&second_bytes);
    let expected = vec![
        (
            format!("blake3:{}", first.hash),
            first.size,
            first_bytes.clone(),
        ),
        (
            format!("blake3:{}", second.hash),
            second.size,
            second_bytes.clone(),
        ),
    ];
    let framed =
        BLOB_PACK_MAGIC.len() as u64 + first.size + second.size + BLOB_PACK_HEADER_BYTES * 2;
    let upload = server
        .mock("POST", "/v1/blobs:pack-upload")
        .match_header("content-type", BLOB_PACK_MEDIA_TYPE)
        .match_header(BLOB_PACK_BLOBS_HEADER, "2")
        .match_header(
            BLOB_PACK_BYTES_HEADER,
            (first.size + second.size).to_string().as_str(),
        )
        .match_header("content-length", framed.to_string().as_str())
        .match_request(move |request| decode_blob_pack_frames(request.body().unwrap()) == expected)
        .with_status(200)
        .with_header("content-type", BLOB_PACK_RECEIPT_MEDIA_TYPE)
        .with_body(serde_json::json!({"created":2,"existing":0}).to_string())
        .expect(1)
        .create_async()
        .await;
    let client = test_client(&server);

    let receipt = client
        .put_blob_pack(&[
            BlobUpload {
                digest: first,
                source: BlobSource::Bytes(first_bytes),
            },
            BlobUpload {
                digest: second,
                source: BlobSource::Bytes(second_bytes),
            },
        ])
        .await
        .unwrap()
        .expect("the server advertised packed uploads");

    assert_eq!(receipt.created, 2);
    assert_eq!(receipt.existing, 0);
    upload.assert_async().await;
}

#[tokio::test]
async fn packed_uploads_fall_back_when_not_advertised() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(&mut server, serde_json::json!({ "blob_packs": true })).await;
    let upload = server
        .mock("POST", "/v1/blobs:pack-upload")
        .expect(0)
        .create_async()
        .await;
    let client = test_client(&server);

    let bytes = b"unpacked blob".to_vec();
    let digest = CacheDigest::blake3(&bytes);
    assert!(
        client
            .put_blob_pack(&[BlobUpload {
                digest,
                source: BlobSource::Bytes(bytes),
            }])
            .await
            .unwrap()
            .is_none()
    );
    upload.assert_async().await;
}

#[tokio::test]
async fn refuses_packs_over_the_negotiated_size() {
    let mut server = mockito::Server::new_async().await;
    mock_capabilities(
        &mut server,
        serde_json::json!({ "blob_pack_uploads": true }),
    )
    .await;
    let client = test_client(&server);

    // The advertised ceiling is 1024 bytes.
    let bytes = vec![0u8; 2048];
    let digest = CacheDigest::blake3(&bytes);
    let error = client
        .put_blob_pack(&[BlobUpload {
            digest,
            source: BlobSource::Bytes(bytes),
        }])
        .await
        .expect_err("an oversized pack was sent");
    assert!(error.to_string().contains("exceeds the negotiated limit"));
}

#[tokio::test]
async fn token_file_credentials_are_reloaded() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("cache-token");
    fs::write(&path, "first-token\n").unwrap();
    let credential = RemoteCacheCredential::File(path.clone());

    let first = credential.authorization().await.unwrap().unwrap();
    assert_eq!(first, "Bearer first-token");
    assert!(first.is_sensitive());

    fs::write(path, "rotated-token\n").unwrap();
    let rotated = credential.authorization().await.unwrap().unwrap();
    assert_eq!(rotated, "Bearer rotated-token");
}

#[tokio::test]
async fn github_actions_oidc_tokens_are_acquired_and_cached() {
    let mut server = mockito::Server::new_async().await;
    let expires_at = unix_timestamp().unwrap() + 3600;
    let token = test_jwt(expires_at);
    let token_response = serde_json::json!({"value":token}).to_string();
    let request = server
        .mock("GET", "/oidc")
        .match_query(mockito::Matcher::UrlEncoded(
            "audience".into(),
            "https://cache.example.com".into(),
        ))
        .match_header("authorization", "Bearer request-secret")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(token_response)
        .expect(1)
        .create_async()
        .await;
    let credential = GithubActionsOidcCredential::new(
        "https://cache.example.com",
        format!("{}/oidc?api-version=1&audience=old", server.url())
            .parse()
            .unwrap(),
        "request-secret",
        reqwest::Client::new(),
        0,
    )
    .unwrap();
    assert_eq!(
        credential.request_url.query_pairs().collect::<Vec<_>>(),
        vec![
            ("api-version".into(), "1".into()),
            ("audience".into(), "https://cache.example.com".into()),
        ]
    );

    let first = credential.authorization().await.unwrap();
    let second = credential.authorization().await.unwrap();

    assert_eq!(first, format!("Bearer {token}"));
    assert_eq!(first, second);
    assert!(first.is_sensitive());
    request.assert_async().await;
}

#[test]
fn oidc_request_urls_require_https_except_for_loopback() {
    validate_oidc_request_url(&"https://example.com/oidc".parse().unwrap()).unwrap();
    validate_oidc_request_url(&"http://127.0.0.1:3000/oidc".parse().unwrap()).unwrap();
    assert!(validate_oidc_request_url(&"http://example.com/oidc".parse().unwrap()).is_err());
}

fn test_jwt(expires_at: u64) -> String {
    let header = URL_SAFE_NO_PAD.encode(b"{}");
    let claims =
        URL_SAFE_NO_PAD.encode(serde_json::to_vec(&serde_json::json!({"exp":expires_at})).unwrap());
    format!("{header}.{claims}.signature")
}

#[test]
fn remote_urls_require_https_for_authenticated_requests() {
    for url in [
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://[::1]:3000",
        "https://cache.example.com",
    ] {
        validate_remote_url(&url.parse().unwrap(), true).unwrap();
    }
    let insecure: Url = "http://cache.example.com".parse().unwrap();
    assert!(validate_remote_url(&insecure, true).is_err());
    validate_remote_url(&insecure, false).unwrap();
    assert!(validate_remote_url(&"ftp://localhost/cache".parse().unwrap(), false).is_err());
}

/// `download_timeout` is a deadline for the whole download rather than a budget
/// each attempt gets afresh, so it has to expire while retries are still
/// unspent. Four retries sleep at least 100ms + 500ms + 2s + 7.5s between
/// attempts, so returning well inside that shows the deadline cut the retry
/// loop short instead of restarting with every attempt.
#[tokio::test]
async fn blob_download_timeout_spans_retries_rather_than_one_attempt() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"retried blob");
    let request = server
        .mock(
            "GET",
            format!("/v1/blobs/blake3/{}/{}", digest.hash, digest.size).as_str(),
        )
        .with_status(503)
        .expect_at_least(1)
        .create_async()
        .await;
    let client = test_client_with(&server, Duration::from_millis(200), 4);
    let staging = tempfile::tempdir().unwrap();

    let started = Instant::now();
    let error = client
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

/// The packed path shares the deadline semantics of the single-blob path; only
/// the size of the budget differs, scaled by what the pack declares.
#[tokio::test]
async fn blob_pack_download_timeout_spans_retries_rather_than_one_attempt() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"retried packed blob");
    mock_blob_pack_capabilities(&mut server).await;
    let request = server
        .mock("POST", "/v1/blobs:pack")
        .with_status(503)
        .expect_at_least(1)
        .create_async()
        .await;
    let client = test_client_with(&server, Duration::from_millis(200), 4);
    let staging = tempfile::tempdir().unwrap();

    let started = Instant::now();
    let error = client
        .get_blob_pack(&[digest], staging.path())
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

/// A 503 is transient, so without the deadline the retry loop would run to the
/// end of its backoff. This is the control for the two tests above: the same
/// server, given a budget large enough to cover the whole loop, spends every
/// retry and fails with the server's error rather than a timeout.
#[tokio::test]
async fn transient_failures_exhaust_retries_within_a_generous_deadline() {
    let mut server = mockito::Server::new_async().await;
    let digest = CacheDigest::blake3(b"retried blob");
    let request = server
        .mock(
            "GET",
            format!("/v1/blobs/blake3/{}/{}", digest.hash, digest.size).as_str(),
        )
        .with_status(503)
        .expect(2)
        .create_async()
        .await;
    let client = test_client_with(&server, Duration::from_secs(30), 1);
    let staging = tempfile::tempdir().unwrap();

    let error = client
        .get_blob_file(&digest, staging.path())
        .await
        .err()
        .unwrap();

    assert!(!error.to_string().contains("budget"), "{error}");
    request.assert_async().await;
}
