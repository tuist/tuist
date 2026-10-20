use api::{
    capabilities_server::{Capabilities, CapabilitiesServer},
    content_addressable_storage_server::{
        ContentAddressableStorage, ContentAddressableStorageServer,
    },
};
use bazel_remote_apis::build::bazel::remote::execution::v2 as api;
use bazel_remote_apis::google::rpc::Status as BlobStatus;
use prost::Message;
use std::{
    collections::HashMap,
    net::TcpListener,
    pin::Pin,
    sync::{Arc, Barrier, Mutex},
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
    SlowDownload,
    DeclinedDownload(i32),
    RecoveringDownload,
    UnrequestedDownload,
    WrongSizeDownload,
    OmittedDigestDownload,
    OmittedResponseDownload,
    TerminalDownload,
    DeclinedSplit(i32),
    DeclinedSplice(i32),
    TerminalSplitOne,
    Latency(u64),
    HoldLaterBatch,
}

#[derive(Default)]
struct Calls {
    capabilities: usize,
    missing: usize,
    splice: usize,
    split: usize,
    reads: usize,
    whole_reads: usize,
    read_digests: Vec<api::Digest>,
    read_bytes: usize,
    updates: usize,
    active_splits: usize,
    max_active_splits: usize,
    active_splices: usize,
    max_active_splices: usize,
    later_batch_waiting: bool,
    release_later_batch: bool,
    blobs: HashMap<String, Vec<u8>>,
}

struct Server {
    mode: Mode,
    calls: Arc<Mutex<Calls>>,
}

impl Server {
    async fn delay(&self) {
        if let Mode::Latency(millis) = self.mode {
            tokio::time::sleep(std::time::Duration::from_millis(millis)).await;
        }
    }
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
        self.delay().await;
        let mut calls = self.calls.lock().unwrap();
        calls.updates += 1;
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
        self.delay().await;
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
        request: Request<api::SpliceBlobRequest>,
    ) -> Result<Response<api::SpliceBlobResponse>, Status> {
        {
            let mut calls = self.calls.lock().unwrap();
            calls.splice += 1;
            calls.active_splices += 1;
            calls.max_active_splices = calls.max_active_splices.max(calls.active_splices);
        }
        self.delay().await;
        let mut calls = self.calls.lock().unwrap();
        calls.active_splices -= 1;
        if let Mode::DeclinedSplice(code) = self.mode {
            return Err(Status::new(tonic::Code::from_i32(code), "splice refused"));
        }
        if matches!(self.mode, Mode::Latency(_)) {
            let request = request.into_inner();
            let digest = request.blob_digest.unwrap();
            let mut assembled = Vec::new();
            for chunk in request.chunk_digests {
                assembled.extend_from_slice(
                    calls
                        .blobs
                        .get(&chunk.hash)
                        .ok_or_else(|| Status::not_found("chunk not uploaded before splice"))?,
                );
            }
            if blob_digest(&assembled) != digest {
                return Err(Status::invalid_argument("incorrect splice"));
            }
            calls.blobs.insert(digest.hash.clone(), assembled);
            return Ok(Response::new(api::SpliceBlobResponse {
                blob_digest: Some(digest),
            }));
        }
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
        if matches!(self.mode, Mode::HoldLaterBatch)
            && request.get_ref().blob_digest.as_ref().unwrap().size_bytes == 30 * 1024 * 1024
        {
            self.calls.lock().unwrap().later_batch_waiting = true;
            tokio::time::timeout(std::time::Duration::from_secs(30), async {
                while !self.calls.lock().unwrap().release_later_batch {
                    tokio::time::sleep(std::time::Duration::from_millis(1)).await;
                }
            })
            .await
            .map_err(|_| Status::deadline_exceeded("test did not release later batch"))?;
        }
        {
            let mut calls = self.calls.lock().unwrap();
            calls.split += 1;
            calls.active_splits += 1;
            calls.max_active_splits = calls.max_active_splits.max(calls.active_splits);
        }
        self.delay().await;
        let mut calls = self.calls.lock().unwrap();
        calls.active_splits -= 1;
        if let Mode::DeclinedSplit(code) = self.mode {
            return Err(Status::new(tonic::Code::from_i32(code), "split refused"));
        }
        if !matches!(
            self.mode,
            Mode::InvalidRecipe
                | Mode::CorruptDownload
                | Mode::MissingDownload
                | Mode::SlowDownload
                | Mode::DeclinedDownload(_)
                | Mode::RecoveringDownload
                | Mode::UnrequestedDownload
                | Mode::WrongSizeDownload
                | Mode::OmittedDigestDownload
                | Mode::OmittedResponseDownload
                | Mode::TerminalDownload
                | Mode::TerminalSplitOne
                | Mode::Latency(_)
                | Mode::HoldLaterBatch
        ) {
            return Err(Status::unimplemented("mixed-version server"));
        }
        let digest = request.into_inner().blob_digest.unwrap();
        let bytes = calls.blobs[&digest.hash].clone();
        if matches!(self.mode, Mode::TerminalSplitOne) && bytes[0] == 1 {
            return Err(Status::internal("split refused for this blob"));
        }
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
        self.delay().await;
        if matches!(self.mode, Mode::SlowDownload) {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        }
        let mut calls = self.calls.lock().unwrap();
        calls.reads += 1;
        if matches!(self.mode, Mode::OmittedResponseDownload) {
            return Ok(Response::new(api::BatchReadBlobsResponse::default()));
        }
        Ok(Response::new(api::BatchReadBlobsResponse {
            responses: request
                .into_inner()
                .digests
                .into_iter()
                .map(|digest| {
                    let mut bytes = calls.blobs[&digest.hash].clone();
                    let mut code = 0;
                    calls.read_digests.push(digest.clone());
                    if digest.size_bytes > 1024 * 1024 {
                        calls.whole_reads += 1;
                    }
                    if digest.size_bytes <= 1024 * 1024 {
                        if matches!(self.mode, Mode::TerminalDownload) && bytes[0] <= 2 {
                            code = if bytes[0] == 1 {
                                tonic::Code::Internal as i32
                            } else {
                                tonic::Code::ResourceExhausted as i32
                            };
                            bytes.clear();
                        }
                        if matches!(self.mode, Mode::RecoveringDownload)
                            && calls.reads == 1
                            && bytes[0] == 1
                        {
                            bytes.clear();
                            code = tonic::Code::ResourceExhausted as i32;
                        }
                        if let Mode::DeclinedDownload(status) = self.mode {
                            bytes.clear();
                            code = status;
                        }
                        if matches!(self.mode, Mode::CorruptDownload) {
                            bytes.fill(0);
                        }
                        if matches!(self.mode, Mode::MissingDownload) {
                            bytes.clear();
                            code = 5;
                        }
                    }
                    calls.read_bytes += bytes.len();
                    let digest = match self.mode {
                        Mode::UnrequestedDownload => Some(blob_digest(b"unrequested")),
                        Mode::WrongSizeDownload => Some(api::Digest {
                            size_bytes: digest.size_bytes + 1,
                            ..digest
                        }),
                        Mode::OmittedDigestDownload => None,
                        _ => Some(digest),
                    };
                    api::batch_read_blobs_response::Response {
                        digest,
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
fn declined_chunks_do_not_trigger_whole_blob_downloads() {
    for code in [
        tonic::Code::ResourceExhausted,
        tonic::Code::Unavailable,
        tonic::Code::PermissionDenied,
        tonic::Code::Unauthenticated,
    ] {
        let status = code as i32;
        let (remote, calls, _stop) = server(Mode::DeclinedDownload(status));
        let directory =
            std::env::temp_dir().join(format!("chunk-declined-{}-{status}", std::process::id()));
        remote.enable_chunk_cache(directory.clone(), "tenant/project");
        let bytes = vec![7; 3 * 1024 * 1024];
        let digest = blob_digest(&bytes);
        calls
            .lock()
            .unwrap()
            .blobs
            .insert(digest.hash.clone(), bytes);
        for attempt in 0..2 {
            let result = remote.batch_read(std::slice::from_ref(&digest));
            let observed = calls.lock().unwrap();
            assert_eq!(observed.whole_reads, 0, "status {status}");
            if matches!(
                code,
                tonic::Code::ResourceExhausted | tonic::Code::Unavailable
            ) {
                assert!(result.unwrap().is_empty());
                assert_eq!(observed.reads, 3 + attempt);
            } else {
                assert!(result.is_err());
                assert_eq!(observed.reads, 1 + attempt);
            }
        }
        if directory.exists() {
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn split_pressure_preserves_small_blobs_and_uses_the_parent_retry_budget() {
    for code in [tonic::Code::ResourceExhausted, tonic::Code::Unavailable] {
        let (remote, calls, _stop) = server(Mode::DeclinedSplit(code as i32));
        let directory = std::env::temp_dir().join(format!(
            "split-pressure-{}-{}",
            std::process::id(),
            code as i32
        ));
        remote.enable_chunk_cache(directory.clone(), "tenant/project");
        let large = vec![7; 3 * 1024 * 1024];
        let large_digest = blob_digest(&large);
        let small: Vec<_> = (0..5).map(|byte| vec![byte; 1024]).collect();
        let mut digests = vec![large_digest.clone()];
        let mut observed = calls.lock().unwrap();
        observed.blobs.insert(large_digest.hash.clone(), large);
        for bytes in &small {
            let digest = blob_digest(bytes);
            observed.blobs.insert(digest.hash.clone(), bytes.clone());
            digests.push(digest);
        }
        drop(observed);
        let result = remote.batch_read(&digests).unwrap();
        assert_eq!(result.len(), 5);
        for (digest, bytes) in digests[1..].iter().zip(&small) {
            assert_eq!(&result[&digest.hash], bytes);
        }
        assert_eq!(calls.lock().unwrap().split, 3);
        assert_eq!(calls.lock().unwrap().reads, 1);
        // Partial success does not arm a node-wide breaker. A fully declined
        // read does, and the following action-result read gets one attempt.
        assert!(remote
            .batch_read(std::slice::from_ref(&large_digest))
            .unwrap()
            .is_empty());
        assert_eq!(calls.lock().unwrap().split, 6);
        assert!(remote
            .batch_read_after_action_result(&[large_digest])
            .unwrap()
            .is_empty());
        assert_eq!(calls.lock().unwrap().split, 7);
        assert_eq!(calls.lock().unwrap().whole_reads, 0);
        if directory.exists() {
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn large_reads_pool_missing_chunks_and_overlap_split_requests() {
    let (remote, calls, _stop) = server(Mode::Latency(300));
    let directory = std::env::temp_dir().join(format!("chunk-batch-read-{}", std::process::id()));
    let outputs: Vec<Vec<u8>> = (0..4)
        .map(|index| {
            (0..3)
                .flat_map(|part| vec![index * 4 + part; 1024 * 1024])
                .collect()
        })
        .collect();
    let digests: Vec<_> = outputs.iter().map(|bytes| blob_digest(bytes)).collect();
    calls.lock().unwrap().blobs.extend(
        digests
            .iter()
            .zip(&outputs)
            .map(|(digest, bytes)| (digest.hash.clone(), bytes.clone())),
    );
    let start = std::time::Instant::now();
    let whole = remote.batch_read(&digests).unwrap();
    let whole_ms = start.elapsed().as_millis();
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    assert!(remote.uses_chunked_compression(3 * 1024 * 1024));
    let start = std::time::Instant::now();
    let chunked = remote.batch_read(&digests).unwrap();
    let chunked_ms = start.elapsed().as_millis();
    assert_eq!(whole, chunked);
    let observed = calls.lock().unwrap();
    println!("BENCH four_outputs_read latency_ms=300 whole_ms={whole_ms} chunked_ms={chunked_ms} chunk_reads={} split_peak={}", observed.reads - 1, observed.max_active_splits);
    assert_eq!(
        observed.reads, 2,
        "one whole read and one pooled missing-chunk read"
    );
    assert_eq!(observed.split, 4);
    assert!(observed.max_active_splits > 1 && observed.max_active_splits <= 8);
    assert_eq!(observed.read_digests.len(), 4 + 12);
    drop(observed);
    assert_eq!(remote.batch_read(&digests).unwrap(), whole);
    assert_eq!(
        calls.lock().unwrap().reads,
        2,
        "fully local chunks need only recipes"
    );
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn large_uploads_pool_presence_and_updates_before_overlapping_splices() {
    let (remote, calls, _stop) = server(Mode::Latency(100));
    let outputs: Vec<_> = (0..6)
        .map(|index| {
            let bytes = vec![index; 3 * 1024 * 1024];
            (blob_digest(&bytes), bytes)
        })
        .collect();
    assert!(remote.uses_chunked_compression(3 * 1024 * 1024));
    let start = std::time::Instant::now();
    remote.batch_update(outputs.clone()).unwrap();
    let elapsed_ms = start.elapsed().as_millis();
    let observed = calls.lock().unwrap();
    println!("BENCH six_outputs_upload latency_ms=100 elapsed_ms={elapsed_ms} missing={} updates={} splice_peak={}", observed.missing, observed.updates, observed.max_active_splices);
    for (digest, bytes) in outputs {
        assert_eq!(observed.blobs[&digest.hash], bytes);
    }
    assert_eq!(observed.missing, 1);
    assert_eq!(observed.updates, 1);
    assert_eq!(observed.splice, 6);
    assert!(observed.max_active_splices > 1 && observed.max_active_splices <= 8);
}

#[test]
fn recipe_requests_are_bounded_in_both_directions() {
    let (remote, calls, _stop) = server(Mode::Latency(30));
    let directory = std::env::temp_dir().join(format!("recipe-concurrency-{}", std::process::id()));
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    let outputs: Vec<_> = (0..10)
        .map(|index| {
            let bytes = vec![index; 3 * 1024 * 1024];
            (blob_digest(&bytes), bytes)
        })
        .collect();
    remote.batch_update(outputs.clone()).unwrap();
    let digests: Vec<_> = outputs.iter().map(|(digest, _)| digest.clone()).collect();
    let restored = remote.batch_read(&digests).unwrap();
    for (digest, bytes) in outputs {
        assert_eq!(restored[&digest.hash], bytes);
    }
    let observed = calls.lock().unwrap();
    assert_eq!(observed.max_active_splits, 8);
    assert_eq!(observed.max_active_splices, 8);
    assert_eq!(observed.missing, 1);
    assert_eq!(observed.updates, 1);
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn splice_refusals_keep_write_backoff_and_never_fall_back_to_whole_uploads() {
    for (code, first, second) in [
        (tonic::Code::ResourceExhausted, 3, 4),
        (tonic::Code::Unavailable, 3, 6),
        (tonic::Code::PermissionDenied, 1, 2),
    ] {
        let (remote, calls, _stop) = server(Mode::DeclinedSplice(code as i32));
        let bytes = vec![1; 3 * 1024 * 1024];
        let digest = blob_digest(&bytes);
        for attempts in [first, second] {
            assert!(remote
                .batch_update(vec![(digest.clone(), bytes.clone())])
                .is_err());
            let observed = calls.lock().unwrap();
            assert_eq!(observed.splice, attempts);
            assert!(!observed.blobs.contains_key(&digest.hash));
        }
        assert_eq!(
            remote.shedding_writes(),
            code == tonic::Code::ResourceExhausted
        );
    }
}

#[test]
fn chunk_retries_keep_verified_pieces_and_reject_unrequested_responses() {
    for (index, mode) in [
        Mode::RecoveringDownload,
        Mode::UnrequestedDownload,
        Mode::WrongSizeDownload,
        Mode::OmittedDigestDownload,
        Mode::OmittedResponseDownload,
    ]
    .into_iter()
    .enumerate()
    {
        let (remote, calls, _stop) = server(mode);
        let directory =
            std::env::temp_dir().join(format!("chunk-response-{}-{index}", std::process::id()));
        remote.enable_chunk_cache(directory.clone(), "tenant/project");
        let bytes: Vec<u8> = (0..3).flat_map(|n| vec![n; 1024 * 1024]).collect();
        let digest = blob_digest(&bytes);
        calls
            .lock()
            .unwrap()
            .blobs
            .insert(digest.hash.clone(), bytes.clone());
        let result = remote.batch_read(std::slice::from_ref(&digest));
        let observed = calls.lock().unwrap();
        assert_eq!(observed.whole_reads, 0);
        if matches!(mode, Mode::RecoveringDownload) {
            assert_eq!(result.unwrap()[&digest.hash], bytes);
            assert_eq!(observed.reads, 2);
            assert_eq!(observed.read_digests.len(), 4);
            assert_eq!(observed.read_digests[3], blob_digest(&vec![1; 1024 * 1024]));
        } else {
            assert!(result.is_err());
            assert_eq!(observed.reads, 1);
        }
        if directory.exists() {
            std::fs::remove_dir_all(directory).unwrap();
        }
    }
}

#[test]
fn terminal_chunk_failures_preserve_other_blobs_without_retry_or_fallback() {
    let (remote, calls, _stop) = server(Mode::TerminalDownload);
    let directory = std::env::temp_dir().join(format!("chunk-terminal-{}", std::process::id()));
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    let bad: Vec<u8> = (1..=3).flat_map(|n| vec![n; 1024 * 1024]).collect();
    let good = vec![4; 3 * 1024 * 1024];
    let bad_digest = blob_digest(&bad);
    let good_digest = blob_digest(&good);
    calls.lock().unwrap().blobs.extend([
        (bad_digest.hash.clone(), bad),
        (good_digest.hash.clone(), good.clone()),
    ]);
    let result = remote
        .batch_read(&[bad_digest.clone(), good_digest.clone()])
        .unwrap();
    assert!(!result.contains_key(&bad_digest.hash));
    assert_eq!(result[&good_digest.hash], good);
    let observed = calls.lock().unwrap();
    assert_eq!(observed.whole_reads, 0);
    assert_eq!(
        observed.reads, 1,
        "terminal errors must not retry pressure-only siblings"
    );
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn per_blob_split_failure_preserves_sibling_outputs() {
    // A terminal split_blob failure on one large output must not take down
    // every other blob in the same batch. Regression pin for the outer-loop
    // abort behaviour.
    let (remote, calls, _stop) = server(Mode::TerminalSplitOne);
    let directory =
        std::env::temp_dir().join(format!("chunk-split-terminal-{}", std::process::id()));
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    let bad = vec![1u8; 3 * 1024 * 1024];
    let good = vec![4u8; 3 * 1024 * 1024];
    let bad_digest = blob_digest(&bad);
    let good_digest = blob_digest(&good);
    calls.lock().unwrap().blobs.extend([
        (bad_digest.hash.clone(), bad),
        (good_digest.hash.clone(), good.clone()),
    ]);
    let result = remote
        .batch_read(&[bad_digest.clone(), good_digest.clone()])
        .unwrap();
    assert!(!result.contains_key(&bad_digest.hash));
    assert_eq!(result[&good_digest.hash], good);
    let observed = calls.lock().unwrap();
    assert_eq!(observed.whole_reads, 0);
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn maximum_chunk_descriptors_fit_the_response_limit() {
    let recipe = api::SplitBlobResponse {
        chunk_digests: vec![
            api::Digest {
                hash: "f".repeat(64),
                size_bytes: 2 * 1024 * 1024,
            };
            16_384
        ],
        chunking_function: api::chunking_function::Value::FastCdc2020 as i32,
    };
    // This overestimates a valid recipe: at the count limit, most chunks
    // must be smaller to respect the logical blob's total-size bound.
    assert!(recipe.encoded_len() < 2 * 1024 * 1024);
    println!("maximum recipe encoded bytes={}", recipe.encoded_len());
}

#[test]
fn background_and_demand_reads_share_large_downloads() {
    let (remote, calls, _stop) = server(Mode::SlowDownload);
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let directory =
        std::env::temp_dir().join(format!("chunk-concurrent-{}-{nonce}", std::process::id()));
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    let bytes: Vec<u8> = (0..3).flat_map(|n| vec![n; 1024 * 1024]).collect();
    let digest = blob_digest(&bytes);
    calls
        .lock()
        .unwrap()
        .blobs
        .insert(digest.hash.clone(), bytes.clone());
    let start = Barrier::new(2);
    std::thread::scope(|scope| {
        let demand = scope.spawn(|| {
            start.wait();
            remote.batch_read(std::slice::from_ref(&digest)).unwrap()
        });
        start.wait();
        let background = remote
            .batch_read_after_action_result(std::slice::from_ref(&digest))
            .unwrap();
        assert_eq!(background[&digest.hash], bytes);
        assert_eq!(demand.join().unwrap()[&digest.hash], bytes);
    });
    let observed = calls.lock().unwrap();
    println!(
        "concurrent download bytes={} reads={} split={}",
        observed.read_bytes, observed.reads, observed.split
    );
    assert_eq!(observed.read_bytes, bytes.len());
    assert_eq!(observed.split, 1);
    std::fs::remove_dir_all(directory).unwrap();
}

#[test]
fn completed_download_does_not_wait_for_a_later_working_batch() {
    use std::time::{Duration, Instant};

    let (remote, calls, _stop) = server(Mode::HoldLaterBatch);
    let directory =
        std::env::temp_dir().join(format!("chunk-batch-release-{}", std::process::id()));
    remote.enable_chunk_cache(directory.clone(), "tenant/project");
    let first = vec![7; 3 * 1024 * 1024];
    let later = vec![9; 30 * 1024 * 1024];
    let first_digest = blob_digest(&first);
    let later_digest = blob_digest(&later);
    calls.lock().unwrap().blobs.extend([
        (first_digest.hash.clone(), first.clone()),
        (later_digest.hash.clone(), later.clone()),
    ]);

    std::thread::scope(|scope| {
        let background = scope.spawn(|| {
            remote.batch_read_after_action_result(&[first_digest.clone(), later_digest.clone()])
        });
        let deadline = Instant::now() + Duration::from_secs(20);
        while !calls.lock().unwrap().later_batch_waiting && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(1));
        }
        // The second split starts only after the first working batch has been
        // reconstructed and verified. Hold it until the independent read ends.
        let waiting = calls.lock().unwrap().later_batch_waiting;
        let (finished, result) = std::sync::mpsc::channel();
        let demand_remote = &remote;
        let demand_digest = &first_digest;
        let demand = scope.spawn(move || {
            let bytes = demand_remote
                .batch_read(std::slice::from_ref(demand_digest))
                .unwrap();
            finished.send(bytes).unwrap();
        });
        let started = Instant::now();
        let completed = result.recv_timeout(Duration::from_secs(3));
        println!("completed output demand read: {} ms", started.elapsed().as_millis());
        calls.lock().unwrap().release_later_batch = true;
        demand.join().unwrap();
        let restored = background.join().unwrap().unwrap();
        assert!(
            waiting,
            "the test must cross the 32-mebibyte working-batch boundary"
        );
        assert_eq!(restored[&first_digest.hash], first);
        assert_eq!(restored[&later_digest.hash], later);
        assert_eq!(
            completed.expect("verified output waited for an unrelated batch")[&first_digest.hash],
            first
        );
    });
    std::fs::remove_dir_all(directory).unwrap();
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
                    .add_service(
                        ContentAddressableStorageServer::new(Server { mode, calls })
                            .max_decoding_message_size(64 * 1024 * 1024),
                    )
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
