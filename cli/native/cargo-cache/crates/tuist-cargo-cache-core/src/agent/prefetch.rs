use super::*;

fn plan_blob_packs(
    missing: &BTreeMap<CacheDigest, ()>,
    limits: crate::BlobPackLimits,
) -> Vec<Vec<CacheDigest>> {
    let mut pack_candidates = missing.clone();
    let mut pack_requests = Vec::new();
    while !pack_candidates.is_empty() {
        let candidates = match blob_pack_chunk(pack_candidates.keys(), limits) {
            Ok(candidates) if !candidates.is_empty() => candidates,
            Ok(_) => break,
            Err(error) => {
                warn!("remote cache blob pack skipped: {error}");
                break;
            }
        };
        for digest in &candidates {
            pack_candidates.remove(digest);
        }
        pack_requests.push(candidates);
    }

    pack_requests
}

#[derive(Clone)]
pub(crate) struct PrefetchCandidate {
    adapter: String,
    priority: u64,
}

fn prediction_priority(prediction: &ActionPrediction) -> u64 {
    if !matches!(prediction.adapter.as_str(), "rustc" | "cc") {
        return u64::MAX;
    }
    let recorded_duration = serde_json::from_str::<CompilerTiming>(&prediction.payload)
        .ok()
        .and_then(|timing| timing.0);
    match (prediction.adapter.as_str(), recorded_duration) {
        ("rustc" | "cc", Some(duration)) => duration,
        ("rustc" | "cc", None) => 0,
        // Build-script and task predictions do not record compiler time. They
        // are few and often unlock many downstream compiler actions, so retain
        // them ahead of the capped compiler tail.
        _ => u64::MAX,
    }
}

// Ranking only needs the timing field. The already-validated adapter payload
// can contain thousands of input records; do not materialize that tree again.
struct CompilerTiming(Option<u64>);

impl<'de> serde::Deserialize<'de> for CompilerTiming {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct TimingVisitor;
        impl<'de> serde::de::Visitor<'de> for TimingVisitor {
            type Value = CompilerTiming;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("a prediction object")
            }

            fn visit_map<M: serde::de::MapAccess<'de>>(
                self,
                mut map: M,
            ) -> Result<Self::Value, M::Error> {
                let mut duration = None;
                while let Some(key) = map.next_key::<String>()? {
                    if key == "compiler_duration_ns" {
                        // Keep Value's numeric rules and last-key-wins behavior.
                        duration = map.next_value::<serde_json::Value>()?.as_u64();
                    } else {
                        map.next_value::<serde::de::IgnoredAny>()?;
                    }
                }
                Ok(CompilerTiming(duration))
            }
        }
        deserializer.deserialize_map(TimingVisitor)
    }
}

pub(crate) fn select_prefetch_actions<'a>(
    predictions: impl Iterator<Item = &'a ActionPrediction>,
) -> BTreeMap<CacheDigest, PrefetchCandidate> {
    // Keep borrowed keys and adapters until the cap has discarded the tail.
    let mut actions = BTreeMap::<&CacheDigest, (&str, u64)>::new();
    for prediction in predictions {
        let priority = prediction_priority(prediction);
        let candidate = actions
            .entry(&prediction.action)
            .or_insert((prediction.adapter.as_str(), priority));
        if priority > candidate.1 {
            *candidate = (prediction.adapter.as_str(), priority);
        }
    }
    let mut ranked = actions.into_iter().collect::<Vec<_>>();
    if ranked.len() > MAX_PREFETCH_ACTIONS {
        // The result is a map, so only membership, not rank order, is needed.
        ranked.select_nth_unstable_by(
            MAX_PREFETCH_ACTIONS,
            |(left_action, left), (right_action, right)| {
                right
                    .1
                    .cmp(&left.1)
                    .then_with(|| left_action.cmp(right_action))
            },
        );
        ranked.truncate(MAX_PREFETCH_ACTIONS);
    }
    ranked
        .into_iter()
        .map(|(action, (adapter, priority))| {
            (
                action.clone(),
                PrefetchCandidate {
                    adapter: adapter.to_owned(),
                    priority,
                },
            )
        })
        .collect()
}

fn ranked_prefetch_actions(
    actions: &BTreeMap<CacheDigest, PrefetchCandidate>,
) -> Vec<(CacheDigest, String)> {
    let mut ranked = actions
        .iter()
        .map(|(action, candidate)| {
            (
                action.clone(),
                candidate.adapter.clone(),
                candidate.priority,
            )
        })
        .collect::<Vec<_>>();
    ranked.sort_unstable_by(|(left_action, _, left), (right_action, _, right)| {
        right.cmp(left).then_with(|| left_action.cmp(right_action))
    });
    ranked
        .into_iter()
        .map(|(action, adapter, _)| (action, adapter))
        .collect()
}

fn rank_resolved_prefetch_actions(
    actions: &BTreeMap<CacheDigest, PrefetchCandidate>,
    resolved: &mut [PrefetchedAction],
) {
    resolved.sort_unstable_by(|left, right| {
        let left_priority = actions
            .get(&left.result.action)
            .map(|candidate| candidate.priority)
            .unwrap_or_default();
        let right_priority = actions
            .get(&right.result.action)
            .map(|candidate| candidate.priority)
            .unwrap_or_default();
        right_priority
            .cmp(&left_priority)
            .then_with(|| left.result.action.cmp(&right.result.action))
    });
}

impl CacheAgent {
    pub(super) fn spawn_prefetch_predictions(&self, predictions: Vec<ActionPrediction>) {
        if predictions.is_empty() || !self.remote_mode.reads() || self.remote.is_none() {
            return;
        }
        let agent = self.clone();
        let task = tokio::spawn(async move {
            agent.prefetch_predictions(predictions.iter()).await;
        });
        self.prefetch_tasks.lock().unwrap().push(task);
    }

    pub(super) async fn prefetch_predictions<'a>(
        &self,
        predictions: impl Iterator<Item = &'a ActionPrediction>,
    ) {
        if !self.remote_mode.reads() || self.remote.is_none() {
            return;
        }
        self.stats.prefetch_runs.fetch_add(1, Ordering::Relaxed);
        let _timer = AtomicDurationTimer::start(&self.stats.prefetch_duration_ns);
        let actions = select_prefetch_actions(predictions);
        // One request per predicted action is the bulk of a prefetch's latency on
        // a large workspace, so ask for them together where the server allows it.
        match self.prefetch_action_batches(&actions).await {
            Ok(true) => return,
            Ok(false) => {}
            Err(error) => {
                self.note_remote_failure();
                warn!("remote action batch lookup failed: {error}");
            }
        }
        let mut actions = ranked_prefetch_actions(&actions).into_iter();
        let mut tasks = tokio::task::JoinSet::new();
        for _ in 0..MAX_PREFETCH_TRANSFERS {
            let Some((action, adapter)) = actions.next() else {
                break;
            };
            let agent = self.clone();
            tasks.spawn(async move { agent.resolve_prefetch_action(action, adapter).await });
        }
        let mut resolved = Vec::new();
        while !tasks.is_empty() {
            let result = if resolved.is_empty() {
                tasks.join_next().await
            } else {
                match tokio::time::timeout(PREFETCH_ACTION_BATCH_DELAY, tasks.join_next()).await {
                    Ok(result) => result,
                    Err(_) => {
                        self.prefetch_resolved_actions(std::mem::take(&mut resolved))
                            .await;
                        continue;
                    }
                }
            };
            let Some(result) = result else {
                break;
            };
            match result {
                Ok(Ok(Some(action))) => resolved.push(action),
                Ok(Ok(None)) => {}
                Ok(Err(error)) => {
                    self.note_remote_failure();
                    warn!("remote action prefetch failed: {error}");
                }
                Err(error) => {
                    self.note_remote_failure();
                    warn!("remote action prefetch task failed: {error}");
                }
            }
            if let Some((action, adapter)) = actions.next() {
                let agent = self.clone();
                tasks.spawn(async move { agent.resolve_prefetch_action(action, adapter).await });
            }
            if resolved.len() == MAX_PREFETCH_ACTION_WAVE {
                self.prefetch_resolved_actions(std::mem::take(&mut resolved))
                    .await;
            }
        }
        if !resolved.is_empty() {
            self.prefetch_resolved_actions(resolved).await;
        }
    }

    /// Resolve predicted actions in batched lookups, staging what comes back.
    ///
    /// Returns whether the batch extension answered. A server without it, or one
    /// that stops answering part way through, leaves the per-action path to
    /// resolve whatever is left -- the results already staged here are memoized,
    /// so nothing is looked up twice.
    pub(super) async fn prefetch_action_batches(
        &self,
        actions: &BTreeMap<CacheDigest, PrefetchCandidate>,
    ) -> Result<bool> {
        let wanted: Vec<CacheDigest> = ranked_prefetch_actions(actions)
            .into_iter()
            .map(|(action, _)| action)
            .filter(|action| !self.action_is_staged(action))
            .collect();
        if wanted.is_empty() {
            return Ok(true);
        }
        // A warm local store needs no remote capability negotiation. Keep this
        // check ahead of the first await: on a high-latency cache, asking what
        // batch shape it supports can otherwise add a full network round trip
        // to a build that has nothing left to download.
        let Some(remote) = self.remote.as_deref() else {
            return Ok(false);
        };
        let Some(limit) = remote.action_batch_limit().await? else {
            return Ok(false);
        };
        let mut chunks: Vec<Vec<CacheDigest>> = Vec::new();
        for chunk in wanted.chunks(limit) {
            chunks.push(chunk.to_vec());
        }
        let mut lookups = stream::iter(chunks)
            .map(|chunk| async move {
                let _prefetch_permit = self.prefetch_transfers.acquire().await?;
                let _permit = self.remote_transfers.acquire().await?;
                self.stats
                    .remote_action_lookups
                    .fetch_add(1, Ordering::Relaxed);
                let _timer =
                    AtomicDurationTimer::start(&self.stats.remote_action_lookup_duration_ns);
                remote.get_action_results(&chunk).await
            })
            .buffer_unordered(MAX_PREFETCH_BATCH_LOOKUPS);
        let mut answered = true;
        let mut resolved = Vec::new();
        while let Some(lookup) = lookups.next().await {
            let results = match lookup {
                Ok(Some(results)) => results,
                // Advertised but unavailable. What is left falls back.
                Ok(None) => {
                    answered = false;
                    continue;
                }
                Err(error) => {
                    self.note_remote_failure();
                    warn!("remote action batch lookup failed: {error}");
                    answered = false;
                    continue;
                }
            };
            for result in results {
                let Some(adapter) = actions
                    .get(&result.action)
                    .map(|candidate| candidate.adapter.clone())
                else {
                    continue;
                };
                let lock = self.action_lock(&result.action);
                let _guard = lock.lock().await;
                if self.actions.find(&result.action)?.is_some() {
                    continue;
                }
                self.pending_remote_actions
                    .lock()
                    .unwrap()
                    .insert(result.action.clone(), result.clone());
                resolved.push(PrefetchedAction { adapter, result });
            }
        }
        // Finish the small metadata phase before starting any blob packs. This
        // keeps pack bookkeeping from competing with later action batches for
        // the server's database pool, and means serial batch requests do not
        // sit behind minutes of artifact transfer.
        // Batch results are unordered, so restore prediction priority before
        // dividing the output downloads into progressive waves.
        rank_resolved_prefetch_actions(actions, &mut resolved);
        while !resolved.is_empty() {
            let wave = resolved
                .drain(..resolved.len().min(MAX_PREFETCH_ACTION_WAVE))
                .collect();
            self.prefetch_resolved_actions(wave).await;
        }
        Ok(answered)
    }

    /// Whether an action's result is already local or already looked up.
    pub(super) fn action_is_staged(&self, action: &CacheDigest) -> bool {
        if self
            .pending_remote_actions
            .lock()
            .unwrap()
            .contains_key(action)
        {
            return true;
        }
        self.actions.find(action).is_ok_and(|found| found.is_some())
    }

    #[cfg(test)]
    pub(super) async fn prefetch_action(&self, action: CacheDigest, adapter: String) -> Result<()> {
        if let Some(action) = self.resolve_prefetch_action(action, adapter).await? {
            self.prefetch_resolved_actions(vec![action]).await;
        }
        Ok(())
    }

    pub(super) async fn resolve_prefetch_action(
        &self,
        action: CacheDigest,
        adapter: String,
    ) -> Result<Option<PrefetchedAction>> {
        let remote = self
            .remote
            .as_ref()
            .ok_or_else(|| eyre::eyre!("remote cache is not configured"))?;
        let result = {
            let lock = self.action_lock(&action);
            let _guard = lock.lock().await;
            if self.actions.find(&action)?.is_some() {
                return Ok(None);
            }
            if let Some(result) = self
                .pending_remote_actions
                .lock()
                .unwrap()
                .get(&action)
                .cloned()
            {
                result
            } else {
                let _prefetch_permit = self.prefetch_transfers.acquire().await?;
                let result = {
                    let _permit = self.remote_transfers.acquire().await?;
                    self.get_remote_action_result(remote, &action).await?
                };
                let Some(result) = result else {
                    return Ok(None);
                };
                self.pending_remote_actions
                    .lock()
                    .unwrap()
                    .insert(action.clone(), result.clone());
                result
            }
        };
        Ok(Some(PrefetchedAction { adapter, result }))
    }

    pub(super) fn prefetch_resolved_actions(
        &self,
        actions: Vec<PrefetchedAction>,
    ) -> BoxFuture<'_, ()> {
        self.prefetch_resolved_actions_inner(actions).boxed()
    }

    pub(super) async fn prefetch_resolved_actions_inner(&self, actions: Vec<PrefetchedAction>) {
        let Some(remote) = self.remote.as_deref() else {
            return;
        };
        if actions.is_empty() {
            return;
        }

        let mut top_level = BTreeMap::new();
        for action in &actions {
            for digest in [
                Some(&action.result.action),
                action.result.metadata.as_ref(),
                action.result.output_root.as_ref(),
            ]
            .into_iter()
            .flatten()
            {
                top_level.insert(digest.clone(), ());
            }
        }
        let mut verified = self
            .fetch_remote_blobs(
                remote,
                top_level.into_keys().collect(),
                Some(&self.prefetch_transfers),
            )
            .await;

        let mut next = BTreeMap::new();
        let mut pending_directories = BTreeMap::new();
        let mut parsed_directories = BTreeMap::new();
        let mut rustc_metadata = BTreeMap::new();
        for action in &actions {
            if action.adapter == "rustc"
                && let Some(metadata_digest) = &action.result.metadata
            {
                match verified
                    .get(metadata_digest)
                    .ok_or_else(|| eyre::eyre!("remote rustc action metadata is missing"))
                    .and_then(|path| Self::parse_rustc_metadata(path))
                {
                    Ok(metadata) => {
                        queue_prefetch_digest(&verified, &mut next, metadata.stdout.clone());
                        queue_prefetch_digest(&verified, &mut next, metadata.stderr.clone());
                        rustc_metadata.insert(metadata_digest.clone(), metadata);
                    }
                    Err(error) => warn!(
                        "remote rustc action metadata prefetch failed for {}: {error}",
                        action.result.action.hash
                    ),
                }
            }
            if let Some(output_root) = &action.result.output_root {
                pending_directories.insert(output_root.clone(), ());
            }
        }

        let mut seen_directories = BTreeMap::new();
        loop {
            let mut following = BTreeMap::new();
            let mut directory_limit_exceeded = false;
            for digest in pending_directories.into_keys() {
                following.remove(&digest);
                if seen_directories.insert(digest.clone(), ()).is_some() {
                    continue;
                }
                if seen_directories.len() > MAX_PREFETCH_DIRECTORY_OBJECTS {
                    warn!("remote action output tree is too large to prefetch");
                    following.clear();
                    break;
                }
                match verified
                    .get(&digest)
                    .ok_or_else(|| eyre::eyre!("remote action output directory is missing"))
                    .and_then(|path| Self::parse_cache_directory(path))
                {
                    Ok(directory) => {
                        for file in &directory.files {
                            queue_prefetch_digest(&verified, &mut next, file.digest.clone());
                            if next.len() >= MAX_PREFETCH_OBJECTS_PER_WAVE {
                                self.flush_prefetch_digest_batch(remote, &mut verified, &mut next)
                                    .await;
                            }
                        }
                        for child in &directory.directories {
                            if !queue_prefetch_directory(
                                &seen_directories,
                                &mut following,
                                child.digest.clone(),
                                MAX_PREFETCH_DIRECTORY_OBJECTS,
                            ) {
                                warn!("remote action output tree is too large to prefetch");
                                directory_limit_exceeded = true;
                                break;
                            }
                            queue_prefetch_digest(&verified, &mut next, child.digest.clone());
                            if next.len() >= MAX_PREFETCH_OBJECTS_PER_WAVE {
                                self.flush_prefetch_digest_batch(remote, &mut verified, &mut next)
                                    .await;
                            }
                        }
                        parsed_directories.insert(digest, directory);
                    }
                    Err(error) => warn!(
                        "remote action output directory prefetch failed for {}: {error}",
                        digest.hash
                    ),
                }
                if directory_limit_exceeded {
                    following.clear();
                    break;
                }
            }
            self.flush_prefetch_digest_batch(remote, &mut verified, &mut next)
                .await;
            if following.is_empty() {
                break;
            }
            pending_directories = following;
        }

        for action in actions {
            match Self::validate_prefetched_action(
                &action,
                &verified,
                &rustc_metadata,
                &parsed_directories,
            ) {
                Ok(()) => {
                    if let Err(error) = self.actions.store(&action.result) {
                        warn!(
                            "remote action prefetch could not publish {}: {error}",
                            action.result.action.hash
                        );
                        continue;
                    }
                    self.pending_remote_actions
                        .lock()
                        .unwrap()
                        .remove(&action.result.action);
                    self.stats
                        .prefetched_actions
                        .fetch_add(1, Ordering::Relaxed);
                }
                Err(error) => warn!(
                    "remote action prefetch was incomplete for {}: {error}",
                    action.result.action.hash
                ),
            }
        }
    }

    pub(super) async fn flush_prefetch_digest_batch(
        &self,
        remote: &RemoteCacheClient,
        verified: &mut BTreeMap<CacheDigest, PathBuf>,
        pending: &mut BTreeMap<CacheDigest, ()>,
    ) {
        if pending.is_empty() {
            return;
        }
        let digests = std::mem::take(pending).into_keys().collect();
        verified.extend(
            self.fetch_remote_blobs(remote, digests, Some(&self.prefetch_transfers))
                .await,
        );
    }

    pub(super) async fn fetch_remote_blobs(
        &self,
        remote: &RemoteCacheClient,
        digests: Vec<CacheDigest>,
        prefetch_limit: Option<&tokio::sync::Semaphore>,
    ) -> BTreeMap<CacheDigest, PathBuf> {
        let mut verified = BTreeMap::new();
        let mut missing = BTreeMap::new();
        for digest in digests {
            match self.find_verified_blob(&digest) {
                Ok(Some(path)) => {
                    verified.insert(digest, path);
                }
                Ok(None) => {
                    missing.insert(digest, ());
                }
                Err(error) => warn!(
                    "local cache blob lookup failed for {}: {error}",
                    digest.hash
                ),
            }
        }
        if missing.is_empty() {
            return verified;
        }

        let pack_limits = match remote.blob_pack_limits().await {
            Ok(Some(limits)) => Some(limits),
            Ok(None) => None,
            Err(error) => {
                warn!("remote cache blob pack negotiation failed: {error}");
                None
            }
        };
        let pack_requests =
            pack_limits.map_or_else(Vec::new, |limits| plan_blob_packs(&missing, limits));

        let mut packs = stream::iter(pack_requests)
            .map(|requested| async move {
                self.fetch_remote_blob_pack(remote, requested, prefetch_limit)
                    .await
            })
            .buffer_unordered(MAX_CONCURRENT_BLOB_PACKS);
        while let Some(blobs) = packs.next().await {
            for (digest, path) in blobs {
                missing.remove(&digest);
                verified.insert(digest, path);
            }
        }

        let mut transfers = stream::iter(missing.into_keys().map(|digest| {
            let digest_for_result = digest.clone();
            async move {
                (
                    digest_for_result,
                    self.fetch_remote_blob_with_limit(remote, &digest, prefetch_limit)
                        .await,
                )
            }
        }))
        .buffer_unordered(MAX_PREFETCH_TRANSFERS);
        while let Some((digest, result)) = transfers.next().await {
            match result {
                Ok(path) => {
                    verified.insert(digest, path);
                }
                Err(error) => warn!(
                    "remote cache blob prefetch failed for {}: {error}",
                    digest.hash
                ),
            }
        }
        verified
    }

    async fn fetch_remote_blob_pack(
        &self,
        remote: &RemoteCacheClient,
        candidates: Vec<CacheDigest>,
        prefetch_limit: Option<&tokio::sync::Semaphore>,
    ) -> Vec<(CacheDigest, PathBuf)> {
        // A pack and an individual fetch share these per-digest locks. Acquire
        // them only after this pack enters the bounded active set, then hold
        // them through ingestion so a foreground request may win against a
        // queued pack but cannot duplicate an active download.
        let mut guards = BTreeMap::new();
        for digest in candidates {
            let guard = self.write_lock(&digest).lock_owned().await;
            match self.find_verified_blob(&digest) {
                Ok(Some(_)) => {}
                Ok(None) => {
                    guards.insert(digest, guard);
                }
                Err(error) => {
                    warn!(
                        "local cache blob lookup failed for {}: {error}",
                        digest.hash
                    );
                    guards.insert(digest, guard);
                }
            }
        }
        let requested = guards.keys().cloned().collect::<Vec<_>>();
        if requested.is_empty() {
            return Vec::new();
        }
        let requested_bytes = requested
            .iter()
            .fold(0_u64, |total, digest| total.saturating_add(digest.size));
        let reservation = match self
            .reserve_remote_download_up_to(requested_bytes.min(MAX_STAGED_BLOB_PACK_BYTES))
        {
            Ok(reservation) if reservation.bytes() > 0 => reservation,
            Ok(_) => return Vec::new(),
            Err(error) => {
                warn!("remote cache blob pack skipped: {error}");
                return Vec::new();
            }
        };
        let _prefetch_permit = match prefetch_limit {
            Some(limit) => match limit.acquire().await {
                Ok(permit) => Some(permit),
                Err(error) => {
                    warn!("remote cache blob pack could not acquire prefetch limit: {error}");
                    return Vec::new();
                }
            },
            None => None,
        };
        let _transfer_permit = match self.remote_transfers.acquire().await {
            Ok(permit) => permit,
            Err(error) => {
                warn!("remote cache blob pack could not acquire transfer limit: {error}");
                return Vec::new();
            }
        };
        let transfer_started = Instant::now();
        let pack = remote
            .get_blob_pack_with_limit(
                &requested,
                self.remote_staging_dir.as_path(),
                reservation.bytes(),
            )
            .await;
        let transfer_duration_ns = duration_ns(transfer_started);
        atomic_saturating_add(
            &self.stats.remote_blob_transfer_duration_ns,
            transfer_duration_ns,
        );
        let pack = match pack {
            Ok(Some(pack)) => pack,
            Ok(None) => return Vec::new(),
            Err(error) => {
                warn!("remote cache blob pack failed; falling back to individual blobs: {error}");
                return Vec::new();
            }
        };
        reservation.commit(pack.payload_bytes);
        atomic_saturating_add(&self.stats.remote_blob_pack_requests, pack.requests);
        atomic_saturating_add(&self.stats.remote_blob_pack_blobs, pack.blob_count);
        atomic_saturating_add(&self.stats.downloaded_bytes, pack.payload_bytes);

        let mut ingests = stream::iter(pack.blobs.into_iter().map(|(digest, source)| {
            let digest_for_result = digest.clone();
            let guard = guards
                .remove(&digest)
                .expect("requested packed blob has a write lock");
            async move {
                (
                    digest_for_result,
                    self.ingest_packed_blob(digest, source, guard).await,
                )
            }
        }))
        .buffer_unordered(MAX_PREFETCH_TRANSFERS);
        let mut verified = Vec::new();
        while let Some((digest, result)) = ingests.next().await {
            match result {
                Ok(path) => verified.push((digest, path)),
                Err(error) => warn!(
                    "remote cache packed blob ingest failed for {}: {error}",
                    digest.hash
                ),
            }
        }
        verified
    }

    pub(super) async fn ingest_packed_blob(
        &self,
        digest: CacheDigest,
        source: PathBuf,
        _guard: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<PathBuf> {
        let digest_size = digest.size;
        let agent = self.clone();
        let (path, stored, cas_duration_ns) = tokio::task::spawn_blocking(move || {
            if let Some(path) = agent.find_verified_blob(&digest)? {
                return Ok::<_, eyre::Report>((path, false, 0));
            }
            let cas_started = Instant::now();
            let path = agent.cas.adopt_verified_file(&digest, &source)?;
            let cas_duration_ns = duration_ns(cas_started);
            agent.remember_verified_blob(&digest, &path);
            Ok((path, true, cas_duration_ns))
        })
        .await??;
        atomic_saturating_add(&self.stats.local_cas_write_duration_ns, cas_duration_ns);
        if stored {
            self.stats.stores.fetch_add(1, Ordering::Relaxed);
            atomic_saturating_add(&self.stats.stored_bytes, digest_size);
        }
        Ok(path)
    }

    pub(super) fn parse_rustc_metadata(path: &Path) -> Result<RustcMetadata> {
        let bytes = fs::read(path)?;
        let metadata: RustcMetadata = serde_json::from_slice(&bytes)?;
        if metadata.version != 1 || metadata.kind != "rustc" || canonical_json(&metadata)? != bytes
        {
            bail!("remote rustc action metadata is invalid");
        }
        Ok(metadata)
    }

    pub(super) fn parse_cache_directory(path: &Path) -> Result<CacheDirectory> {
        let bytes = fs::read(path)?;
        let directory: CacheDirectory = serde_json::from_slice(&bytes)?;
        if directory.version != 1 || canonical_json(&directory)? != bytes {
            bail!("remote action output directory is invalid");
        }
        Ok(directory)
    }

    #[cfg(test)]
    pub(super) fn load_cache_directory(&self, digest: &CacheDigest) -> Result<CacheDirectory> {
        let path = self
            .find_verified_blob(digest)?
            .ok_or_else(|| eyre::eyre!("remote action output directory is missing"))?;
        Self::parse_cache_directory(&path)
    }

    pub(super) fn validate_prefetched_action(
        action: &PrefetchedAction,
        verified: &BTreeMap<CacheDigest, PathBuf>,
        rustc_metadata: &BTreeMap<CacheDigest, RustcMetadata>,
        directories: &BTreeMap<CacheDigest, CacheDirectory>,
    ) -> Result<()> {
        if !verified.contains_key(&action.result.action) {
            bail!("remote action descriptor is missing");
        }
        if let Some(metadata) = &action.result.metadata {
            if action.adapter == "rustc" {
                let metadata = rustc_metadata
                    .get(metadata)
                    .ok_or_else(|| eyre::eyre!("remote rustc action metadata is missing"))?;
                for digest in [&metadata.stdout, &metadata.stderr] {
                    if !verified.contains_key(digest) {
                        bail!("remote rustc action diagnostic blob is missing");
                    }
                }
            } else if !verified.contains_key(metadata) {
                bail!("remote action metadata is missing");
            }
        }
        let mut pending = action
            .result
            .output_root
            .iter()
            .cloned()
            .collect::<Vec<_>>();
        let mut seen = BTreeMap::new();
        while let Some(digest) = pending.pop() {
            if seen.insert(digest.clone(), ()).is_some() {
                continue;
            }
            if seen.len() > MAX_PREFETCH_DIRECTORY_OBJECTS {
                bail!("remote action output tree is too large");
            }
            let directory = directories
                .get(&digest)
                .ok_or_else(|| eyre::eyre!("remote action output directory is missing"))?;
            for file in &directory.files {
                if !verified.contains_key(&file.digest) {
                    bail!("remote action output file is missing");
                }
            }
            pending.extend(
                directory
                    .directories
                    .iter()
                    .map(|directory| directory.digest.clone()),
            );
        }
        Ok(())
    }

    #[cfg(test)]
    pub(super) async fn prefetch_output_tree(
        &self,
        remote: &RemoteCacheClient,
        output_root: &CacheDigest,
    ) -> Result<()> {
        let mut pending = vec![output_root.clone()];
        let mut seen = BTreeMap::new();
        while let Some(digest) = pending.pop() {
            if seen.insert(digest.clone(), ()).is_some() {
                continue;
            }
            if seen.len() > MAX_PREFETCH_DIRECTORY_OBJECTS {
                bail!("remote action output tree is too large");
            }
            self.fetch_remote_blob_with_limit(remote, &digest, Some(&self.prefetch_transfers))
                .await?;
            let directory = self.load_cache_directory(&digest)?;
            let mut transfers = stream::iter(directory.files.into_iter().map(|file| async move {
                self.fetch_remote_blob_with_limit(
                    remote,
                    &file.digest,
                    Some(&self.prefetch_transfers),
                )
                .await
                .map(|_| ())
            }))
            .buffer_unordered(MAX_PREFETCH_TRANSFERS);
            while let Some(result) = transfers.next().await {
                result?;
            }
            pending.extend(
                directory
                    .directories
                    .into_iter()
                    .map(|directory| directory.digest),
            );
        }
        Ok(())
    }

    pub(super) async fn fetch_remote_blob(
        &self,
        remote: &RemoteCacheClient,
        digest: &CacheDigest,
    ) -> Result<PathBuf> {
        self.fetch_remote_blob_with_limit(remote, digest, None)
            .await
    }

    pub(super) async fn fetch_remote_blob_with_limit(
        &self,
        remote: &RemoteCacheClient,
        digest: &CacheDigest,
        prefetch_limit: Option<&tokio::sync::Semaphore>,
    ) -> Result<PathBuf> {
        let lock = self.write_lock(digest);
        let _guard = lock.lock().await;
        if let Some(path) = self.find_verified_blob(digest)? {
            return Ok(path);
        }
        let _prefetch_permit = match prefetch_limit {
            Some(limit) => Some(limit.acquire().await?),
            None => None,
        };
        let _permit = self.remote_transfers.acquire().await?;
        let reservation = self.reserve_remote_download(digest.size)?;
        self.stats
            .remote_blob_requests
            .fetch_add(1, Ordering::Relaxed);
        let transfer_timer =
            AtomicDurationTimer::start(&self.stats.remote_blob_transfer_duration_ns);
        let temporary = remote
            .get_blob_file(digest, self.remote_staging_dir.as_path())
            .await?;
        drop(transfer_timer);
        let _cas_timer = AtomicDurationTimer::start(&self.stats.local_cas_write_duration_ns);
        let path = self.cas.store_verified_file(digest, temporary.path())?;
        reservation.commit(digest.size);
        self.remember_verified_blob(digest, &path);
        self.stats.stores.fetch_add(1, Ordering::Relaxed);
        self.stats
            .stored_bytes
            .fetch_add(digest.size, Ordering::Relaxed);
        self.stats
            .downloaded_bytes
            .fetch_add(digest.size, Ordering::Relaxed);
        Ok(path)
    }
}

#[cfg(test)]
mod selection_tests {
    use super::*;

    fn prediction(index: usize, duration: u64) -> ActionPrediction {
        ActionPrediction {
            invocation: CacheDigest::blake3(format!("invocation-{index}").as_bytes()),
            action: CacheDigest::blake3(format!("action-{index}").as_bytes()),
            adapter: "rustc".into(),
            payload: serde_json::json!({ "compiler_duration_ns": duration }).to_string(),
        }
    }

    #[test]
    fn projected_priority_preserves_value_numeric_and_duplicate_key_rules() {
        for payload in [
            r#"{}"#,
            r#"[]"#,
            r#"null"#,
            r#"17"#,
            r#"{"compiler_duration_ns":0}"#,
            r#"{"compiler_duration_ns":18446744073709551615}"#,
            r#"{"compiler_duration_ns":18446744073709551616}"#,
            r#"{"compiler_duration_ns":-1}"#,
            r#"{"compiler_duration_ns":1.0}"#,
            r#"{"compiler_duration_ns":"123"}"#,
            r#"{"compiler_duration_ns":null}"#,
            r#"{"compiler_duration_ns":[],"inputs":[{"nested":[1,true,null]}]}"#,
            r#"{"compiler_duration_ns":10,"compiler_duration_ns":20}"#,
            r#"{"compiler_duration_ns":10,"compiler_duration_ns":null}"#,
            r#"{"compiler_duration_ns":10,"inputs":[}"#,
            r#"{"compiler_duration_ns":10} trailing"#,
            r#"{"inputs":{"compiler_duration_ns":99},"compiler_duration_ns":10}"#,
            r#"{"compiler_duration_\u006es":10}"#,
        ] {
            let mut record = prediction(0, 0);
            record.payload = payload.into();
            let expected = serde_json::from_str::<serde_json::Value>(payload)
                .ok()
                .and_then(|value| value.get("compiler_duration_ns")?.as_u64())
                .unwrap_or(0);
            assert_eq!(prediction_priority(&record), expected, "{payload}");
        }
        let mut task = prediction(0, 0);
        task.adapter = "task".into();
        task.payload = "not json".into();
        assert_eq!(prediction_priority(&task), u64::MAX);
    }

    #[test]
    fn prefetch_selection_keeps_the_most_expensive_predictions() {
        let predictions = (0..MAX_PREFETCH_ACTIONS + 8)
            .map(|index| prediction(index, index as u64))
            .collect::<Vec<_>>();

        let selected = select_prefetch_actions(predictions.iter());

        assert_eq!(selected.len(), MAX_PREFETCH_ACTIONS);
        for prediction in predictions.iter().take(8) {
            assert!(!selected.contains_key(&prediction.action));
        }
        for prediction in predictions.iter().skip(8) {
            assert!(selected.contains_key(&prediction.action));
        }
    }

    #[test]
    fn non_rustc_predictions_are_not_starved_by_the_rustc_cap() {
        let mut predictions = (0..MAX_PREFETCH_ACTIONS)
            .map(|index| prediction(index, u64::MAX - 1))
            .collect::<Vec<_>>();
        let task = ActionPrediction {
            invocation: CacheDigest::blake3(b"task invocation"),
            action: CacheDigest::blake3(b"task action"),
            adapter: "task".into(),
            payload: "{}".into(),
        };
        predictions.push(task.clone());

        let selected = select_prefetch_actions(predictions.iter());

        assert_eq!(selected.len(), MAX_PREFETCH_ACTIONS);
        assert!(selected.contains_key(&task.action));
    }

    #[test]
    fn unordered_batch_results_are_restored_to_prediction_priority() {
        let predictions = (0..MAX_PREFETCH_ACTION_WAVE + 2)
            .map(|index| prediction(index, index as u64))
            .collect::<Vec<_>>();
        let actions = select_prefetch_actions(predictions.iter());
        let mut resolved = predictions
            .iter()
            .map(|prediction| PrefetchedAction {
                adapter: prediction.adapter.clone(),
                result: RemoteActionResult {
                    action: prediction.action.clone(),
                    metadata: None,
                    output_root: None,
                    version: 1,
                },
            })
            .collect::<Vec<_>>();

        rank_resolved_prefetch_actions(&actions, &mut resolved);

        let expected = predictions
            .iter()
            .rev()
            .map(|prediction| &prediction.action)
            .collect::<Vec<_>>();
        assert_eq!(
            resolved
                .iter()
                .map(|action| &action.result.action)
                .collect::<Vec<_>>(),
            expected
        );
    }
}

#[cfg(test)]
mod priority_benchmark {
    use super::*;
    #[test]
    #[ignore = "manual performance measurement; run in release mode"]
    fn benchmark_prefetch_priority() {
        let inputs: Vec<_> = (0_u64..256)
            .map(|index| {
                serde_json::json!({
                    "path": format!("/workspace/include/header-{index}.h"),
                    "digest": CacheDigest::blake3(&index.to_le_bytes()),
                })
            })
            .collect();
        for count in [1000_usize, 4096] {
            // Build distinct records and allocate each payload outside timing.
            let predictions: Vec<_> = (0..count)
                .map(|index| ActionPrediction {
                    invocation: CacheDigest::blake3(format!("invocation-{index}").as_bytes()),
                    action: CacheDigest::blake3(format!("action-{index}").as_bytes()),
                    adapter: "cc".into(),
                    payload: serde_json::json!({
                        "compiler_duration_ns": index as u64 + 1,
                        "source": format!("/workspace/src/unit-{index}.c"),
                        "inputs": inputs,
                    })
                    .to_string(),
                })
                .collect();
            let expected: BTreeMap<_, _> = predictions
                .iter()
                .enumerate()
                .rev()
                .take(MAX_PREFETCH_ACTIONS)
                .map(|(index, prediction)| (&prediction.action, index as u64 + 1))
                .collect();
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = std::time::Instant::now();
                let selected = select_prefetch_actions(std::hint::black_box(&predictions).iter());
                samples.push(start.elapsed().as_secs_f64() * 1e3);
                assert_eq!(
                    selected
                        .iter()
                        .map(|(action, candidate)| (action, candidate.priority))
                        .collect::<BTreeMap<_, _>>(),
                    expected
                );
                std::hint::black_box(selected);
            }
            samples.sort_by(f64::total_cmp);
            eprintln!(
                "select {count} distinct predictions, 256 inputs each: median {:.3} ms, range {:.3}..{:.3} ms",
                samples[3], samples[0], samples[6]
            );
        }
    }
}

#[cfg(test)]
mod pack_planning_tests {
    use super::*;
    #[test]
    fn pack_planning_keeps_order_and_limits_while_leaving_large_blobs_for_single_gets() {
        let mut missing = BTreeMap::new();
        for index in 0_usize..23 {
            let mut digest = CacheDigest::blake3(&index.to_le_bytes());
            digest.size = if index % 3 == 0 { 200 } else { 30 };
            missing.insert(digest, ());
        }
        for max_items in [1, 3, 10] {
            let packs = plan_blob_packs(
                &missing,
                crate::BlobPackLimits {
                    max_items,
                    max_bytes: 100,
                },
            );
            assert!(packs.iter().all(|pack| !pack.is_empty()
                && pack.len() <= max_items
                && pack.iter().map(|d| d.size).sum::<u64>() <= 100));
            assert_eq!(
                packs.iter().flatten().collect::<Vec<_>>(),
                missing.keys().filter(|d| d.size <= 100).collect::<Vec<_>>()
            );
        }
        let limits = crate::BlobPackLimits {
            max_items: 10,
            max_bytes: 1,
        };
        assert!(plan_blob_packs(&missing, limits).is_empty());
        assert!(plan_blob_packs(&BTreeMap::new(), limits).is_empty());
    }

    #[test]
    #[ignore = "manual performance measurement; run in release mode"]
    fn benchmark_pack_planning() {
        for count in [1000_usize, 10000] {
            let missing: BTreeMap<_, _> = (0..count)
                .map(|index| (CacheDigest::blake3(&index.to_le_bytes()), ()))
                .collect();
            let limits = crate::BlobPackLimits {
                max_items: 100,
                max_bytes: 1024 * 1024,
            };
            let mut samples = Vec::new();
            for _ in 0..7 {
                let start = std::time::Instant::now();
                let packs = plan_blob_packs(&missing, limits);
                samples.push(start.elapsed().as_secs_f64() * 1e3);
                assert_eq!(packs.iter().map(Vec::len).sum::<usize>(), count);
                std::hint::black_box(packs);
            }
            samples.sort_by(f64::total_cmp);
            eprintln!(
                "{count} candidates, 100 per pack: median {:.3} ms, range {:.3}..{:.3} ms",
                samples[3], samples[0], samples[6]
            );
        }
    }
}

#[cfg(test)]
mod selection_index_tests {
    use super::*;
    fn reference_selection<'a>(
        predictions: impl Iterator<Item = &'a ActionPrediction>,
    ) -> BTreeMap<CacheDigest, PrefetchCandidate> {
        let mut actions = BTreeMap::<CacheDigest, PrefetchCandidate>::new();
        for prediction in predictions {
            let priority = prediction_priority(prediction);
            let candidate =
                actions
                    .entry(prediction.action.clone())
                    .or_insert_with(|| PrefetchCandidate {
                        adapter: prediction.adapter.clone(),
                        priority,
                    });
            if priority > candidate.priority {
                candidate.adapter.clone_from(&prediction.adapter);
                candidate.priority = priority;
            }
        }
        if actions.len() <= MAX_PREFETCH_ACTIONS {
            return actions;
        }
        let mut ranked = actions.into_iter().collect::<Vec<_>>();
        ranked.sort_unstable_by(|(left_action, left), (right_action, right)| {
            right
                .priority
                .cmp(&left.priority)
                .then_with(|| left_action.cmp(right_action))
        });
        ranked.truncate(MAX_PREFETCH_ACTIONS);
        ranked.into_iter().collect()
    }

    fn fixture(count: usize) -> Vec<ActionPrediction> {
        (0..count)
            .map(|index| ActionPrediction {
                invocation: CacheDigest::blake3(format!("invocation-{index}").as_bytes()),
                action: CacheDigest::blake3(
                    format!("action-{}", index % (count / 2 + 1)).as_bytes(),
                ),
                adapter: if index % 7 == 0 {
                    "task"
                } else if index % 3 == 0 {
                    "cc"
                } else {
                    "rustc"
                }
                .into(),
                payload: format!(r#"{{"compiler_duration_ns":{}}}"#, index % 31),
            })
            .collect()
    }

    fn comparable(
        actions: &BTreeMap<CacheDigest, PrefetchCandidate>,
    ) -> Vec<(&CacheDigest, &str, u64)> {
        actions
            .iter()
            .map(|(action, candidate)| (action, candidate.adapter.as_str(), candidate.priority))
            .collect()
    }

    #[test]
    fn borrowed_selection_preserves_duplicate_winners_and_cap_ties() {
        for count in [0, 1, 1024, 2046, 2048, 4096, 16384] {
            let mut predictions = fixture(count);
            for _ in 0..2 {
                assert_eq!(
                    comparable(&select_prefetch_actions(predictions.iter())),
                    comparable(&reference_selection(predictions.iter()))
                );
                predictions.reverse();
            }
        }
    }

    #[test]
    #[ignore = "manual performance measurement; run in release mode"]
    fn benchmark_selection_index() {
        for count in [1024, 4096, 16384] {
            let predictions = fixture(count);
            let mut before = Vec::new();
            let mut after = Vec::new();
            for round in 0..15 {
                for optimized in if round % 2 == 0 {
                    [false, true]
                } else {
                    [true, false]
                } {
                    let start = std::time::Instant::now();
                    for _ in 0..20 {
                        let selected = if optimized {
                            select_prefetch_actions(std::hint::black_box(&predictions).iter())
                        } else {
                            reference_selection(std::hint::black_box(&predictions).iter())
                        };
                        std::hint::black_box(selected);
                    }
                    let sample = start.elapsed().as_secs_f64() * 1e3 / 20.0;
                    if optimized {
                        after.push(sample);
                    } else {
                        before.push(sample);
                    }
                }
            }
            before.sort_by(f64::total_cmp);
            after.sort_by(f64::total_cmp);
            eprintln!(
                "{count} predictions with duplicate actions: before {:.3} ms, after {:.3} ms",
                before[7], after[7]
            );
        }
    }
}
