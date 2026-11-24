use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;

use crate::{
    artifact::{manifest::ArtifactManifest, producer::ArtifactProducer},
    constants::MAX_INLINE_REPLICATION_BODY_BYTES,
    state::SharedState,
    store::RefreshTrigger,
    utils::blob_key,
};

pub use kura_core::reapi::chunking::*;

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
    refresh: bool,
) -> Result<Option<Vec<ArtifactManifest>>, String> {
    let mut manifests = Vec::with_capacity(recipe.chunks().len());
    for digest in recipe.chunks() {
        let key = blob_key(&format!("{}/{}", digest.hash, digest.size_bytes));
        let lookup = if refresh {
            state
                .store
                .fetch_artifact_for_serving(ArtifactProducer::Reapi, namespace_id, &key)
                .await?
        } else {
            state
                .store
                .manifest_for_key(ArtifactProducer::Reapi, namespace_id, &key)?
        };
        let Some(manifest) = lookup else {
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
    recipe_presence_keys(state, namespace_id, blob_digest, trigger, aging, budget).await
}

/// The composite half of [`presence_keys`], for callers that already know the
/// direct blob is absent.
pub async fn recipe_presence_keys(
    state: &SharedState,
    namespace_id: &str,
    blob_digest: &reapi::Digest,
    trigger: RefreshTrigger,
    aging: bool,
    budget: &mut PresenceBudget,
) -> Result<Option<Vec<String>>, String> {
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
