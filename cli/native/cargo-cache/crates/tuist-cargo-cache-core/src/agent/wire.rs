use super::{FileDigestResolution, FileDigestScope, FileIdentity, RecordedFileDigest};
use crate::{ActionPrediction, CacheDigest, RemoteActionResult};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;

/// Wire protocol version used between an in-process cache agent and its shims.
pub const AGENT_PROTOCOL_VERSION: u8 = 11;
/// Largest single protocol request the agent will read.
///
/// Requests are small JSON objects; the largest legitimate ones carry an output
/// tree or a batch of digests, which stay far below this.
pub(super) const MAX_REQUEST_BYTES: usize = 16 * 1024 * 1024;

/// A file as a probe found it: absent, or present with a length and
/// modification time. Length alone would miss a rewrite that kept the size.
///
/// Described by the shim at the moment it reads the file, not by the agent
/// afterwards, so an executable replaced while its probe ran cannot be
/// recorded under the replacement's identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinnedFile {
    /// The file, absent or present.
    pub path: PathBuf,
    /// What was there, or `None` for nothing.
    pub state: Option<PinnedState>,
}

/// What a present pinned file looked like: enough to notice it being
/// written, replaced, or made executable, without reading it.
///
/// Length and modification time alone would miss a replacement of the same
/// length whose timestamp was preserved, and a `chmod +x`, which touches
/// neither. So the inode says whether it is the same file, the change time,
/// which the kernel sets on every write, rename and permission change and
/// which no program can set back, says whether it was touched, and the mode
/// says whether it can run. Windows has no change time or inode to offer
/// through the standard library; its creation time and attributes stand in.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PinnedState {
    /// Length in bytes.
    pub len: u64,
    /// Modification time, seconds since the Unix epoch.
    pub modified_secs: u64,
    /// Modification time, nanoseconds past `modified_secs`.
    pub modified_nanos: u32,
    /// Change time on Unix, creation time on Windows, seconds since the
    /// Unix epoch.
    pub changed_secs: u64,
    /// Nanoseconds past `changed_secs`.
    pub changed_nanos: u32,
    /// The inode on Unix; zero on Windows.
    pub inode: u64,
    /// Permission bits on Unix, file attributes on Windows.
    pub mode: u32,
}

impl PinnedFile {
    /// Describe `path` as it is now, or nothing when the filesystem cannot
    /// say enough about it to notice a change later.
    pub fn describe(path: impl Into<PathBuf>) -> Option<Self> {
        let path = path.into();
        let state = match std::fs::metadata(&path) {
            Ok(metadata) => Some(PinnedState::of(&metadata)?),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(_) => return None,
        };
        Some(Self { path, state })
    }

    /// Whether the file is still as this pin describes it.
    pub fn holds(&self) -> bool {
        PinnedFile::describe(self.path.clone()).as_ref() == Some(self)
    }
}

impl PinnedState {
    #[cfg(unix)]
    fn of(metadata: &std::fs::Metadata) -> Option<Self> {
        use std::os::unix::fs::MetadataExt as _;
        let modified = metadata
            .modified()
            .ok()?
            .duration_since(std::time::SystemTime::UNIX_EPOCH)
            .ok()?;
        Some(Self {
            len: metadata.len(),
            modified_secs: modified.as_secs(),
            modified_nanos: modified.subsec_nanos(),
            changed_secs: u64::try_from(metadata.ctime()).ok()?,
            changed_nanos: u32::try_from(metadata.ctime_nsec()).ok()?,
            inode: metadata.ino(),
            mode: metadata.mode(),
        })
    }

    #[cfg(windows)]
    fn of(metadata: &std::fs::Metadata) -> Option<Self> {
        use std::os::windows::fs::MetadataExt as _;
        let modified = metadata
            .modified()
            .ok()?
            .duration_since(std::time::SystemTime::UNIX_EPOCH)
            .ok()?;
        let created = metadata
            .created()
            .ok()?
            .duration_since(std::time::SystemTime::UNIX_EPOCH)
            .ok()?;
        Some(Self {
            len: metadata.len(),
            modified_secs: modified.as_secs(),
            modified_nanos: modified.subsec_nanos(),
            changed_secs: created.as_secs(),
            changed_nanos: created.subsec_nanos(),
            inode: 0,
            mode: metadata.file_attributes(),
        })
    }

    #[cfg(not(any(unix, windows)))]
    fn of(_metadata: &std::fs::Metadata) -> Option<Self> {
        None
    }
}

/// A request accepted by the task-scoped cache agent.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AgentRequest {
    /// Negotiate protocol and application versions.
    Hello {
        /// Agent protocol version understood by the caller.
        protocol: u8,
        /// Human-readable tuist_cargo_cache client version.
        client_version: String,
    },
    /// Begin a prediction-manifest run for a stable Cargo or task identity.
    BeginTask {
        /// Stable 64-character lowercase hexadecimal task identity.
        task: String,
    },
    /// Commit predictions collected by an earlier [`Self::BeginTask`].
    CommitTask {
        /// Opaque run identifier returned by the agent.
        run: String,
    },
    /// Resolve a blob to a session-verified local CAS path.
    FindBlob {
        /// Blob to resolve.
        digest: CacheDigest,
    },
    /// Resolve blobs to session-verified local CAS paths.
    FindBlobs {
        /// Blobs to resolve, preserving request order in the response.
        digests: Vec<CacheDigest>,
    },
    /// Import a file into the local content-addressed store.
    StoreBlob {
        /// Digest the source must match.
        digest: CacheDigest,
        /// File to verify and import.
        source: PathBuf,
    },
    /// Look up an action-result record.
    FindActionResult {
        /// Action digest to resolve.
        action: CacheDigest,
    },
    /// Account for a successfully restored cache hit.
    RecordActionHit {
        /// Action that supplied the outputs.
        action: CacheDigest,
        /// Restoration work performed by the adapter.
        restore: RestoreStats,
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
    },
    /// A compilation the adapter declined to cache, grouped by reason.
    RecordBypass {
        /// Stable, low-cardinality bypass-reason name.
        kind: String,
    },
    /// A compilation the adapter could not look up, having no key to look up
    /// with. Distinct from a bypass: these are cached once compiled.
    RecordUnconsulted,
    /// Account for one real compiler invocation performed by the adapter.
    RecordCompilerInvocation {
        /// Stable outcome category: `miss`, `unconsulted`, `bypass` or
        /// `verification`.
        ///
        /// A compilation the adapter deliberately ran with incremental state
        /// instead of publishing reports `incremental-miss` or
        /// `incremental-unconsulted`, saying both what its lookup did and that
        /// its result was withheld. The agent counts those separately; a bare
        /// `incremental` is no longer an outcome, because it could not say
        /// whether the cache had been consulted.
        outcome: String,
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
        /// Wall time spent running the compiler.
        duration_ns: u64,
    },
    /// Account for a cache hit that was rebuilt for correctness verification.
    RecordActionVerification {
        /// Whether rebuilt and cached outputs matched.
        matched: bool,
        /// Restoration work performed before rebuilding.
        restore: RestoreStats,
    },
    /// Store an action-result record locally and enqueue remote publication.
    StoreActionResult {
        /// Action-result record to store.
        result: RemoteActionResult,
    },
    /// Find an earlier input prediction for a task and invocation.
    FindActionPrediction {
        /// Stable task identity.
        task: String,
        /// Digest of the compiler invocation without discovered inputs.
        invocation: CacheDigest,
    },
    /// Record an input prediction after a successful compilation.
    RecordActionPrediction {
        /// Stable task identity.
        task: String,
        /// Adapter-owned prediction record.
        prediction: ActionPrediction,
    },
    /// Find cached identity output for an executable and environment.
    FindExecutableIdentity {
        /// Executable whose identity command would run.
        executable: PathBuf,
        /// Environment variables affecting identity output.
        environment: BTreeMap<String, Option<String>>,
    },
    /// Cache identity output for an executable and environment.
    StoreExecutableIdentity {
        /// Executable whose identity command ran.
        executable: PathBuf,
        /// Environment variables affecting identity output.
        environment: BTreeMap<String, Option<String>>,
        /// Captured identity-command standard output.
        stdout: Vec<u8>,
        /// Files the probe read, as they were when it read them, which pin
        /// the output beyond this session so the next one can skip the
        /// probe. Empty keeps the identity for this session only.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        pins: Vec<PinnedFile>,
    },
    /// Surface a shim diagnostic through the session that owns the build.
    ///
    /// A shim must not print diagnostics itself: its stderr belongs to the
    /// compiler it stands in for, and build scripts read that stream as part
    /// of the compiler's answer -- cc-rs treats any stderr output from a flag
    /// probe as "unsupported", which changes the flags of every compilation
    /// that follows and, with them, every action key the build produces.
    ///
    /// Appended rather than grouped with the other `Record*` requests it
    /// belongs beside: these variants carry no `repr`, so inserting one moves
    /// the discriminant of every variant after it, and a break nobody asked
    /// for is worth less than the grouping.
    RecordWarning {
        /// Human-readable single-line diagnostic.
        message: String,
    },
    /// Find session-recorded digests for files with these identities.
    FindFileDigests {
        /// What the recorded digests may stand in for.
        scope: FileDigestScope,
        /// File identities to resolve, preserving request order in the
        /// response.
        files: Vec<FileIdentity>,
    },
    /// Record digests of files a shim hashed or wrote this session.
    RecordFileDigests {
        /// What the recorded digests may stand in for.
        scope: FileDigestScope,
        /// Hashed files and the identities their digests describe.
        entries: Vec<RecordedFileDigest>,
    },
    /// Join or claim an invocation-wide promise through the cache server.
    JoinActionPromise {
        /// Adapter that owns the invocation and prediction payload.
        adapter: String,
        /// Digest of the compiler invocation before input discovery.
        invocation: CacheDigest,
    },
    /// Fulfill a claimed promise after its action result is remotely durable.
    CompleteActionPromise {
        /// Opaque claim token returned by [`Self::JoinActionPromise`].
        claim: String,
        /// Prediction through which waiters reconstruct the final action key.
        prediction: ActionPrediction,
    },
    /// Resolve file digests, coalescing concurrent reads through the agent.
    ResolveFileDigests {
        /// What the digest and any accompanying validation may stand in for.
        scope: FileDigestScope,
        /// File identities to resolve, preserving request order.
        files: Vec<FileIdentity>,
    },
    /// Record exclusive wrapper phase durations and bounded trace spans.
    RecordWrapperTiming {
        /// Completed invocation timings.
        timing: WrapperTiming,
    },
    /// Surface a fatal shim diagnostic through the session that owns the build.
    ///
    /// This is appended to preserve every existing request variant and wire
    /// shape while allowing a caller to distinguish fatal acknowledgement from
    /// [`Self::RecordWarning`] and fall back locally when it is not accepted.
    RecordError {
        /// Human-readable single-line diagnostic.
        message: String,
    },
    /// Emit a routine shim log through the owning session's logger.
    /// Filtering uses the original target; these records never consume the
    /// warning/error allowance or enter compiler output.
    RecordDebug {
        /// Original logging module target.
        target: String,
        /// Human-readable single-line message.
        message: String,
    },
}

/// One wrapper invocation, independent of its cache hit/miss accounting.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct WrapperTiming {
    /// Compiler adapter, such as rustc or cc.
    pub adapter: String,
    /// Crate or source name, when known.
    pub unit: Option<String>,
    /// Wrapper process, used as the trace lane.
    pub pid: u32,
    /// Wall-clock start in microseconds since the Unix epoch.
    pub start_us: u64,
    /// Monotonic elapsed time, excluding telemetry delivery.
    pub duration_ns: u64,
    /// Exclusive durations; nested work is subtracted from its parent.
    pub phases_ns: std::collections::BTreeMap<String, u64>,
    /// Nested spans relative to this wrapper's start, capped at 512.
    pub spans: Vec<WrapperSpan>,
    /// The build unit this invocation produced, when it can be identified.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit_id: Option<String>,
    /// Units whose outputs this invocation consumed, by [`Self::unit_id`].
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependencies: Vec<String>,
}

/// A trace interval inside one wrapper process.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct WrapperSpan {
    /// Phase name.
    pub name: String,
    /// Monotonic offset from wrapper entry.
    pub start_ns: u64,
    /// Inclusive elapsed time.
    pub duration_ns: u64,
}

/// Local output restoration work performed by one action-cache adapter hit.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RestoreStats {
    /// Cumulative time spent materializing and validating output files.
    pub duration_ns: u64,
    /// Compiler wall time recorded when this action was originally produced.
    /// Zero means no timing hint was available.
    pub avoided_compiler_duration_ns: u64,
    /// Number of compiler output files restored.
    pub output_files: u64,
    /// Declared size of compiler output files restored.
    pub output_bytes: u64,
    /// Number of restored output files that share data blocks with the CAS.
    pub reflinked_output_files: u64,
    /// Declared size of restored outputs that share data blocks with the CAS.
    pub reflinked_output_bytes: u64,
    /// Number of restored output files that share an inode with the CAS blob.
    pub hardlinked_output_files: u64,
    /// Declared size of restored outputs that share an inode with the CAS blob.
    pub hardlinked_output_bytes: u64,
    /// Number of restored output files that required a byte-for-byte copy.
    pub copied_output_files: u64,
    /// Declared size of restored outputs that required a byte-for-byte copy.
    pub copied_output_bytes: u64,
    /// Number of output files already in place with the cached contents, kept
    /// rather than rewritten.
    pub reused_output_files: u64,
    /// Declared size of outputs kept in place rather than rewritten.
    pub reused_output_bytes: u64,
}

/// One accounted cache decision, as it happens.
///
/// The agent already folds every one of these into [`AgentStats`]; an observer
/// sees the same decisions individually, before that summing loses the crate
/// they belong to. Delivered synchronously from the request handler, so an
/// observer that blocks slows the build it is watching.
#[derive(Debug, Clone)]
#[non_exhaustive]
pub enum AgentEvent {
    /// An invocation completed its wrapper instrumentation.
    WrapperTiming {
        /// Completed invocation timings.
        timing: WrapperTiming,
    },
    /// An action's outputs were restored from cache.
    ActionHit {
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
        /// Restoration work performed by the adapter.
        restore: RestoreStats,
    },
    /// A compilation the adapter declined to cache.
    Bypass {
        /// Stable, low-cardinality bypass-reason name.
        kind: String,
    },
    /// A compilation no lookup was possible for.
    Unconsulted,
    /// A compilation the adapter declined to cache, and the compiler run that
    /// followed.
    ///
    /// Emitted in place of [`Self::Bypass`] and a `bypass`
    /// [`Self::CompilerInvocation`] when a shim reports both over one
    /// connection, so the reason arrives with the crate and time it cost.
    BypassedCompilation {
        /// Stable, low-cardinality bypass-reason name.
        kind: String,
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
        /// Wall time spent running the compiler.
        duration_ns: u64,
    },
    /// A real compiler invocation ran.
    CompilerInvocation {
        /// Stable outcome category such as `miss`, `unconsulted`, or `bypass`.
        outcome: String,
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
        /// Wall time spent running the compiler.
        duration_ns: u64,
    },
    /// A hit was rebuilt to verify it.
    Verification {
        /// Whether rebuilt and cached outputs matched.
        matched: bool,
        /// Restoration work performed before rebuilding.
        restore: RestoreStats,
    },
    /// A shim reported a diagnostic for the session to surface.
    Warning {
        /// Human-readable single-line diagnostic.
        message: String,
    },
    /// A shim reported a fatal diagnostic for the session to surface.
    Error {
        /// Human-readable single-line diagnostic.
        message: String,
    },
    /// Cache-key material for the action event immediately following it.
    ActionDiagnostic {
        /// Outcome of the action this describes.
        outcome: String,
        /// Compiler crate name, when the invocation supplied one.
        crate_name: Option<String>,
        /// Privacy-preserving action-key decomposition.
        diagnostic: ActionDiagnostic,
    },
}

/// A privacy-preserving decomposition of an action key.
///
/// Values are content digests rather than source or environment contents. The
/// names are enough to say what changed without copying secrets into session
/// history.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionDiagnostic {
    /// Complete action-cache key.
    pub action: CacheDigest,
    /// Non-file key components, named for display.
    pub components: BTreeMap<String, CacheDigest>,
    /// Normalized input path to content digest.
    pub inputs: BTreeMap<String, CacheDigest>,
}

/// A sink for [`AgentEvent`]s observed during one session.
pub trait AgentEventObserver: Send + Sync {
    /// Handle one event. Must not panic, and should not block.
    fn event(&self, event: AgentEvent);
}

/// A response returned by the task-scoped cache agent.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AgentResponse {
    /// Successful protocol negotiation.
    Hello {
        /// Agent protocol version.
        protocol: u8,
        /// Human-readable agent version.
        agent_version: String,
    },
    /// A task prediction run was begun.
    TaskBegun {
        /// Opaque run identifier to pass to compiler shims and commit later.
        run: String,
    },
    /// A task prediction run was committed.
    TaskCommitted,
    /// A local CAS path already verified against the requested digest.
    Blob {
        /// Verified local path, or `None` on a cache miss.
        path: Option<PathBuf>,
    },
    /// Local CAS paths already verified against the requested digests.
    Blobs {
        /// Verified local paths or misses, in request order.
        paths: Vec<Option<PathBuf>>,
    },
    /// A blob was stored locally.
    Stored {
        /// Path of the stored object in the local CAS.
        path: PathBuf,
    },
    /// Result of an action lookup.
    ActionResult {
        /// Validated action result, or `None` on a cache miss.
        result: Option<RemoteActionResult>,
    },
    /// Hit statistics were updated.
    ActionHitRecorded,
    /// Verification statistics were updated.
    ActionVerificationRecorded,
    /// Bypass statistics were updated.
    BypassRecorded,
    /// Unconsulted-compilation statistics were updated.
    UnconsultedRecorded,
    /// Compiler invocation accounting was recorded.
    CompilerInvocationRecorded,
    /// An action result was stored.
    ActionStored {
        /// Path of the stored local action-result record.
        path: PathBuf,
    },
    /// Result of an input-prediction lookup.
    ActionPrediction {
        /// Matching prediction, or `None` when none is known.
        prediction: Option<ActionPrediction>,
    },
    /// An input prediction was recorded.
    ActionPredictionRecorded,
    /// Result of an executable-identity lookup.
    ExecutableIdentity {
        /// Captured output, or `None` when no identity is cached.
        stdout: Option<Vec<u8>>,
    },
    /// The request failed without terminating the agent connection.
    Error {
        /// Human-readable failure description.
        message: String,
    },
    /// A shim diagnostic was accepted for the session to surface.
    ///
    /// Kept after `Error` so this acknowledgement remains alongside the
    /// existing diagnostic response without changing earlier variants.
    WarningRecorded,
    /// Digests recorded earlier for the requested file identities.
    FileDigests {
        /// Recorded digests or misses, in request order.
        digests: Vec<Option<CacheDigest>>,
    },
    /// File digests were recorded.
    FileDigestsRecorded,
    /// State of an optional server-wide compilation promise.
    ActionPromise {
        /// Opaque lease owned by this client, when it should compile.
        claim: Option<String>,
        /// Completed prediction, when another client compiled first.
        prediction: Option<ActionPrediction>,
    },
    /// A server-wide compilation promise was fulfilled or safely skipped.
    ActionPromiseCompleted,
    /// Digests and scope-specific validation outcomes for requested files.
    FileDigestsResolved {
        /// Resolution outcomes in request order.
        resolutions: Vec<FileDigestResolution>,
    },
    /// Wrapper phase timings were recorded.
    WrapperTimingRecorded,
    /// A fatal shim diagnostic was accepted for the session to surface.
    ///
    /// This is appended to preserve every existing response variant and wire
    /// shape while giving fatal diagnostics their own acknowledgement.
    ErrorRecorded,
    /// A debug record was accepted, including when filtered out.
    DebugRecorded,
}
