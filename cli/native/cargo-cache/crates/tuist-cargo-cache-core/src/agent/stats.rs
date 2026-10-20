use std::collections::{BTreeMap, BTreeSet};

/// Aggregate cache activity for one task session.
///
/// The agent produces these; nothing outside this crate has cause to build one.
/// Saying so keeps a new counter from being a breaking change, which is what
/// this type exists to accumulate -- reach for [`AgentStats::default`] and
/// assign the fields a test needs.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
#[non_exhaustive]
pub struct AgentStats {
    /// Cumulative exclusive wrapper durations, including an unattributed remainder.
    pub wrapper_phases_ns: BTreeMap<String, u64>,
    /// End-to-end lifetime of the task-scoped cache session.
    pub session_duration_ns: u64,
    /// Compilations that looked up an action result: each hit, miss, and
    /// verification, counted when that outcome is recorded rather than per
    /// read, so the three always add up to this.
    pub lookups: u64,
    /// Compilations no action-result lookup was possible for, because no usable
    /// action key was available.
    ///
    /// Counted separately from a miss, which is a lookup that found nothing.
    /// Both compile, but only a miss says a lookup happened.
    pub unconsulted: u64,
    /// Number of lookups that found a valid local action result.
    pub hits: u64,
    /// Compilations that kept private incremental state, so their results were
    /// not stored.
    ///
    /// Counted beside the lookup outcome rather than instead of it: these
    /// compilations both consulted the cache, or did not, and withheld their
    /// result, and a summary that reports only one of those is wrong about the
    /// other.
    pub incremental_compilations: u64,
    /// Number of newly stored content-addressed objects.
    pub stores: u64,
    /// Total size of newly stored objects.
    pub stored_bytes: u64,
    /// Number of cache hits compiled again for qualification.
    pub verifications: u64,
    /// Number of qualification builds that diverged from the cached result.
    pub divergences: u64,
    /// CAS payload bytes downloaded from the remote cache.
    pub downloaded_bytes: u64,
    /// CAS payload bytes uploaded to the remote cache.
    pub uploaded_bytes: u64,
    /// Objects published to the remote cache after the build asked for them.
    ///
    /// A store request returns once the object is in the local CAS, so the
    /// upload it implies happens off the build's critical path. This counts the
    /// blobs and action results that publication actually completed for.
    pub background_uploads: u64,
    /// Queued uploads that did not publish, having been reported and recovered
    /// from.
    pub background_upload_failures: u64,
    /// Framed requests that published several blobs at once.
    pub remote_blob_pack_uploads: u64,
    /// Blobs published through those framed requests.
    pub remote_blob_pack_upload_blobs: u64,
    /// Time the session spent waiting for queued uploads once the build ended.
    pub upload_drain_duration_ns: u64,
    /// Complete actions staged before an adapter requested them.
    pub prefetched_actions: u64,
    /// Predictions carried by the task manifest this session loaded.
    ///
    /// Zero means no earlier build left a manifest behind -- a genuinely cold
    /// start. Together with `lookups`, this is what tells a session that loaded
    /// hundreds of predictions and matched none of them apart from one that had
    /// nothing to match against; the first means the invocations changed (a
    /// compiler update does this to every one of them at once), the second that
    /// the store was empty.
    pub predictions_loaded: u64,
    /// Compilations that were not cacheable, counted by reason.
    pub bypasses: BTreeMap<String, u64>,
    /// Estimated compiler time avoided by restored action hits.
    pub avoided_compiler_duration_ns: u64,
    /// Real compiler work performed in this session, grouped by outcome.
    pub compiler: BTreeMap<String, CompilerStats>,
    /// Observed outcomes keyed by crate name and Cargo unit fingerprint.
    pub unit_outcomes: BTreeMap<String, BTreeSet<String>>,
    /// Cumulative real compiler time by crate name.
    pub slow_compilations: BTreeMap<String, u64>,
    /// Remote cache operations that failed and were degraded to a local result.
    ///
    /// A remote cache that cannot be reached, or that answers in a way this
    /// client refuses, costs hit rate rather than correctness, so every one of
    /// these is recovered from rather than raised. Counting them is what keeps a
    /// remote that is failing every request from reading as one that merely had
    /// nothing to offer.
    pub remote_failures: u64,
    /// Number of task manifest requests made to the remote cache.
    pub remote_manifest_lookups: u64,
    /// Cumulative time spent requesting remote task manifests.
    pub remote_manifest_lookup_duration_ns: u64,
    /// Number of action-result requests made to the remote cache.
    pub remote_action_lookups: u64,
    /// Cumulative time spent requesting remote action results.
    pub remote_action_lookup_duration_ns: u64,
    /// Number of blob requests made to the remote cache.
    pub remote_blob_requests: u64,
    /// Number of packed blob requests made to the remote cache.
    pub remote_blob_pack_requests: u64,
    /// Number of verified blobs received through packed responses.
    pub remote_blob_pack_blobs: u64,
    /// Cumulative time spent downloading and verifying remote blobs.
    pub remote_blob_transfer_duration_ns: u64,
    /// Cumulative time spent ingesting downloaded blobs into the local CAS.
    pub local_cas_write_duration_ns: u64,
    /// Number of speculative prefetch runs started for task manifests.
    pub prefetch_runs: u64,
    /// Cumulative wall time of speculative task-manifest prefetch runs.
    pub prefetch_duration_ns: u64,
    /// Cumulative time spent staging or materializing and validating cached outputs.
    pub materialization_duration_ns: u64,
    /// Number of compiler output files restored from action hits.
    pub restored_output_files: u64,
    /// Declared size of compiler output files restored from action hits.
    pub restored_output_bytes: u64,
    /// Number of restored output files materialized with filesystem reflinks.
    pub reflinked_output_files: u64,
    /// Declared size of outputs materialized with filesystem reflinks.
    pub reflinked_output_bytes: u64,
    /// Restored output files that share an inode with their CAS blob.
    pub hardlinked_output_files: u64,
    /// Declared size of restored outputs that share an inode with their blob.
    pub hardlinked_output_bytes: u64,
    /// Number of restored output files materialized by copying their bytes.
    pub copied_output_files: u64,
    /// Declared size of outputs materialized by copying their bytes.
    pub copied_output_bytes: u64,
    /// Number of output files kept in place, already holding the cached bytes.
    pub reused_output_files: u64,
    /// Declared size of outputs kept in place.
    pub reused_output_bytes: u64,
}

/// Count and cumulative wall time for one compiler-invocation outcome.
///
/// Non-exhaustive for the same reason as [`AgentStats`], which holds these:
/// leaving the outer bag open does not help if describing an outcome in more
/// detail still breaks the type inside it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
#[non_exhaustive]
pub struct CompilerStats {
    /// Number of compiler invocations observed.
    pub invocations: u64,
    /// Cumulative wall time spent in those invocations.
    pub duration_ns: u64,
}

impl CompilerStats {
    /// The counts observed for one outcome.
    pub fn new(invocations: u64, duration_ns: u64) -> Self {
        Self {
            invocations,
            duration_ns,
        }
    }
}
