use super::*;
use crate::test_support::test_context;
use bazel_remote_apis::google::bytestream::byte_stream_client::ByteStreamClient;

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
