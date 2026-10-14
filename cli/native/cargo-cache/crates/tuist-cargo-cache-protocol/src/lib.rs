//! Wire types and constants shared by tuist_cargo_cache remote cache clients and servers.
//!
//! These records are protocol-owned: changing their serialized shape or a
//! framing constant is a wire-format change. Transport, authentication, local
//! storage, and adapter behavior deliberately live outside this crate.
#![deny(missing_docs)]

use serde::{Deserialize, Serialize};
use sha2::Digest as _;
use std::collections::BTreeMap;
use std::fmt;
use std::fs::File;
use std::io::Read;
use std::path::Path;

/// Major version of the HTTP cache protocol.
pub const PROTOCOL_VERSION: u8 = 1;
/// Header carrying the negotiated cache protocol version.
pub const PROTOCOL_HEADER: &str = "tuist-cargo-cache-protocol";
/// Header carrying the caller's isolated cache namespace.
pub const NAMESPACE_HEADER: &str = "tuist_cargo_cache-cache-namespace";
/// Media type for canonical [`ActionResult`] JSON records.
pub const ACTION_RESULT_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-action-result.v1+json";
/// Media type for canonical [`Directory`] JSON records.
pub const DIRECTORY_MEDIA_TYPE: &str = "application/vnd.tuist_cargo_cache.cache-directory.v1+json";
/// Media type for adapter-specific action metadata blobs.
pub const CLIENT_METADATA_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-client-metadata.v1+json";
/// Media type for task-to-action prediction manifests.
pub const TASK_ACTION_MANIFEST_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-task-action-manifest.v1+json";
/// Media type for opaque content-addressed blobs.
pub const BLOB_MEDIA_TYPE: &str = "application/octet-stream";
/// Media type for framed batches of content-addressed blobs.
pub const BLOB_PACK_MEDIA_TYPE: &str = "application/vnd.tuist_cargo_cache.cache-blob-pack.v1";
/// Media type for a JSON list of digests.
pub const DIGEST_LIST_MEDIA_TYPE: &str = "application/vnd.tuist_cargo_cache.cache-digests.v1+json";
/// Media type for a JSON batch of [`ActionResult`] records.
///
/// Each record names the action it belongs to, so the batch is unordered and
/// carries only the results a service actually holds.
pub const ACTION_RESULT_BATCH_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-action-result-batch.v1+json";
/// Media type for ephemeral, invocation-keyed compilation promises.
pub const ACTION_PROMISE_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-action-promise.v1+json";
/// Media type for the receipt describing an accepted blob-pack upload.
pub const BLOB_PACK_RECEIPT_MEDIA_TYPE: &str =
    "application/vnd.tuist_cargo_cache.cache-blob-pack-receipt.v1+json";
/// Header declaring the number of blobs in a blob pack.
pub const BLOB_PACK_BLOBS_HEADER: &str = "tuist_cargo_cache-cache-pack-blobs";
/// Header declaring the total payload bytes in a blob pack.
pub const BLOB_PACK_BYTES_HEADER: &str = "tuist_cargo_cache-cache-pack-bytes";
/// Magic prefix identifying a version-one blob pack.
pub const BLOB_PACK_MAGIC: &[u8; 8] = b"TUISTPK1";
/// Bytes before each blob pack payload: algorithm, hash, and length.
pub const BLOB_PACK_HEADER_BYTES: u64 = 1 + 32 + 8;
/// Maximum number of digests in a batch request supported by the protocol.
pub const MAX_BATCH_ITEMS: usize = 10_000;
/// Maximum predictions carried by one task action manifest.
pub const MAX_TASK_ACTION_PREDICTIONS: usize = 16 * 1024;
/// Maximum serialized adapter payload in one action prediction.
pub const MAX_ACTION_PREDICTION_PAYLOAD: usize = 256 * 1024;
/// Maximum opaque lease-token length accepted for an action promise.
pub const MAX_ACTION_PROMISE_CLAIM_BYTES: usize = 256;

/// Serialize a protocol record using the JSON Canonicalization Scheme.
pub fn canonical_json(value: &impl Serialize) -> serde_json::Result<Vec<u8>> {
    serde_json_canonicalizer::to_vec(value)
}

/// Algorithm-tagged digest and exact byte length of a cache object.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Digest {
    /// Hash algorithm name (`blake3` or `sha256`).
    pub algorithm: String,
    /// Lowercase hexadecimal hash value.
    pub hash: String,
    /// Exact uncompressed object length in bytes.
    pub size: u64,
}

impl Digest {
    /// Compute a BLAKE3 digest for in-memory bytes.
    pub fn blake3(bytes: &[u8]) -> Self {
        Self {
            algorithm: DigestAlgorithm::Blake3.into(),
            hash: blake3::hash(bytes).to_hex().to_string(),
            size: bytes.len() as u64,
        }
    }

    /// Hash a file with BLAKE3 while counting bytes in the same pass.
    pub fn blake3_file(path: &Path) -> eyre::Result<Self> {
        let (hash, size) = hash_file(path, DigestAlgorithm::Blake3)?;
        Ok(Self {
            algorithm: DigestAlgorithm::Blake3.into(),
            hash,
            size,
        })
    }

    /// Validate the algorithm and lowercase hexadecimal representation.
    pub fn validate(&self) -> eyre::Result<()> {
        self.algorithm_kind()?;
        if self.hash.len() != 64
            || !self
                .hash
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        {
            eyre::bail!("invalid remote cache digest");
        }
        Ok(())
    }

    /// Return whether `bytes` have this digest and declared length.
    pub fn matches_bytes(&self, bytes: &[u8]) -> eyre::Result<bool> {
        self.validate()?;
        if self.size != bytes.len() as u64 {
            return Ok(false);
        }
        match self.algorithm_kind()? {
            DigestAlgorithm::Blake3 => Ok(self.hash == blake3::hash(bytes).to_hex().as_str()),
            DigestAlgorithm::Sha256 => {
                let mut encoded = [0; 64];
                hex::encode_to_slice(sha2::Sha256::digest(bytes), &mut encoded)
                    .expect("a SHA-256 digest always encodes into 64 bytes");
                Ok(self.hash.as_bytes() == encoded)
            }
        }
    }

    /// Stream a file and return whether it has this digest and length.
    pub fn matches_file(&self, path: &Path) -> eyre::Result<bool> {
        self.validate()?;
        let (hash, size) = hash_file(path, self.algorithm_kind()?)?;
        Ok(self.size == size && self.hash == hash)
    }

    /// Stable storage key containing the algorithm, hash, and byte length.
    pub fn key(&self) -> String {
        format!("{}/{}/{}", self.algorithm, self.hash, self.size)
    }

    /// Parse the algorithm tag into its closed version-one enum.
    pub fn algorithm_kind(&self) -> eyre::Result<DigestAlgorithm> {
        Ok(self.algorithm.parse()?)
    }
}

/// Hash algorithms supported by protocol version one.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DigestAlgorithm {
    /// BLAKE3.
    Blake3,
    /// SHA-256.
    Sha256,
}

impl DigestAlgorithm {
    /// Lowercase name serialized on the wire and used in endpoint paths.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Blake3 => "blake3",
            Self::Sha256 => "sha256",
        }
    }
}

impl fmt::Display for DigestAlgorithm {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

impl std::str::FromStr for DigestAlgorithm {
    type Err = ParseDigestAlgorithmError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "blake3" => Ok(Self::Blake3),
            "sha256" => Ok(Self::Sha256),
            _ => Err(ParseDigestAlgorithmError),
        }
    }
}

impl From<DigestAlgorithm> for String {
    fn from(algorithm: DigestAlgorithm) -> Self {
        algorithm.as_str().into()
    }
}

/// A digest algorithm name was outside the version-one contract.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ParseDigestAlgorithmError;

impl fmt::Display for ParseDigestAlgorithmError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("unsupported remote cache digest algorithm")
    }
}

impl std::error::Error for ParseDigestAlgorithmError {}

fn hash_file(path: &Path, algorithm: DigestAlgorithm) -> eyre::Result<(String, u64)> {
    let mut file = File::open(path)?;
    let mut buffer = [0; 64 * 1024];
    let mut size = 0;
    let mut blake3 = blake3::Hasher::new();
    let mut sha256 = sha2::Sha256::new();
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        match algorithm {
            DigestAlgorithm::Blake3 => {
                blake3.update(&buffer[..count]);
            }
            DigestAlgorithm::Sha256 => {
                sha256.update(&buffer[..count]);
            }
        }
        size += count as u64;
    }
    let hash = match algorithm {
        DigestAlgorithm::Blake3 => blake3.finalize().to_hex().to_string(),
        DigestAlgorithm::Sha256 => hex::encode(sha256.finalize()),
    };
    Ok((hash, size))
}

/// A canonical action-result record referencing objects in the CAS.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionResult {
    /// Digest of the canonical action descriptor this record satisfies.
    pub action: Digest,
    /// Optional adapter metadata blob.
    #[serde(default)]
    pub metadata: Option<Digest>,
    /// Optional digest of the root [`Directory`] containing outputs.
    #[serde(default)]
    pub output_root: Option<Digest>,
    /// Action-result schema version.
    pub version: u8,
}

/// A canonical directory object stored in the CAS.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Directory {
    /// Child directory entries, sorted canonically by name.
    pub directories: Vec<DirectoryNode>,
    /// Child file entries, sorted canonically by name.
    pub files: Vec<FileNode>,
    /// Child symbolic-link entries, sorted canonically by name.
    pub symlinks: Vec<SymlinkNode>,
    /// Directory-object schema version.
    pub version: u8,
}

/// A child directory entry in a canonical cache directory.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DirectoryNode {
    /// Digest of the child [`Directory`].
    pub digest: Digest,
    /// Platform mode bits recorded for the directory.
    pub mode: u32,
    /// Single path-component name within the parent directory.
    pub name: String,
}

/// A file entry in a canonical cache directory.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FileNode {
    /// Digest of the file contents.
    pub digest: Digest,
    /// Whether the file should be restored as executable.
    pub executable: bool,
    /// Platform mode bits recorded for the file.
    pub mode: u32,
    /// Single path-component name within the parent directory.
    pub name: String,
}

/// A symbolic-link entry in a canonical cache directory.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SymlinkNode {
    /// Platform mode bits recorded for the symbolic link.
    pub mode: u32,
    /// Single path-component name within the parent directory.
    pub name: String,
    /// Link target text exactly as recorded by the producer.
    pub target: String,
}

/// Rust-specific action metadata stored alongside compiled outputs.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RustcMetadata {
    /// Metadata schema version.
    pub version: u8,
    /// Adapter-defined output kind.
    pub kind: String,
    /// Digest of captured compiler standard output.
    pub stdout: Digest,
    /// Digest of captured compiler standard error.
    pub stderr: Digest,
}

impl RustcMetadata {
    /// Whether the metadata satisfies the version-one rustc schema invariants.
    pub fn validate(&self) -> bool {
        self.version == 1
            && self.kind == "rustc"
            && self.stdout.validate().is_ok()
            && self.stderr.validate().is_ok()
    }
}

/// C and C++ action metadata stored alongside compiled objects.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CcMetadata {
    /// Metadata schema version.
    pub version: u8,
    /// Adapter-defined output kind.
    pub kind: String,
    /// Digest of captured compiler standard output.
    pub stdout: Digest,
    /// Digest of captured compiler standard error.
    pub stderr: Digest,
}

impl CcMetadata {
    /// Whether the metadata satisfies the version-one cc schema invariants.
    pub fn validate(&self) -> bool {
        self.version == 1
            && self.kind == "cc"
            && self.stdout.validate().is_ok()
            && self.stderr.validate().is_ok()
    }
}

/// Adapter-owned data needed to reconstruct an action from a prior task run.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionPrediction {
    /// Invocation digest used to locate this prediction.
    pub invocation: Digest,
    /// Full action digest produced when the prediction was recorded.
    pub action: Digest,
    /// Adapter name that owns and understands `payload`.
    pub adapter: String,
    /// Adapter-defined serialized input prediction.
    pub payload: String,
}

/// Request to join or claim one invocation-wide compilation promise.
///
/// The invocation digest lives in the endpoint URL. The adapter remains in
/// the body so a server can reject a client trying to join a promise created
/// by a different action adapter under the same digest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionPromiseJoin {
    /// Action adapter that will interpret the completed prediction.
    pub adapter: String,
}

/// State returned when a client joins an invocation-wide promise.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case", deny_unknown_fields)]
#[non_exhaustive]
pub enum ActionPromiseState {
    /// This client owns the lease and should perform the compilation.
    Claimed {
        /// Opaque bearer token required to complete this claim.
        claim: String,
    },
    /// Another client owns the lease; retry after the stated delay.
    Pending {
        /// Minimum delay before asking again.
        retry_after_ms: u64,
    },
    /// The owner published a prediction through which this client can restore.
    Complete {
        /// Prediction for reconstructing and looking up the final action key.
        prediction: ActionPrediction,
    },
}

/// Immutable completion of an invocation-wide compilation promise.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionPromiseCompletion {
    /// Opaque token returned to the client that claimed the promise.
    pub claim: String,
    /// Prediction naming the action result that was published first.
    pub prediction: ActionPrediction,
}

impl ActionPromiseJoin {
    /// Whether the join names a valid action adapter.
    pub fn validate(&self) -> eyre::Result<()> {
        if !valid_adapter_name(&self.adapter) {
            eyre::bail!("invalid action promise adapter name");
        }
        Ok(())
    }
}

impl ActionPromiseState {
    /// Check the bounds and prediction invariants of a server response.
    pub fn validate(&self) -> eyre::Result<()> {
        match self {
            Self::Claimed { claim }
                if claim.is_empty() || claim.len() > MAX_ACTION_PROMISE_CLAIM_BYTES =>
            {
                eyre::bail!("invalid action promise claim token")
            }
            Self::Complete { prediction } => prediction.validate(),
            _ => Ok(()),
        }
    }
}

impl ActionPromiseCompletion {
    /// Check the claim-token bound and completed prediction.
    pub fn validate(&self) -> eyre::Result<()> {
        if self.claim.is_empty() || self.claim.len() > MAX_ACTION_PROMISE_CLAIM_BYTES {
            eyre::bail!("invalid action promise claim token");
        }
        self.prediction.validate()
    }
}

/// Predictions associated with one stable task identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TaskActionManifest {
    /// Manifest schema version.
    pub version: u8,
    /// Stable task identity.
    pub task: String,
    /// Predicted actions, uniquely keyed by invocation digest.
    pub predictions: Vec<ActionPrediction>,
}

#[derive(Serialize)]
struct TaskActionManifestSelector<'a> {
    kind: &'static str,
    task: &'a str,
    version: u8,
}

impl TaskActionManifest {
    /// Whether the manifest satisfies the version-one wire invariants.
    pub fn validate(&self) -> bool {
        let mut invocations = std::collections::BTreeSet::new();
        self.version == 1
            && valid_task_identity(&self.task)
            && self.predictions.len() <= MAX_TASK_ACTION_PREDICTIONS
            && self.predictions.iter().all(|prediction| {
                prediction.validate().is_ok() && invocations.insert(&prediction.invocation)
            })
    }

    /// Digest selecting this task identity's action manifest.
    pub fn selector_digest(&self) -> Digest {
        Self::selector(&self.task)
            .expect("manifest task identity must be valid")
            .1
    }

    /// Canonical selector bytes and digest for a task identity.
    pub fn selector(task: &str) -> eyre::Result<(Vec<u8>, Digest)> {
        if !valid_task_identity(task) {
            eyre::bail!("invalid task action manifest identity");
        }
        let selector = canonical_json(&TaskActionManifestSelector {
            kind: "task_action_manifest",
            task,
            version: 1,
        })?;
        let digest = Digest::blake3(&selector);
        Ok((selector, digest))
    }
}

impl ActionPrediction {
    /// Check the version-one wire invariants, naming the one that fails.
    ///
    /// A rejected prediction is only ever reported to someone working out why
    /// a build stopped predicting, and "invalid" on its own tells them nothing
    /// about which of these constraints to go looking at. The message stands on
    /// its own because the agent sends callers `Display`, not the error chain.
    pub fn validate(&self) -> eyre::Result<()> {
        match self.constraint_violation() {
            Some(reason) => eyre::bail!("invalid action prediction: {reason}"),
            None => Ok(()),
        }
    }

    fn constraint_violation(&self) -> Option<String> {
        if self.action.algorithm != DigestAlgorithm::Blake3.as_str()
            || self.action.validate().is_err()
        {
            return Some("action digest is not a valid blake3 digest".into());
        }
        if self.invocation.algorithm != DigestAlgorithm::Blake3.as_str()
            || self.invocation.validate().is_err()
        {
            return Some("invocation digest is not a valid blake3 digest".into());
        }
        if self.adapter.is_empty() {
            return Some("adapter name is empty".into());
        }
        if !valid_adapter_name(&self.adapter) {
            return Some(format!(
                "adapter name {:?} is not alphanumeric, '-', or '_'",
                self.adapter
            ));
        }
        if self.payload.len() > MAX_ACTION_PREDICTION_PAYLOAD {
            return Some(format!(
                "payload is {} bytes, over the {MAX_ACTION_PREDICTION_PAYLOAD} byte limit",
                self.payload.len()
            ));
        }
        if serde_json::from_str::<serde_json::Value>(&self.payload).is_err() {
            return Some("payload is not valid JSON".into());
        }
        None
    }
}

fn valid_adapter_name(value: &str) -> bool {
    !value.is_empty()
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

fn valid_task_identity(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// Version advertised by a cache service.
///
/// Capability records are the protocol's additive surface: a server may
/// advertise fields a client does not know, so every type below stays open to
/// extension rather than requiring a major release per advertised field.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct CapabilityProtocol {
    /// Protocol major version.
    pub major: u8,
    /// Backward-compatible protocol revision.
    #[serde(default)]
    pub minor: u8,
}

impl CapabilityProtocol {
    /// A protocol version advertisement.
    pub fn new(major: u8, minor: u8) -> Self {
        Self { major, minor }
    }
}

/// Schemas supported for one action adapter.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct ActionKindCapability {
    /// Action descriptor schema version.
    pub action_schema: u8,
    /// Adapter metadata schema version.
    pub metadata_schema: u8,
}

impl ActionKindCapability {
    /// The schema pair one adapter accepts.
    pub fn new(action_schema: u8, metadata_schema: u8) -> Self {
        Self {
            action_schema,
            metadata_schema,
        }
    }
}

/// Optional server protocol features.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct CapabilityFeatures {
    /// Conditional action-manifest endpoints are available.
    #[serde(default)]
    pub action_manifests: bool,
    /// Missing-blob batch queries are available.
    #[serde(default)]
    pub batch: bool,
    /// Batched action-result lookups are available.
    ///
    /// Distinct from [`Self::batch`], which covers missing-blob queries only. A
    /// service that answered those before this feature existed advertises
    /// `batch` without implementing the action-result endpoint.
    #[serde(default)]
    pub action_batch: bool,
    /// Framed blob-pack downloads are available.
    #[serde(default)]
    pub blob_packs: bool,
    /// Framed blob-pack uploads are available.
    #[serde(default)]
    pub blob_pack_uploads: bool,
    /// Resumable uploads are available.
    #[serde(default)]
    pub resumable_uploads: bool,
    /// Delegated transfers are available.
    #[serde(default)]
    pub delegated_transfers: bool,
    /// Invocation-wide claim and promise endpoints are available.
    #[serde(default)]
    pub action_promises: bool,
}

/// Server-advertised request and object limits.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct CapabilityLimits {
    /// Maximum digests accepted by one batch request.
    #[serde(default)]
    pub max_batch_items: u64,
    /// Maximum blob size eligible for inline transfer.
    #[serde(default)]
    pub max_inline_blob_bytes: u64,
    /// Maximum size of an individual blob.
    #[serde(default)]
    pub max_blob_bytes: u64,
    /// Maximum declared payload bytes in one blob pack.
    #[serde(default)]
    pub max_pack_bytes: u64,
}

/// Cache service capabilities negotiated before optional protocol features.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub struct Capabilities {
    /// Protocol version implemented by the server.
    pub protocol: CapabilityProtocol,
    /// Digest algorithms accepted by the service.
    #[serde(default)]
    pub digest_algorithms: Vec<String>,
    /// Content codings accepted and produced by the service.
    #[serde(default)]
    pub compressors: Vec<String>,
    /// Adapter schemas accepted by the service.
    #[serde(default)]
    pub action_kinds: BTreeMap<String, ActionKindCapability>,
    /// Optional endpoint features.
    #[serde(default)]
    pub features: CapabilityFeatures,
    /// Server-enforced request limits.
    #[serde(default)]
    pub limits: CapabilityLimits,
}

impl Capabilities {
    /// A baseline advertisement for `protocol`, claiming no optional features.
    ///
    /// The remaining fields are public and assignable, so a service adds only
    /// what it actually supports.
    pub fn new(protocol: CapabilityProtocol) -> Self {
        Self {
            protocol,
            digest_algorithms: Vec::new(),
            compressors: Vec::new(),
            action_kinds: BTreeMap::new(),
            features: CapabilityFeatures::default(),
            limits: CapabilityLimits::default(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn byte_verification_checks_both_algorithms_lengths_and_invalid_digests() {
        for bytes in [b"".as_slice(), b"small record", &[0, 255, 128]] {
            for digest in [
                Digest::blake3(bytes),
                Digest {
                    algorithm: "sha256".into(),
                    hash: hex::encode(sha2::Sha256::digest(bytes)),
                    size: bytes.len() as u64,
                },
            ] {
                assert!(digest.matches_bytes(bytes).unwrap());
                let mut wrong_hash = digest.clone();
                wrong_hash.hash.replace_range(
                    ..1,
                    if digest.hash.starts_with('0') {
                        "1"
                    } else {
                        "0"
                    },
                );
                assert!(!wrong_hash.matches_bytes(bytes).unwrap());
                let mut wrong_size = digest.clone();
                wrong_size.size += 1;
                assert!(!wrong_size.matches_bytes(bytes).unwrap());
                let mut invalid = digest.clone();
                invalid.hash.replace_range(..1, "G");
                assert!(invalid.matches_bytes(bytes).is_err());
                invalid.algorithm = "unknown".into();
                assert!(invalid.matches_bytes(bytes).is_err());
            }
        }
    }

    #[test]
    fn digest_validation_is_exact() {
        let valid = Digest {
            algorithm: DigestAlgorithm::Blake3.into(),
            hash: "a".repeat(64),
            size: 42,
        };
        assert!(valid.validate().is_ok());
        assert!(
            Digest {
                hash: "A".repeat(64),
                ..valid.clone()
            }
            .validate()
            .is_err()
        );
        assert!(
            Digest {
                algorithm: "md5".into(),
                ..valid
            }
            .validate()
            .is_err()
        );
    }

    #[test]
    fn a_rejected_prediction_names_the_constraint_it_violated() {
        let digest = Digest::blake3(b"action");
        let prediction = ActionPrediction {
            invocation: digest.clone(),
            action: digest,
            adapter: "rustc".into(),
            payload: "{}".into(),
        };
        assert!(prediction.validate().is_ok());

        let reason = |prediction: ActionPrediction| {
            prediction
                .validate()
                .expect_err("the prediction violates a constraint")
                .to_string()
        };
        let oversized = ActionPrediction {
            payload: format!("\"{}\"", "p".repeat(MAX_ACTION_PREDICTION_PAYLOAD)),
            ..prediction.clone()
        };
        let oversized_len = oversized.payload.len();
        let message = reason(oversized);
        assert!(
            message.contains(&oversized_len.to_string())
                && message.contains(&MAX_ACTION_PREDICTION_PAYLOAD.to_string()),
            "the message must carry both sizes so a build log says how far over it went: {message}"
        );

        // Every message stands alone, because the agent sends callers the
        // outermost `Display` rather than the error chain.
        assert_eq!(
            reason(ActionPrediction {
                adapter: "rust c".into(),
                ..prediction.clone()
            }),
            r#"invalid action prediction: adapter name "rust c" is not alphanumeric, '-', or '_'"#
        );
        assert_eq!(
            reason(ActionPrediction {
                payload: "not json".into(),
                ..prediction.clone()
            }),
            "invalid action prediction: payload is not valid JSON"
        );
        assert_eq!(
            reason(ActionPrediction {
                action: Digest {
                    algorithm: DigestAlgorithm::Sha256.into(),
                    ..prediction.action.clone()
                },
                ..prediction
            }),
            "invalid action prediction: action digest is not a valid blake3 digest"
        );
    }

    #[test]
    fn canonical_json_is_independent_of_map_insertion_order() {
        #[derive(Serialize)]
        struct ZThenA {
            z: u8,
            a: bool,
        }

        #[derive(Serialize)]
        struct AThenZ {
            a: bool,
            z: u8,
        }

        assert_eq!(
            canonical_json(&ZThenA { z: 1, a: true }).unwrap(),
            canonical_json(&AThenZ { a: true, z: 1 }).unwrap()
        );
    }
}
