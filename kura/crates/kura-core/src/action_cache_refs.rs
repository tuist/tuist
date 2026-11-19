//! Derivation of the blob references an action-cache entry carries.
//!
//! An action-cache entry is a REAPI `ActionResult` stored inline; it references
//! CAS output blobs by digest. The storage layer maintains a reverse index
//! (blob -> referencing entries) so eviction can cascade instead of stranding
//! entries whose blobs it removes. This module is the single place that decodes
//! an `ActionResult` and yields the blob keys it references, so the write,
//! delete, backfill, and eviction paths agree on exactly one definition of
//! "referenced blob".

use bazel_remote_apis::build::bazel::remote::execution::v2 as reapi;
use prost::Message;

use crate::utils::blob_key;

const EMPTY_BLOB_SHA256: &str = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

/// The logical blob keys (`blob/{hash}/{size}`) an action-cache entry references
/// directly: every `output_files[].digest`, `stdout_digest`, `stderr_digest`,
/// and each `output_directories[].tree_digest`. Returned sorted and
/// de-duplicated so a single hot blob referenced twice yields one reverse row.
///
/// Malformed bytes and malformed/empty digests are skipped: an entry we cannot
/// decode has no derivable references (it is left for the serve-side presence
/// gates), and the empty blob is never stored so it can never be stranded.
///
/// Tree **leaves** are intentionally not walked. A `Tree`'s inner file digests
/// are referenced transitively, and covering them would require reading and
/// decoding the tree blob here. Tuist's action-cache is `output_files` only in
/// practice (no `output_directories`), so the cascade indexes the direct tree
/// digest and leaves the per-key/snapshot presence gates as the backstop for
/// the rare tree-output shape.
pub fn referenced_blob_keys(action_result_bytes: &[u8]) -> Vec<String> {
    let Ok(result) = reapi::ActionResult::decode(action_result_bytes) else {
        return Vec::new();
    };

    let mut keys = Vec::new();
    for file in &result.output_files {
        push_blob_key(&mut keys, file.digest.as_ref());
    }
    push_blob_key(&mut keys, result.stdout_digest.as_ref());
    push_blob_key(&mut keys, result.stderr_digest.as_ref());
    for directory in &result.output_directories {
        push_blob_key(&mut keys, directory.tree_digest.as_ref());
    }

    keys.sort();
    keys.dedup();
    keys
}

fn push_blob_key(keys: &mut Vec<String>, digest: Option<&reapi::Digest>) {
    if let Some(digest) = digest
        && !is_empty_blob(digest)
        && let Some(raw_key) = digest_blob_raw_key(digest)
    {
        keys.push(blob_key(&raw_key));
    }
}

fn is_empty_blob(digest: &reapi::Digest) -> bool {
    digest.size_bytes == 0 && digest.hash == EMPTY_BLOB_SHA256
}

/// `{hash}/{size}` for a well-formed SHA-256 digest, matching the REAPI layer's
/// `digest_key`. A malformed digest yields `None` (nothing to reference) rather
/// than an error: this runs on the storage write/delete paths, not a request
/// boundary, and the request boundary already rejected malformed digests.
fn digest_blob_raw_key(digest: &reapi::Digest) -> Option<String> {
    if digest.size_bytes < 0 {
        return None;
    }
    if digest.hash.len() != 64 || !digest.hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    Some(format!("{}/{}", digest.hash, digest.size_bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn digest(hash: &str, size: i64) -> reapi::Digest {
        reapi::Digest {
            hash: hash.to_string(),
            size_bytes: size,
        }
    }

    fn hash(byte: u8) -> String {
        format!("{:02x}", byte).repeat(32)
    }

    #[test]
    fn enumerates_output_files_stdout_stderr_and_tree_digests() {
        let result = reapi::ActionResult {
            output_files: vec![
                reapi::OutputFile {
                    path: "a".into(),
                    digest: Some(digest(&hash(1), 10)),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "b".into(),
                    digest: Some(digest(&hash(2), 20)),
                    ..Default::default()
                },
            ],
            stdout_digest: Some(digest(&hash(3), 30)),
            stderr_digest: Some(digest(&hash(4), 40)),
            output_directories: vec![reapi::OutputDirectory {
                path: "d".into(),
                tree_digest: Some(digest(&hash(5), 50)),
                ..Default::default()
            }],
            ..Default::default()
        };

        let keys = referenced_blob_keys(&result.encode_to_vec());

        assert_eq!(keys, {
            let mut expected = vec![
                blob_key(&format!("{}/10", hash(1))),
                blob_key(&format!("{}/20", hash(2))),
                blob_key(&format!("{}/30", hash(3))),
                blob_key(&format!("{}/40", hash(4))),
                blob_key(&format!("{}/50", hash(5))),
            ];
            expected.sort();
            expected
        });
    }

    #[test]
    fn skips_empty_blob_and_deduplicates() {
        let result = reapi::ActionResult {
            output_files: vec![
                reapi::OutputFile {
                    path: "a".into(),
                    digest: Some(digest(&hash(1), 10)),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "b".into(),
                    digest: Some(digest(&hash(1), 10)),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "empty".into(),
                    digest: Some(digest(EMPTY_BLOB_SHA256, 0)),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };

        let keys = referenced_blob_keys(&result.encode_to_vec());

        assert_eq!(keys, vec![blob_key(&format!("{}/10", hash(1)))]);
    }

    #[test]
    fn undecodable_bytes_yield_no_references() {
        assert!(referenced_blob_keys(b"not a proto").is_empty());
    }

    #[test]
    fn skips_malformed_digests() {
        let result = reapi::ActionResult {
            output_files: vec![
                reapi::OutputFile {
                    path: "short-hash".into(),
                    digest: Some(digest("abc", 10)),
                    ..Default::default()
                },
                reapi::OutputFile {
                    path: "negative-size".into(),
                    digest: Some(digest(&hash(9), -1)),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };

        assert!(referenced_blob_keys(&result.encode_to_vec()).is_empty());
    }
}
