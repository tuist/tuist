// Included in proxy::tests to exercise the production private resolve/fetch paths.
mod cold_replay_benchmark {
    use super::*;
    use bazel_remote_apis::build::bazel::remote::execution::v2 as wire;
    use sha2::{Digest as _, Sha256};
    use std::pin::Pin;
    use std::sync::atomic::AtomicBool;
    use tonic::{Request, Response, Status};
    use wire::action_cache_server::{ActionCache, ActionCacheServer};
    use wire::content_addressable_storage_server::{
        ContentAddressableStorage, ContentAddressableStorageServer,
    };

    struct Server {
        actions: HashMap<String, wire::ActionResult>,
        blobs: HashMap<String, Vec<u8>>,
        snapshot: Vec<u8>,
        latency_ms: AtomicU64,
        bytes_per_second: AtomicU64,
        next_send: tokio::sync::Mutex<Instant>,
        inline: AtomicBool,
        gets: AtomicU64,
        batches: AtomicU64,
        requested_blobs: AtomicU64,
        bytes: AtomicU64,
    }

    impl Server {
        async fn throttle(&self, bytes: usize) {
            let rate = self.bytes_per_second.load(Ordering::Relaxed);
            if rate == 0 {
                return;
            }
            let finish = {
                let mut next = self.next_send.lock().await;
                *next = (*next).max(Instant::now())
                    + Duration::from_secs_f64(bytes as f64 / rate as f64);
                *next
            };
            tokio::time::sleep_until(finish.into()).await;
        }
    }

    #[derive(Clone)]
    struct RpcServer(Arc<Server>);
    impl std::ops::Deref for RpcServer {
        type Target = Server;
        fn deref(&self) -> &Server {
            &self.0
        }
    }

    #[tonic::async_trait]
    impl ActionCache for RpcServer {
        async fn get_action_result(
            &self,
            request: Request<wire::GetActionResultRequest>,
        ) -> Result<Response<wire::ActionResult>, Status> {
            self.gets.fetch_add(1, Ordering::Relaxed);
            let latency = self.latency_ms.load(Ordering::Relaxed);
            if latency > 0 {
                tokio::time::sleep(Duration::from_millis(latency)).await;
            }
            let hash = request.into_inner().action_digest.unwrap().hash;
            if hash == hash_key(reapi::SNAPSHOT_ACTION_KEY) {
                self.bytes
                    .fetch_add(self.snapshot.len() as u64, Ordering::Relaxed);
                self.throttle(self.snapshot.len()).await;
                return Ok(Response::new(wire::ActionResult {
                    output_files: vec![wire::OutputFile {
                        path: "snapshot".into(),
                        contents: self.snapshot.clone(),
                        ..Default::default()
                    }],
                    ..Default::default()
                }));
            }
            let mut result = self
                .actions
                .get(&hash)
                .cloned()
                .ok_or_else(|| Status::not_found("unknown action"))?;
            if self.inline.load(Ordering::Relaxed) {
                for file in &mut result.output_files {
                    file.contents = self.blobs[&file.digest.as_ref().unwrap().hash].clone();
                    self.bytes
                        .fetch_add(file.contents.len() as u64, Ordering::Relaxed);
                }
            }
            self.throttle(
                result
                    .output_files
                    .iter()
                    .map(|file| file.contents.len())
                    .sum(),
            )
            .await;
            Ok(Response::new(result))
        }
        async fn update_action_result(
            &self,
            _: Request<wire::UpdateActionResultRequest>,
        ) -> Result<Response<wire::ActionResult>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
    }

    #[tonic::async_trait]
    impl ContentAddressableStorage for RpcServer {
        async fn batch_read_blobs(
            &self,
            request: Request<wire::BatchReadBlobsRequest>,
        ) -> Result<Response<wire::BatchReadBlobsResponse>, Status> {
            self.batches.fetch_add(1, Ordering::Relaxed);
            let latency = self.latency_ms.load(Ordering::Relaxed);
            if latency > 0 {
                tokio::time::sleep(Duration::from_millis(latency)).await;
            }
            let responses: Vec<_> = request
                .into_inner()
                .digests
                .into_iter()
                .map(|digest| {
                    // The server has EVERY child for every advertised parent. Any
                    // extra latency or transfer is client work, not missing blobs.
                    let data = self.blobs[&digest.hash].clone();
                    self.requested_blobs.fetch_add(1, Ordering::Relaxed);
                    self.bytes.fetch_add(data.len() as u64, Ordering::Relaxed);
                    wire::batch_read_blobs_response::Response {
                        digest: Some(digest),
                        data,
                        compressor: 0,
                        status: Some(bazel_remote_apis::google::rpc::Status::default()),
                    }
                })
                .collect();
            self.throttle(responses.iter().map(|response| response.data.len()).sum())
                .await;
            Ok(Response::new(wire::BatchReadBlobsResponse { responses }))
        }
        async fn find_missing_blobs(
            &self,
            _: Request<wire::FindMissingBlobsRequest>,
        ) -> Result<Response<wire::FindMissingBlobsResponse>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
        async fn batch_update_blobs(
            &self,
            _: Request<wire::BatchUpdateBlobsRequest>,
        ) -> Result<Response<wire::BatchUpdateBlobsResponse>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
        type GetTreeStream = Pin<
            Box<
                dyn tonic::codegen::tokio_stream::Stream<
                        Item = Result<wire::GetTreeResponse, Status>,
                    > + Send,
            >,
        >;
        async fn get_tree(
            &self,
            _: Request<wire::GetTreeRequest>,
        ) -> Result<Response<Self::GetTreeStream>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
        async fn split_blob(
            &self,
            _: Request<wire::SplitBlobRequest>,
        ) -> Result<Response<wire::SplitBlobResponse>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
        async fn splice_blob(
            &self,
            _: Request<wire::SpliceBlobRequest>,
        ) -> Result<Response<wire::SpliceBlobResponse>, Status> {
            Err(Status::unimplemented("read-only benchmark"))
        }
    }

    fn hash_key(bytes: &[u8]) -> String {
        crate::analytics::hex_upper(&Sha256::digest(bytes)).to_lowercase()
    }

    fn start_server(
        server: Arc<Server>,
    ) -> (
        String,
        tokio::sync::oneshot::Sender<()>,
        std::thread::JoinHandle<()>,
    ) {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let endpoint = format!("http://{}", listener.local_addr().unwrap());
        let (stop, stopped) = tokio::sync::oneshot::channel();
        let thread = std::thread::spawn(move || {
            let runtime = tokio::runtime::Builder::new_multi_thread()
                .worker_threads(4)
                .enable_all()
                .build()
                .unwrap();
            runtime.block_on(async move {
                let listener = tokio::net::TcpListener::from_std(listener).unwrap();
                tonic::transport::Server::builder()
                    .add_service(ActionCacheServer::new(RpcServer(server.clone())))
                    .add_service(ContentAddressableStorageServer::new(RpcServer(server)))
                    .serve_with_incoming_shutdown(
                        tonic::transport::server::TcpIncoming::from(listener),
                        async {
                            let _ = stopped.await;
                        },
                    )
                    .await
                    .unwrap();
            });
        });
        (endpoint, stop, thread)
    }

    fn dataset(count: usize, source: &'static PathState) -> (Arc<Server>, Vec<Vec<u8>>) {
        let encoding_remote = test_proxy().remote_for("tuist/cold-replay-source");
        let mut actions = HashMap::new();
        let mut blobs = HashMap::new();
        let mut nodes = Vec::new();
        let mut indexes = HashMap::new();
        let mut entries = Vec::new();
        let mut keys = Vec::new();
        for action in 0..count {
            let mut outputs = Vec::new();
            for output in 0..8 {
                let mut children = Vec::new();
                for chunk in 0..4 {
                    // One output is shared across actions; the remaining 28
                    // chunks differ. Deterministic incompressible 4 KiB blobs.
                    let salt = if output == 0 { 0 } else { action };
                    let mut rng = 1 + (salt * 32 + output * 4 + chunk) as u64;
                    let data: Vec<u8> = (0..4096)
                        .map(|_| {
                            rng ^= rng << 13;
                            rng ^= rng >> 7;
                            rng ^= rng << 17;
                            rng as u8
                        })
                        .collect();
                    children.push(store_probe_object(source, &data));
                }
                outputs.push(store_probe_object_with_refs(
                    source,
                    format!("output-{output}").as_bytes(),
                    &children,
                ));
            }
            let root =
                store_probe_object_with_refs(source, format!("root-{action}").as_bytes(), &outputs);
            let (manifest, encoded) = walk_closure(source, &root, &encoding_remote).unwrap();
            assert_eq!(manifest.len(), 41);
            let mut entry = Vec::new();
            let mut files = Vec::new();
            for (node, (bytes, chunked)) in manifest.into_iter().zip(encoded) {
                let bytes = bytes.unwrap_or_else(|| {
                    encode_node_blob_accounted(source, &node.llcas_digest, &encoding_remote, Some(chunked)).unwrap().0
                });
                blobs.insert(node.blob.hash.clone(), bytes);
                let index = *indexes.entry(node.llcas_digest.clone()).or_insert_with(|| {
                    let index = nodes.len() as u32;
                    nodes.push((node.llcas_digest.clone(), node.blob.clone()));
                    index
                });
                entry.push(index);
                files.push(wire::OutputFile {
                    path: crate::analytics::hex_upper(&node.llcas_digest),
                    digest: Some(node.blob),
                    ..Default::default()
                });
            }
            let key = format!("cold-replay-key-{action}").into_bytes();
            actions.insert(
                hash_key(&key),
                wire::ActionResult {
                    output_files: files,
                    ..Default::default()
                },
            );
            entries.push((Sha256::digest(&key).to_vec(), entry));
            keys.push(key);
        }
        let mut snapshot = b"TSNP\x02".to_vec();
        snapshot.extend_from_slice(&1u64.to_le_bytes());
        snapshot.extend_from_slice(&(nodes.len() as u32).to_le_bytes());
        for (digest, blob) in nodes {
            snapshot.push(digest.len() as u8);
            snapshot.extend(digest);
            snapshot.extend(
                (0..blob.hash.len())
                    .step_by(2)
                    .map(|i| u8::from_str_radix(&blob.hash[i..i + 2], 16).unwrap()),
            );
            snapshot.extend_from_slice(&(blob.size_bytes as u64).to_le_bytes());
        }
        snapshot.extend_from_slice(&(entries.len() as u32).to_le_bytes());
        for (key, nodes) in entries {
            snapshot.extend(key);
            snapshot.extend_from_slice(&(nodes.len() as u32).to_le_bytes());
            for index in nodes {
                snapshot.extend_from_slice(&index.to_le_bytes());
            }
        }
        (
            Arc::new(Server {
                actions,
                blobs,
                snapshot,
                latency_ms: AtomicU64::new(0),
                bytes_per_second: AtomicU64::new(0),
                next_send: tokio::sync::Mutex::new(Instant::now()),
                inline: AtomicBool::new(false),
                gets: AtomicU64::new(0),
                batches: AtomicU64::new(0),
                requested_blobs: AtomicU64::new(0),
                bytes: AtomicU64::new(0),
            }),
            keys,
        )
    }

    // Like a compiler: load locally first, ask the proxy only on a miss, then
    // visit the actual references. Root-return latency alone hides missing work.
    fn replay(proxy: &'static Proxy, state: &'static PathState, root: Vec<u8>) {
        let mut todo = vec![root];
        let mut seen = HashSet::new();
        while let Some(digest) = todo.pop() {
            if !seen.insert(digest.clone()) {
                continue;
            }
            if !state.load_present(&digest) {
                assert!(proxy
                    .fetch_object(state, &state.cas_path, "bench/project", &digest)
                    .unwrap());
            }
            let guard = state.cas.read().unwrap();
            let cas = guard.unwrap();
            unsafe {
                let mut id = llcas_objectid_t { opaque: 0 };
                let mut error = std::ptr::null_mut();
                assert!(!(state.up.llcas_cas_get_objectid)(
                    cas,
                    llcas_digest_t {
                        data: digest.as_ptr(),
                        size: digest.len()
                    },
                    &mut id,
                    &mut error
                ));
                let mut loaded = llcas_loaded_object_t { opaque: 0 };
                assert_eq!(
                    (state.up.llcas_cas_load_object)(cas, id, &mut loaded, &mut error),
                    LLCAS_LOOKUP_RESULT_SUCCESS
                );
                assert!(error.is_null());
                std::hint::black_box((state.up.llcas_loaded_object_get_data)(cas, loaded));
                let refs = (state.up.llcas_loaded_object_get_refs)(cas, loaded);
                for i in 0..(state.up.llcas_object_refs_get_count)(cas, refs) {
                    let child = (state.up.llcas_object_refs_get_id)(cas, refs, i);
                    let child = (state.up.llcas_objectid_get_digest)(cas, child);
                    todo.push(std::slice::from_raw_parts(child.data, child.size).to_vec());
                }
            }
        }
        assert_eq!(seen.len(), 41);
    }

    #[test]
    #[ignore = "cold remote replay benchmark; run explicitly in release mode"]
    fn cold_remote_replay() {
        let source_dir = TempCasDir::new("cold-benchmark-source");
        let source = path_state_for(&source_dir.path());
        let (server, keys) = dataset(128, source);
        let (endpoint, stop, serving) = start_server(server.clone());
        let samples: usize = std::env::var("TUIST_CAS_BENCH_SAMPLES")
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(5);
        for (scenario, latency, inlined, snapshot, bandwidth) in [
            ("inline-local", 0, true, false, 0),
            ("inline-20ms", 20, true, false, 0),
            ("fallback-20ms", 20, false, false, 0),
            ("snapshot-local", 0, false, true, 0),
            ("snapshot-20ms", 20, false, true, 0),
            ("snapshot-60ms", 60, false, true, 0),
            ("fallback-20ms-5mib", 20, false, false, 5 * 1024 * 1024),
            ("snapshot-20ms-20mib", 20, false, true, 20 * 1024 * 1024),
        ] {
            if std::env::var("TUIST_CAS_BENCH_SCENARIO_FILTER")
                .is_ok_and(|filter| !scenario.contains(&filter))
            {
                continue;
            }
            server.latency_ms.store(latency, Ordering::Relaxed);
            server.inline.store(inlined, Ordering::Relaxed);
            server.bytes_per_second.store(bandwidth, Ordering::Relaxed);
            for sample in 0..samples {
                for counter in [
                    &server.gets,
                    &server.batches,
                    &server.requested_blobs,
                    &server.bytes,
                ] {
                    counter.store(0, Ordering::Relaxed);
                }
                let dir = TempCasDir::new(&format!("cold-{scenario}-{sample}"));
                let proxy = Proxy::new(
                    endpoint.clone(),
                    crate::token::TokenProvider::from_env(),
                    crate::upstream_path(),
                    None,
                    None,
                );
                let remote = Remote::new(
                    reapi::RemoteConfig {
                        grpc_url: endpoint.clone(),
                        instance: "project".into(),
                    },
                    crate::token::TokenProvider::from_env(),
                );
                proxy
                    .remotes
                    .lock()
                    .unwrap()
                    .insert("bench/project".into(), (0, remote.clone()));
                let state = proxy.path_state(&dir.path()).unwrap();
                let (send, recv) = std::sync::mpsc::channel();
                let recv = Arc::new(Mutex::new(recv));
                let workers: Vec<_> = (0..16)
                    .map(|_| {
                        let recv = recv.clone();
                        std::thread::spawn(move || loop {
                            let root = recv.lock().unwrap().recv();
                            match root {
                                Ok(root) => replay(proxy, state, root),
                                Err(_) => break,
                            }
                        })
                    })
                    .collect();
                let started = Instant::now();
                let snapshot = snapshot.then(|| {
                    Snapshot::decode(&remote.get_snapshot(None, None).unwrap().unwrap()).unwrap()
                });
                let resolve_started = Instant::now();
                for key in &keys {
                    send.send(
                        proxy
                            .resolve(&remote, "bench/project", state, key, snapshot.as_ref())
                            .unwrap()
                            .unwrap(),
                    )
                    .unwrap();
                }
                let resolve_ms = resolve_started.elapsed().as_secs_f64() * 1000.0;
                drop(send);
                for worker in workers {
                    worker.join().unwrap();
                }
                let replay_ms = started.elapsed().as_secs_f64() * 1000.0;
                assert!(proxy
                    .materializer
                    .drain_stop_timeout(Duration::from_secs(30))
                    .is_empty());
                let drained_ms = started.elapsed().as_secs_f64() * 1000.0;
                assert_eq!(state.stats_incomplete_closures.load(Ordering::Relaxed), 0);
                println!(
                    "COLD_BENCH {}",
                    serde_json::json!({ "scenario": scenario, "sample": sample, "keys": keys.len(), "resolve_ms": resolve_ms, "replay_ms": replay_ms, "drained_ms": drained_ms, "gets": server.gets.load(Ordering::Relaxed), "batches": server.batches.load(Ordering::Relaxed), "blob_requests": server.requested_blobs.load(Ordering::Relaxed), "wire_blob_bytes": server.bytes.load(Ordering::Relaxed), "demand_fetched": state.stats_demand_fetched.load(Ordering::Relaxed) })
                );
                // Close handles and release per-sample caches before the next
                // fresh store; Proxy intentionally has process lifetime.
                unsafe {
                    (state.up.llcas_cas_dispose)(state.cas.write().unwrap().take().unwrap());
                }
                state.pending_objects.lock().unwrap().clear();
                state.resolved.lock().unwrap().clear();
                state.publish_cache.lock().unwrap().clear();
                proxy.remotes.lock().unwrap().clear();
            }
        }
        stop.send(()).unwrap();
        serving.join().unwrap();
    }
}
