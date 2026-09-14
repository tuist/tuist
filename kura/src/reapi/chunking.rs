use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use prost::Message;

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    constants::{MAX_INLINE_REPLICATION_BODY_BYTES, MAX_MODULE_TOTAL_BYTES},
    state::SharedState,
    store::RefreshTrigger,
    utils::blob_key,
};

pub const FAST_CDC_AVERAGE_CHUNK_BYTES: u64 = 512 * 1024;
pub const FAST_CDC_MINIMUM_CHUNK_BYTES: u64 = FAST_CDC_AVERAGE_CHUNK_BYTES / 4;
pub const FAST_CDC_MAXIMUM_CHUNK_BYTES: u64 = FAST_CDC_AVERAGE_CHUNK_BYTES * 4;
pub const MAX_CHUNKS_PER_BLOB: usize = 16_384;
pub const MAX_CHUNK_PRESENCE_PROBES_PER_REQUEST: usize = 65_536;
pub const MAX_CHUNK_PRESENCE_PROBES_PER_SNAPSHOT_SCAN: usize = 1_048_576;
const PRESENCE_BUDGET_ERROR_PREFIX: &str = "chunk presence expansion exceeds";

const RECIPE_VERSION: u32 = 1;
const RECIPE_KEY_PREFIX: &str = "blob_chunks/";

#[derive(Clone, PartialEq, Message)]
pub struct ChunkedBlobRecipe {
    #[prost(uint32, tag = "1")]
    version: u32,
    #[prost(string, tag = "2")]
    blob_hash: String,
    #[prost(uint64, tag = "3")]
    blob_size: u64,
    #[prost(enumeration = "reapi::chunking_function::Value", tag = "4")]
    chunking_function: i32,
    #[prost(message, repeated, tag = "5")]
    chunks: Vec<reapi::Digest>,
}

impl ChunkedBlobRecipe {
    pub fn new(
        blob_digest: &reapi::Digest,
        chunk_digests: Vec<reapi::Digest>,
        chunking_function: i32,
    ) -> Result<Self, String> {
        if blob_digest.size_bytes < 0 {
            return Err("blob digest size must be non-negative".into());
        }
        let recipe = Self {
            version: RECIPE_VERSION,
            blob_hash: blob_digest.hash.clone(),
            blob_size: blob_digest.size_bytes as u64,
            chunking_function,
            chunks: chunk_digests,
        };
        recipe.validate()?;
        Ok(recipe)
    }

    pub fn decode_validated(bytes: &[u8]) -> Result<Self, String> {
        let recipe = Self::decode(bytes)
            .map_err(|error| format!("failed to decode chunked blob recipe: {error}"))?;
        recipe.validate()?;
        Ok(recipe)
    }

    pub fn encode(&self) -> Vec<u8> {
        self.encode_to_vec()
    }

    pub fn blob_digest(&self) -> reapi::Digest {
        reapi::Digest {
            hash: self.blob_hash.clone(),
            size_bytes: self.blob_size as i64,
        }
    }

    pub fn blob_size(&self) -> u64 {
        self.blob_size
    }

    pub fn chunking_function_value(&self) -> i32 {
        self.chunking_function
    }

    pub fn chunks(&self) -> &[reapi::Digest] {
        &self.chunks
    }

    pub fn referenced_blob_keys(&self) -> Vec<String> {
        self.chunks
            .iter()
            .map(|digest| blob_key(&format!("{}/{}", digest.hash, digest.size_bytes)))
            .collect()
    }

    fn validate(&self) -> Result<(), String> {
        if self.version != RECIPE_VERSION {
            return Err(format!(
                "unsupported chunked blob recipe version {}",
                self.version
            ));
        }
        validate_sha256(&self.blob_hash, "blob")?;
        if self.blob_size == 0 {
            return Err("an empty blob must not use a chunked recipe".into());
        }
        if self.blob_size > MAX_MODULE_TOTAL_BYTES {
            return Err(format!(
                "chunked blob size {} exceeds the {} byte limit",
                self.blob_size, MAX_MODULE_TOTAL_BYTES
            ));
        }
        if self.chunks.is_empty() {
            return Err("a chunked blob recipe must contain at least one chunk".into());
        }
        if self.chunks.len() > MAX_CHUNKS_PER_BLOB {
            return Err(format!(
                "chunked blob recipe has {} chunks, exceeds the {} chunk limit",
                self.chunks.len(),
                MAX_CHUNKS_PER_BLOB
            ));
        }
        let function = reapi::chunking_function::Value::try_from(self.chunking_function)
            .map_err(|_| "unknown chunking function".to_string())?;
        if !matches!(
            function,
            reapi::chunking_function::Value::Unknown | reapi::chunking_function::Value::FastCdc2020
        ) {
            return Err("unsupported chunking function".into());
        }

        let mut total = 0_u64;
        for (index, chunk) in self.chunks.iter().enumerate() {
            validate_sha256(&chunk.hash, "chunk")?;
            let size = u64::try_from(chunk.size_bytes)
                .map_err(|_| "chunk digest size must be positive".to_string())?;
            if size == 0 {
                return Err("chunk digest size must be positive".into());
            }
            if function == reapi::chunking_function::Value::FastCdc2020 {
                if size > FAST_CDC_MAXIMUM_CHUNK_BYTES {
                    return Err(format!(
                        "FastCDC chunk size {size} exceeds the {FAST_CDC_MAXIMUM_CHUNK_BYTES} byte maximum"
                    ));
                }
                if index + 1 != self.chunks.len() && size < FAST_CDC_MINIMUM_CHUNK_BYTES {
                    return Err(format!(
                        "FastCDC non-final chunk size {size} is below the {FAST_CDC_MINIMUM_CHUNK_BYTES} byte minimum"
                    ));
                }
            }
            total = total
                .checked_add(size)
                .ok_or_else(|| "chunk sizes overflow the blob size".to_string())?;
        }
        if total != self.blob_size {
            return Err(format!(
                "chunk sizes total {total} bytes, expected {} bytes",
                self.blob_size
            ));
        }
        Ok(())
    }
}

pub fn recipe_key(blob_digest_key: &str) -> String {
    format!("{RECIPE_KEY_PREFIX}{blob_digest_key}")
}

pub fn is_recipe_key(key: &str) -> bool {
    key.starts_with(RECIPE_KEY_PREFIX)
}

pub fn canonical_blob_key(recipe_key: &str) -> Option<String> {
    recipe_key.strip_prefix(RECIPE_KEY_PREFIX).map(blob_key)
}

pub fn recipe_referenced_blob_keys(key: &str, bytes: &[u8]) -> Option<Vec<String>> {
    is_recipe_key(key)
        .then(|| ChunkedBlobRecipe::decode_validated(bytes).ok())
        .flatten()
        .map(|recipe| recipe.referenced_blob_keys())
}

fn validate_sha256(hash: &str, label: &str) -> Result<(), String> {
    if hash.len() != 64
        || !hash
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(format!(
            "{label} digest hash must be a lowercase 64-character SHA-256 hex value"
        ));
    }
    Ok(())
}

pub async fn fetch_recipe(
    state: &SharedState,
    namespace_id: &str,
    blob_digest: &reapi::Digest,
) -> Result<Option<(ArtifactManifest, ChunkedBlobRecipe)>, String> {
    let key = recipe_key(&format!("{}/{}", blob_digest.hash, blob_digest.size_bytes));
    let Some(manifest) =
        state
            .store
            .manifest_for_key(ArtifactProducer::Reapi, namespace_id, &key)?
    else {
        state
            .metrics
            .record_reapi_chunking_event("recipe_lookup", "absent");
        return Ok(None);
    };
    if !manifest.inline {
        state
            .metrics
            .record_reapi_chunking_event("recipe_lookup", "invalid");
        return Err("chunked blob recipe must be stored inline".into());
    }
    if manifest.size > MAX_INLINE_REPLICATION_BODY_BYTES {
        state
            .metrics
            .record_reapi_chunking_event("recipe_lookup", "oversize");
        return Err(format!(
            "chunked blob recipe exceeds the {MAX_INLINE_REPLICATION_BODY_BYTES} byte limit"
        ));
    }
    let Some(bytes) =
        state
            .store
            .fetch_inline_artifact_bytes(ArtifactProducer::Reapi, namespace_id, &key)?
    else {
        state
            .metrics
            .record_reapi_chunking_event("recipe_lookup", "invalid");
        return Err("chunked blob recipe manifest has no inline body".into());
    };
    let recipe = match ChunkedBlobRecipe::decode_validated(&bytes) {
        Ok(recipe) => recipe,
        Err(error) => {
            state
                .metrics
                .record_reapi_chunking_event("recipe_lookup", "invalid");
            return Err(error);
        }
    };
    if recipe.blob_digest() != blob_digest.clone() {
        state
            .metrics
            .record_reapi_chunking_event("recipe_lookup", "invalid");
        return Err("chunked blob recipe does not match its logical blob digest".into());
    }
    state
        .metrics
        .record_reapi_chunking_event("recipe_lookup", "hit");
    Ok(Some((manifest, recipe)))
}

pub async fn fetch_chunk_manifests(
    state: &SharedState,
    namespace_id: &str,
    recipe: &ChunkedBlobRecipe,
) -> Result<Option<Vec<ArtifactManifest>>, String> {
    let mut manifests = Vec::with_capacity(recipe.chunks().len());
    for digest in recipe.chunks() {
        let key = blob_key(&format!("{}/{}", digest.hash, digest.size_bytes));
        let Some(manifest) = state
            .store
            .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
            .await?
        else {
            return Ok(None);
        };
        manifests.push(manifest);
    }
    Ok(Some(manifests))
}

/// Returns the physical keys whose lifetimes back this logical blob. A direct
/// blob yields its own key; a composite yields every chunk key. `None` means
/// the blob is not completely readable on this node.
pub async fn presence_keys(
    state: &SharedState,
    namespace_id: &str,
    blob_digest: &reapi::Digest,
    trigger: RefreshTrigger,
    aging: bool,
    budget: &mut PresenceBudget,
) -> Result<Option<Vec<String>>, String> {
    let direct_key = blob_key(&format!("{}/{}", blob_digest.hash, blob_digest.size_bytes));
    let direct_exists = if aging {
        state
            .store
            .artifact_exists_extending_lifetime(
                ArtifactProducer::Reapi,
                namespace_id,
                &direct_key,
                trigger,
            )
            .await?
    } else {
        state
            .store
            .artifact_exists(ArtifactProducer::Reapi, namespace_id, &direct_key)
            .await?
    };
    if direct_exists {
        return Ok(Some(vec![direct_key]));
    }

    let Some((_manifest, recipe)) = fetch_recipe(state, namespace_id, blob_digest).await? else {
        return Ok(None);
    };
    budget.consume(recipe.chunks().len())?;
    let mut keys = Vec::with_capacity(recipe.chunks().len());
    for chunk in recipe.chunks() {
        let key = blob_key(&format!("{}/{}", chunk.hash, chunk.size_bytes));
        let exists = if aging {
            state
                .store
                .artifact_exists_extending_lifetime(
                    ArtifactProducer::Reapi,
                    namespace_id,
                    &key,
                    trigger,
                )
                .await?
        } else {
            state
                .store
                .artifact_exists(ArtifactProducer::Reapi, namespace_id, &key)
                .await?
        };
        if !exists {
            return Ok(None);
        }
        keys.push(key);
    }
    Ok(Some(keys))
}

/// Metadata-only counterpart used by action-result and snapshot deletion
/// gates. Eviction removes manifests atomically with storage, while promotion
/// may briefly make a cached manifest's old segment path disappear. Probing
/// storage here could therefore turn a relocation race into deletion of a
/// live action result.
pub async fn manifest_presence_keys(
    state: &SharedState,
    namespace_id: &str,
    blob_digest: &reapi::Digest,
    budget: &mut PresenceBudget,
) -> Result<Option<Vec<String>>, String> {
    let direct_key = blob_key(&format!("{}/{}", blob_digest.hash, blob_digest.size_bytes));
    if state
        .store
        .artifact_manifest_exists(ArtifactProducer::Reapi, namespace_id, &direct_key)?
    {
        return Ok(Some(vec![direct_key]));
    }

    let Some((_manifest, recipe)) = fetch_recipe(state, namespace_id, blob_digest).await? else {
        return Ok(None);
    };
    budget.consume(recipe.chunks().len())?;
    let mut keys = Vec::with_capacity(recipe.chunks().len());
    for chunk in recipe.chunks() {
        let key = blob_key(&format!("{}/{}", chunk.hash, chunk.size_bytes));
        if !state
            .store
            .artifact_manifest_exists(ArtifactProducer::Reapi, namespace_id, &key)?
        {
            return Ok(None);
        }
        keys.push(key);
    }
    Ok(Some(keys))
}

pub struct PresenceBudget {
    remaining_chunk_probes: usize,
}

impl PresenceBudget {
    pub fn for_request() -> Self {
        Self {
            remaining_chunk_probes: MAX_CHUNK_PRESENCE_PROBES_PER_REQUEST,
        }
    }

    pub fn for_snapshot_scan() -> Self {
        Self {
            remaining_chunk_probes: MAX_CHUNK_PRESENCE_PROBES_PER_SNAPSHOT_SCAN,
        }
    }

    fn consume(&mut self, probes: usize) -> Result<(), String> {
        self.remaining_chunk_probes = self
            .remaining_chunk_probes
            .checked_sub(probes)
            .ok_or_else(|| {
                format!(
                    "{PRESENCE_BUDGET_ERROR_PREFIX} the {MAX_CHUNK_PRESENCE_PROBES_PER_REQUEST} probe request limit"
                )
            })?;
        Ok(())
    }
}

pub fn is_presence_budget_error(error: &str) -> bool {
    error.starts_with(PRESENCE_BUDGET_ERROR_PREFIX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn digest(byte: u8, size: i64) -> reapi::Digest {
        reapi::Digest {
            hash: format!("{byte:02x}").repeat(32),
            size_bytes: size,
        }
    }

    #[test]
    fn recipe_round_trips_and_derives_keys() {
        let recipe = ChunkedBlobRecipe::new(
            &digest(3, (2 * FAST_CDC_MINIMUM_CHUNK_BYTES) as i64),
            vec![
                digest(1, FAST_CDC_MINIMUM_CHUNK_BYTES as i64),
                digest(2, FAST_CDC_MINIMUM_CHUNK_BYTES as i64),
            ],
            reapi::chunking_function::Value::FastCdc2020 as i32,
        )
        .expect("valid recipe");

        let decoded = ChunkedBlobRecipe::decode_validated(&recipe.encode()).expect("decode");
        assert_eq!(decoded, recipe);
        assert_eq!(
            decoded.referenced_blob_keys(),
            vec![
                blob_key(&format!(
                    "{}/{}",
                    digest(1, 1).hash,
                    FAST_CDC_MINIMUM_CHUNK_BYTES
                )),
                blob_key(&format!(
                    "{}/{}",
                    digest(2, 1).hash,
                    FAST_CDC_MINIMUM_CHUNK_BYTES
                )),
            ]
        );
    }

    #[test]
    fn rejects_unknown_versions_and_wrong_totals() {
        let mut recipe = ChunkedBlobRecipe {
            version: 99,
            blob_hash: digest(3, 1).hash,
            blob_size: 1,
            chunking_function: reapi::chunking_function::Value::Unknown as i32,
            chunks: vec![digest(1, 1)],
        };
        assert!(recipe.validate().unwrap_err().contains("version"));

        recipe.version = RECIPE_VERSION;
        recipe.blob_size = 2;
        assert!(recipe.validate().unwrap_err().contains("total"));
    }

    #[test]
    fn rejects_recipes_that_exceed_blob_or_chunk_count_limits() {
        let oversized_blob = ChunkedBlobRecipe {
            version: RECIPE_VERSION,
            blob_hash: digest(3, 1).hash,
            blob_size: MAX_MODULE_TOTAL_BYTES + 1,
            chunking_function: reapi::chunking_function::Value::Unknown as i32,
            chunks: vec![digest(1, (MAX_MODULE_TOTAL_BYTES + 1) as i64)],
        };
        assert!(oversized_blob.validate().unwrap_err().contains("limit"));

        let too_many_chunks = ChunkedBlobRecipe {
            version: RECIPE_VERSION,
            blob_hash: digest(3, 1).hash,
            blob_size: (MAX_CHUNKS_PER_BLOB + 1) as u64,
            chunking_function: reapi::chunking_function::Value::Unknown as i32,
            chunks: vec![digest(1, 1); MAX_CHUNKS_PER_BLOB + 1],
        };
        assert!(
            too_many_chunks
                .validate()
                .unwrap_err()
                .contains("chunk limit")
        );
    }

    #[test]
    fn presence_expansion_has_an_aggregate_request_budget() {
        let mut budget = PresenceBudget::for_request();
        budget
            .consume(MAX_CHUNK_PRESENCE_PROBES_PER_REQUEST)
            .expect("the exact request budget should be admitted");
        let error = budget.consume(1).expect_err("one extra probe must fail");
        assert!(is_presence_budget_error(&error));
    }
}
