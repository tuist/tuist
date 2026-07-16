//! Diagnostic probe: publish one brand-new action-cache key and watch whether
//! the server's snapshot watermark ever advances past it. Splits "re-publish
//! path ignored" from "scan/reconcile never sees new rows".
//!
//! Env: TUIST_CAS_REMOTE_GRPC_URL, TUIST_CAS_TOKEN or
//! TUIST_CAS_TUIST_BIN(+TUIST_CAS_SERVER_URL), TUIST_CAS_PROJECT.

use std::sync::Arc;
use std::time::Duration;

use tuist_cas_plugin::reapi::{blob_digest, ManifestEntry, Remote, RemoteConfig};
use tuist_cas_plugin::token::TokenProvider;

fn decode_snapshot_header(bytes: &[u8]) -> Option<(u64, u32, Vec<[u8; 32]>)> {
    fn take<'a>(bytes: &mut &'a [u8], n: usize) -> Option<&'a [u8]> {
        if bytes.len() < n {
            return None;
        }
        let (head, tail) = bytes.split_at(n);
        *bytes = tail;
        Some(head)
    }
    fn take_u32(bytes: &mut &[u8]) -> Option<u32> {
        Some(u32::from_le_bytes(take(bytes, 4)?.try_into().ok()?))
    }
    let mut bytes = bytes;
    if take(&mut bytes, 4)? != b"TSNP" || take(&mut bytes, 1)? != [2] {
        return None;
    }
    let watermark = u64::from_le_bytes(take(&mut bytes, 8)?.try_into().ok()?);
    let node_count = take_u32(&mut bytes)?;
    for _ in 0..node_count {
        let len = take(&mut bytes, 1)?[0] as usize;
        take(&mut bytes, len + 32 + 8)?;
    }
    let key_count = take_u32(&mut bytes)? as usize;
    let mut keys = Vec::with_capacity(key_count);
    for _ in 0..key_count {
        let action_hash: [u8; 32] = take(&mut bytes, 32)?.try_into().ok()?;
        let entry_count = take_u32(&mut bytes)? as usize;
        take(&mut bytes, entry_count * 4)?;
        keys.push(action_hash);
    }
    Some((watermark, node_count, keys))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

fn main() {
    let config = RemoteConfig::from_env().expect("TUIST_CAS_REMOTE_GRPC_URL required");
    let tokens = TokenProvider::from_env();
    let remote = Remote::new(config, tokens.clone());

    // A unique blob + a unique llcas digest + a unique action key, derived
    // from the wall clock so re-runs don't collide.
    let seed = now_ms();
    let blob_bytes = format!("tuist-snapshot-probe-{seed}").into_bytes();
    let blob = blob_digest(&blob_bytes);
    let mut llcas = vec![0u8; 32];
    llcas[..8].copy_from_slice(&seed.to_le_bytes());
    let mut action_key = [0xabu8; 32];
    action_key[..8].copy_from_slice(&seed.to_le_bytes());

    println!("probe action key: {}", hex(&action_key));
    println!(
        "probe blob:       {} ({} bytes)",
        blob.hash,
        blob_bytes.len()
    );

    remote
        .batch_update(vec![(blob.clone(), blob_bytes)])
        .expect("blob upload failed");
    println!("[{}] blob uploaded", now_ms());

    let manifest = [ManifestEntry {
        llcas_digest: llcas,
        blob,
        contents: None,
    }];
    // Taken BEFORE the call: the server stamps the entry with its own clock
    // during the RPC, so a post-call timestamp runs a few ms ahead of the
    // stored version and turns the watermark comparison into a false negative.
    let published_at = now_ms();
    remote
        .update_action(&action_key, &manifest, None, None)
        .expect("update_action failed");
    println!("[{published_at}] action result published");

    match remote.get_action(&action_key) {
        Ok(Some(entries)) => println!("per-key readback: HIT ({} entries)", entries.len()),
        Ok(None) => println!("per-key readback: MISS (!!)"),
        Err(error) => println!("per-key readback: ERROR {error}"),
    }

    // Phase 1: poll the full snapshot until the fresh key's publish is
    // reflected. Every serve kicks the server's background reconcile (60s
    // interval), so within 2-3 polls a healthy index must advance the
    // watermark past the publish.
    if !(0..10).any(|round| {
        std::thread::sleep(Duration::from_secs(45));
        poll(&remote, &tokens, round, published_at)
    }) {
        println!("PROBE RESULT: fresh key NEVER became snapshot-visible");
        return;
    }
    println!("PROBE RESULT: fresh key became snapshot-visible");

    // Phase 2: RE-publish the same key with DIFFERENT content (the failing
    // production case was existing keys whose value graphs changed) and
    // watch whether the watermark advances past the second publish too.
    let blob2_bytes = format!("tuist-snapshot-probe-repub-{seed}").into_bytes();
    let blob2 = blob_digest(&blob2_bytes);
    remote
        .batch_update(vec![(blob2.clone(), blob2_bytes)])
        .expect("second blob upload failed");
    let mut llcas2 = vec![1u8; 32];
    llcas2[..8].copy_from_slice(&seed.to_le_bytes());
    let manifest2 = [ManifestEntry {
        llcas_digest: llcas2,
        blob: blob2,
        contents: None,
    }];
    let republished_at = now_ms();
    remote
        .update_action(&action_key, &manifest2, None, None)
        .expect("re-publish failed");
    println!("[{republished_at}] action result RE-published (same key, new content)");
    if (0..10).any(|round| {
        std::thread::sleep(Duration::from_secs(45));
        poll(&remote, &tokens, round, republished_at)
    }) {
        println!("PROBE RESULT: re-publish became snapshot-visible");
    } else {
        println!(
            "PROBE RESULT: re-publish NEVER became snapshot-visible (frozen watermark reproduced)"
        );
    }
}

/// One snapshot poll: prints the view's shape and returns whether its
/// watermark has advanced past `published_at`.
fn poll(
    remote: &std::sync::Arc<Remote>,
    tokens: &std::sync::Arc<TokenProvider>,
    round: usize,
    published_at: u64,
) -> bool {
    tokens.refresh_if_expiring(Duration::from_secs(120));
    match remote.get_snapshot(None, None) {
        Ok(Some(bytes)) => match decode_snapshot_header(&bytes) {
            Some((watermark, nodes, keys)) => {
                println!(
                    "[{}] round {round}: snapshot {} bytes, {} keys, {nodes} nodes, watermark {watermark} ({})",
                    now_ms(),
                    bytes.len(),
                    keys.len(),
                    if watermark >= published_at {
                        "ADVANCED past publish"
                    } else {
                        "still BEHIND publish"
                    },
                );
                watermark >= published_at
            }
            None => {
                println!(
                    "round {round}: snapshot decode failed ({} bytes)",
                    bytes.len()
                );
                false
            }
        },
        Ok(None) => {
            println!("round {round}: no snapshot served");
            false
        }
        Err(error) => {
            println!("round {round}: snapshot fetch error: {error}");
            false
        }
    }
}
