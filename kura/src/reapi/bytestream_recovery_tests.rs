use super::*;
use crate::config::ReapiCasDurability;
use crate::test_support::test_context;
use bazel_remote_apis::build::bazel::remote::execution::v2::content_addressable_storage_client::ContentAddressableStorageClient;
use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn existing_blob_acknowledgements_cover_a_cancelled_visible_commit() {
    for mode in [
        ReapiCasDurability::PerWrite,
        ReapiCasDurability::ActionResult,
    ] {
        for operation in ["status", "write", "batch", "find_missing"] {
            let context = test_context(|config| config.reapi_cas_durability = mode).await;
            let store = context.state.store.clone();
            store.sync_feed_activate().await.unwrap();
            store
                .persist_artifact_from_bytes(
                    ArtifactProducer::Reapi,
                    "recovery",
                    "sentinel",
                    "application/octet-stream",
                    b"sentinel",
                )
                .await
                .unwrap();
            let head_before = store.sync_feed().head();
            let bytes = b"cancelled but database-visible content".to_vec();
            let digest = reapi::Digest {
                hash: hex::encode(Sha256::digest(&bytes)),
                size_bytes: bytes.len() as i64,
            };
            let key = blob_key(&format!("{}/{}", digest.hash, digest.size_bytes));
            let (reached_tx, reached_rx) = tokio::sync::oneshot::channel();
            let (finished_tx, finished_rx) = tokio::sync::oneshot::channel();
            let (resume_tx, resume_rx) = std::sync::mpsc::channel();
            let reached_tx = std::sync::Mutex::new(Some(reached_tx));
            let finished_tx = std::sync::Mutex::new(Some(finished_tx));
            let resume_rx = std::sync::Mutex::new(resume_rx);
            store.set_write_commit_observer(Some(Arc::new(move || {
                reached_tx.lock().unwrap().take().unwrap().send(()).unwrap();
                // Closing the sender on test failure also releases the worker.
                let _ = resume_rx.lock().unwrap().recv();
                let _ = finished_tx.lock().unwrap().take().unwrap().send(());
            })));
            let writer_store = store.clone();
            let writer_key = key.clone();
            let writer_bytes = bytes.clone();
            let writer = tokio::spawn(async move {
                writer_store
                    .persist_artifact_from_bytes_and_replicate(
                        ArtifactProducer::Reapi,
                        "recovery",
                        &writer_key,
                        "application/octet-stream",
                        &writer_bytes,
                    )
                    .await
            });
            tokio::time::timeout(std::time::Duration::from_secs(10), reached_rx)
                .await
                .unwrap()
                .unwrap();
            store.set_write_commit_observer(None);
            writer.abort();
            assert!(writer.await.unwrap_err().is_cancelled());
            assert!(
                store
                    .artifact_manifest_exists(ArtifactProducer::Reapi, "recovery", &key)
                    .unwrap()
            );
            if mode == ReapiCasDurability::ActionResult {
                assert_eq!(
                    store.sync_feed().head(),
                    head_before,
                    "cancellation must not expose an undurable feed row"
                );
            }
            let before = store.wal_write_counts().2;
            let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap();
            let router = routes(context.state.clone());
            let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
            let resource_name = format!(
                "recovery/uploads/cancelled/blobs/{}/{}",
                digest.hash, digest.size_bytes
            );
            match operation {
                "status" => {
                    let mut client = ByteStreamClient::connect(format!("http://{address}"))
                        .await
                        .unwrap();
                    let response = client
                        .query_write_status(bytestream::QueryWriteStatusRequest { resource_name })
                        .await
                        .unwrap()
                        .into_inner();
                    assert!(response.complete);
                    assert_eq!(response.committed_size, digest.size_bytes);
                }
                "write" => {
                    let mut client = ByteStreamClient::connect(format!("http://{address}"))
                        .await
                        .unwrap();
                    let response = client
                        .write(tokio_stream::iter([bytestream::WriteRequest {
                            resource_name,
                            write_offset: 0,
                            finish_write: true,
                            data: bytes,
                        }]))
                        .await
                        .unwrap()
                        .into_inner();
                    assert_eq!(response.committed_size, digest.size_bytes);
                }
                "batch" => {
                    let mut client =
                        ContentAddressableStorageClient::connect(format!("http://{address}"))
                            .await
                            .unwrap();
                    let response = client
                        .batch_update_blobs(reapi::BatchUpdateBlobsRequest {
                            instance_name: "recovery".into(),
                            requests: vec![reapi::batch_update_blobs_request::Request {
                                digest: Some(digest),
                                data: bytes,
                                compressor: 0,
                            }],
                            ..Default::default()
                        })
                        .await
                        .unwrap()
                        .into_inner();
                    assert_eq!(response.responses.len(), 1);
                    assert_eq!(response.responses[0].status.as_ref().unwrap().code, 0);
                }
                "find_missing" => {
                    let mut client =
                        ContentAddressableStorageClient::connect(format!("http://{address}"))
                            .await
                            .unwrap();
                    let response = client
                        .find_missing_blobs(reapi::FindMissingBlobsRequest {
                            instance_name: "recovery".into(),
                            blob_digests: vec![digest],
                            ..Default::default()
                        })
                        .await
                        .unwrap()
                        .into_inner();
                    assert!(response.missing_blob_digests.is_empty());
                }
                _ => unreachable!(),
            }
            if mode == ReapiCasDurability::ActionResult {
                assert_eq!(
                    store.wal_write_counts().2,
                    before,
                    "{operation} must not force a deferred upload flush"
                );
                let target = store
                    .deferred_client_manifest_target()
                    .expect("visible cancelled commit must be registered");
                store
                    .ensure_deferred_client_manifests_durable(Some(target))
                    .await
                    .unwrap();
                assert!(store.wal_write_counts().2 > before);
                assert!(
                    store.sync_feed().head() > head_before,
                    "the covered cancelled commit must become replicable"
                );
            } else if operation != "find_missing" {
                assert!(
                    store.wal_write_counts().2 > before,
                    "{operation} must cover the visible commit before acknowledging it"
                );
            }
            if operation != "find_missing" {
                let after = store.wal_write_counts().2;
                let target = store.deferred_client_manifest_target();
                store.acknowledge_existing_client_manifest().await.unwrap();
                assert_eq!(
                    store.wal_write_counts().2,
                    after,
                    "durable lookup must not flush again"
                );
                assert!(target.is_none());
            }
            resume_tx.send(()).unwrap();
            tokio::time::timeout(std::time::Duration::from_secs(10), finished_rx)
                .await
                .unwrap()
                .unwrap();
            server.abort();
            let _ = server.await;
        }
    }
}

#[tokio::test]
async fn absent_upload_status_requires_restart_instead_of_a_terminal_miss() {
    let context = test_context(|_| {}).await;
    let service = ReapiService::new(context.state.clone());
    let status = service
        .query_write_status(Request::new(bytestream::QueryWriteStatusRequest {
            resource_name: format!("recovery/uploads/unknown/blobs/{}/8", "a".repeat(64)),
        }))
        .await
        .unwrap_err();
    assert_eq!(status.code(), tonic::Code::Unimplemented);
}

#[tokio::test]
async fn completed_upload_status_is_preserved_for_identity_and_compressed_resources() {
    let context = test_context(|_| {}).await;
    let service = ReapiService::new(context.state.clone());
    let bytes = b"completed artifact";
    let hash = hex::encode(Sha256::digest(bytes));
    let key = blob_key(&format!("{hash}/{}", bytes.len()));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            "recovery",
            &key,
            "application/octet-stream",
            bytes,
        )
        .await
        .unwrap();

    for marker in ["blobs", "compressed-blobs/zstd"] {
        let status = service
            .query_write_status(Request::new(bytestream::QueryWriteStatusRequest {
                resource_name: format!("recovery/uploads/id/{marker}/{hash}/{}", bytes.len()),
            }))
            .await
            .unwrap()
            .into_inner();
        assert!(status.complete);
        assert_eq!(status.committed_size, bytes.len() as i64);
    }

    let other_namespace = service
        .query_write_status(Request::new(bytestream::QueryWriteStatusRequest {
            resource_name: format!("other/uploads/id/blobs/{hash}/{}", bytes.len()),
        }))
        .await
        .unwrap_err();
    assert_eq!(other_namespace.code(), tonic::Code::Unimplemented);
}

#[tokio::test]
async fn interrupted_bytestream_upload_can_restart_from_zero_and_verify_its_bytes() {
    let context = test_context(|_| {}).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = routes(context.state.clone());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let mut client = ByteStreamClient::connect(format!("http://{address}"))
        .await
        .unwrap();
    let bytes = (0..8 * 1024 * 1024)
        .map(|index| (index % 251) as u8)
        .collect::<Vec<_>>();
    let hash = hex::encode(Sha256::digest(&bytes));
    let resource = format!("recovery/uploads/retry/blobs/{hash}/{}", bytes.len());
    let incomplete = client
        .write(tokio_stream::iter([bytestream::WriteRequest {
            resource_name: resource.clone(),
            write_offset: 0,
            finish_write: false,
            data: bytes[..2 * 1024 * 1024].to_vec(),
        }]))
        .await
        .unwrap_err();
    assert_eq!(incomplete.code(), tonic::Code::InvalidArgument);
    assert_eq!(
        std::fs::read_dir(context.state.config.tmp_dir.join("uploads"))
            .unwrap()
            .count(),
        0,
        "the failed write must not retain partial staging"
    );
    let status = client
        .query_write_status(bytestream::QueryWriteStatusRequest {
            resource_name: resource.clone(),
        })
        .await
        .unwrap_err();
    assert_eq!(status.code(), tonic::Code::Unimplemented);

    let requests = bytes
        .chunks(256 * 1024)
        .enumerate()
        .map(|(index, data)| bytestream::WriteRequest {
            resource_name: resource.clone(),
            write_offset: (index * 256 * 1024) as i64,
            finish_write: (index + 1) * 256 * 1024 == bytes.len(),
            data: data.to_vec(),
        })
        .collect::<Vec<_>>();
    assert_eq!(
        client
            .write(tokio_stream::iter(requests))
            .await
            .unwrap()
            .into_inner()
            .committed_size,
        bytes.len() as i64
    );
    let completed = client
        .query_write_status(bytestream::QueryWriteStatusRequest {
            resource_name: resource,
        })
        .await
        .unwrap()
        .into_inner();
    assert!(completed.complete);
    assert_eq!(completed.committed_size, bytes.len() as i64);
    let mut read = client
        .read(bytestream::ReadRequest {
            resource_name: format!("recovery/blobs/{hash}/{}", bytes.len()),
            read_offset: 0,
            read_limit: 0,
        })
        .await
        .unwrap()
        .into_inner();
    let mut downloaded = Vec::new();
    while let Some(chunk) = read.message().await.unwrap() {
        downloaded.extend(chunk.data);
    }
    assert_eq!(downloaded, bytes);
    server.abort();
    let _ = server.await;
}

/// Incompressible bytes, so a zstd upload spans as many messages as identity.
fn noise(len: usize) -> Vec<u8> {
    let mut state = 0x9e37_79b9_7f4a_7c15_u64;
    (0..len)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state as u8
        })
        .collect()
}

/// Streams `wire` as one Write but holds its final chunk until `before_final`
/// ran. The client hands a chunk to the transport only once flow control has
/// room for the previous ones, and Kura advertises a 4 MiB stream window, so
/// with 16 MiB sent ahead the server has already read most of the stream.
async fn write_holding_final_chunk(
    client: &ByteStreamClient<tonic::transport::Channel>,
    resource: String,
    wire: &[u8],
    before_final: impl std::future::Future<Output = ()>,
) -> Result<i64, Status> {
    let (sender, receiver) = tokio::sync::mpsc::channel(1);
    let requests = futures_util::stream::unfold(receiver, |mut receiver| async move {
        receiver.recv().await.map(|request| (request, receiver))
    });
    let write = tokio::spawn({
        let mut client = client.clone();
        async move { client.write(requests).await }
    });
    let mut before_final = Some(before_final);
    let mut resource_name = Some(resource);
    let mut chunks = wire.chunks(256 * 1024).peekable();
    let mut offset = 0;
    while let Some(data) = chunks.next() {
        let finish_write = chunks.peek().is_none();
        if finish_write && let Some(before_final) = before_final.take() {
            before_final.await;
        }
        sender
            .send(bytestream::WriteRequest {
                resource_name: resource_name.take().unwrap_or_default(),
                write_offset: offset as i64,
                finish_write,
                data: data.to_vec(),
            })
            .await
            .unwrap();
        offset += data.len();
    }
    write
        .await
        .unwrap()
        .map(|response| response.into_inner().committed_size)
}

async fn stored_blob_fixture() -> (
    crate::test_support::TestContext,
    ByteStreamClient<tonic::transport::Channel>,
    tokio::task::JoinHandle<()>,
    Vec<u8>,
    String,
    String,
) {
    let context = test_context(|_| {}).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = routes(context.state.clone());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let client = ByteStreamClient::connect(format!("http://{address}"))
        .await
        .unwrap();
    let bytes = noise(20 * 1024 * 1024);
    let hash = hex::encode(Sha256::digest(&bytes));
    let key = blob_key(&format!("{hash}/{}", bytes.len()));
    context
        .state
        .store
        .persist_artifact_from_bytes(
            ArtifactProducer::Reapi,
            "recovery",
            &key,
            "application/octet-stream",
            &bytes,
        )
        .await
        .unwrap();
    (context, client, server, bytes, hash, key)
}

#[tokio::test]
async fn write_of_a_stored_blob_is_read_without_staging_or_storing_it_again() {
    let (context, client, server, bytes, hash, key) = stored_blob_fixture().await;
    let stored_version = || {
        context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "recovery", &key)
            .unwrap()
            .expect("the stored blob should keep its manifest")
            .version_ms
    };
    let version_before = stored_version();
    let uploads = context.state.config.tmp_dir.join("uploads");
    let compressed = zstd::encode_all(&bytes[..], 3).unwrap();

    for (marker, wire) in [
        ("blobs", &bytes[..]),
        ("compressed-blobs/zstd", &compressed[..]),
    ] {
        let resource = format!("recovery/uploads/again/{marker}/{hash}/{}", bytes.len());
        let committed = write_holding_final_chunk(&client, resource, wire, async {
            assert_eq!(
                std::fs::read_dir(&uploads)
                    .map(|entries| entries.count())
                    .unwrap_or(0),
                0,
                "{marker}: a stored blob must not be staged"
            );
            assert!(
                context
                    .state
                    .tmp_staging_budget
                    .try_reserve(context.state.config.tmp_dir_max_bytes)
                    .is_ok(),
                "{marker}: a stored blob must not hold a staging reservation"
            );
        })
        .await
        .unwrap();
        assert_eq!(committed, wire.len() as i64, "{marker}");
    }
    assert_eq!(
        stored_version(),
        version_before,
        "the stored blob must not be rewritten"
    );

    let oversized = client
        .clone()
        .write(tokio_stream::iter([bytestream::WriteRequest {
            resource_name: format!("recovery/uploads/oversized/blobs/{hash}/{}", bytes.len()),
            write_offset: 0,
            finish_write: true,
            data: vec![0; bytes.len() + 1],
        }]))
        .await
        .unwrap_err();
    assert_eq!(oversized.code(), tonic::Code::InvalidArgument);
    server.abort();
    let _ = server.await;
}

#[tokio::test]
async fn a_stored_blob_evicted_during_the_upload_is_not_acknowledged() {
    let (context, client, server, bytes, hash, key) = stored_blob_fixture().await;
    let resource = format!("recovery/uploads/evicted/blobs/{hash}/{}", bytes.len());
    let evicted = write_holding_final_chunk(&client, resource.clone(), &bytes, async {
        let manifest = context
            .state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, "recovery", &key)
            .unwrap()
            .unwrap();
        context
            .state
            .store
            .delete_artifact_metadata(&[manifest])
            .unwrap();
    })
    .await
    .unwrap_err();
    assert_eq!(evicted.code(), tonic::Code::Unavailable);

    // The client's restart takes the staging path and stores the blob again.
    let committed = write_holding_final_chunk(&client, resource, &bytes, async {})
        .await
        .unwrap();
    assert_eq!(committed, bytes.len() as i64);
    assert!(
        context
            .state
            .store
            .artifact_exists(ArtifactProducer::Reapi, "recovery", &key)
            .await
            .unwrap()
    );
    server.abort();
    let _ = server.await;
}

#[tokio::test]
async fn write_of_a_composite_only_blob_uploads_normally() {
    let context = test_context(|_| {}).await;
    let service = ReapiService::new(context.state.clone());
    let first = vec![0x11; 1024 * 1024];
    let second = vec![0x22; 1024 * 1024];
    let digest = |bytes: &[u8]| reapi::Digest {
        hash: hex::encode(Sha256::digest(bytes)),
        size_bytes: bytes.len() as i64,
    };
    for chunk in [&first, &second] {
        context
            .state
            .store
            .persist_artifact_from_bytes(
                ArtifactProducer::Reapi,
                "recovery",
                &blob_key(&digest_key(&digest(chunk)).unwrap()),
                "application/octet-stream",
                chunk,
            )
            .await
            .unwrap();
    }
    let mut blob = first.clone();
    blob.extend_from_slice(&second);
    let blob_digest = digest(&blob);
    let mut splice = Request::new(reapi::SpliceBlobRequest {
        instance_name: "recovery".into(),
        blob_digest: Some(blob_digest.clone()),
        chunk_digests: vec![digest(&first), digest(&second)],
        digest_function: 0,
        chunking_function: reapi::chunking_function::Value::FastCdc2020 as i32,
    });
    splice.extensions_mut().insert(
        GrpcWriteAdmission::new(
            &context.state.memory,
            CAS_SPLICE_DECODE_COPIES,
            context.state.metrics.grpc_write_admission_metrics(),
        )
        .unwrap(),
    );
    service.splice_blob(splice).await.unwrap();
    let direct_key = blob_key(&digest_key(&blob_digest).unwrap());
    assert!(
        !context
            .state
            .store
            .artifact_exists(ArtifactProducer::Reapi, "recovery", &direct_key)
            .await
            .unwrap()
    );

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = routes(context.state.clone());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let mut client = ByteStreamClient::connect(format!("http://{address}"))
        .await
        .unwrap();
    let resource = format!(
        "recovery/uploads/composite/blobs/{}/{}",
        blob_digest.hash,
        blob.len()
    );
    let requests = blob
        .chunks(256 * 1024)
        .enumerate()
        .map(|(index, data)| bytestream::WriteRequest {
            resource_name: resource.clone(),
            write_offset: (index * 256 * 1024) as i64,
            finish_write: (index + 1) * 256 * 1024 == blob.len(),
            data: data.to_vec(),
        })
        .collect::<Vec<_>>();
    let committed = client
        .write(tokio_stream::iter(requests))
        .await
        .unwrap()
        .into_inner()
        .committed_size;
    assert_eq!(committed, blob.len() as i64);
    // The recipe is never decoded on the write path, so the full upload ran
    // and stored the blob directly.
    assert!(
        context
            .state
            .store
            .artifact_exists(ArtifactProducer::Reapi, "recovery", &direct_key)
            .await
            .unwrap()
    );
    server.abort();
    let _ = server.await;
}

#[tokio::test]
async fn cancelling_a_staged_write_releases_its_file_and_reservation() {
    let context = test_context(|_| {}).await;
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = routes(context.state.clone());
    let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
    let mut client = ByteStreamClient::connect(format!("http://{address}"))
        .await
        .unwrap();
    let size = 8 * 1024 * 1024;
    let hash = "b".repeat(64);
    let requests = tokio_stream::iter([bytestream::WriteRequest {
        resource_name: format!("recovery/uploads/cancel/blobs/{hash}/{size}"),
        write_offset: 0,
        finish_write: false,
        data: vec![7; 1024 * 1024],
    }])
    .chain(futures_util::stream::pending());
    let upload = tokio::spawn(async move { client.write(requests).await });
    let uploads = context.state.config.tmp_dir.join("uploads");
    let staged_entries = || {
        std::fs::read_dir(&uploads)
            .map(|entries| entries.count())
            .unwrap_or(0)
    };
    let fully_released = || {
        context
            .state
            .tmp_staging_budget
            .try_reserve(context.state.config.tmp_dir_max_bytes)
            .is_ok()
    };
    tokio::time::timeout(Duration::from_secs(5), async {
        while staged_entries() == 0 || fully_released() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the write should stage its first chunk and hold a reservation");

    // Dropping the client call resets the stream, as a transport interruption does.
    upload.abort();
    let _ = upload.await;
    tokio::time::timeout(Duration::from_secs(5), async {
        while staged_entries() != 0 || !fully_released() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("a cancelled write must remove its staging file and release its reservation");
    server.abort();
    let _ = server.await;
}
