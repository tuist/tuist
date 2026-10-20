//! Stable verification selection shared by compiler adapters and input hashing.
use std::cell::Cell;

use eyre::Result;
use tuist_cargo_cache_core::CacheDigest;

pub(super) const SAMPLE_RATE_ENV: &str = "TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE";
thread_local! {
    static SELECTED: Cell<Option<bool>> = const { Cell::new(None) };
}

pub(crate) struct Selection(Option<bool>);

fn full_verification() -> bool {
    std::env::var_os(super::VERIFY_ENV).is_some_and(|value| !value.is_empty() && value != "0")
}

pub(super) fn requested() -> bool {
    full_verification() || SELECTED.with(|selected| selected.get().unwrap_or(false))
}

/// Decide once, before either adapter discovers inputs. A sampled invocation
/// must also bypass the session digest ledger and learned incremental state.
/// Computing the digest is lazy so disabled sampling adds no key-building work.
pub(crate) fn select(identity: impl FnOnce() -> Result<CacheDigest>) -> Result<Selection> {
    let rate = std::env::var(SAMPLE_RATE_ENV)
        .ok()
        .and_then(|rate| rate.parse::<u8>().ok())
        .filter(|rate| *rate <= 100)
        .unwrap_or(0);
    let selected = if full_verification() || rate == 100 {
        true
    } else if rate == 0 {
        false
    } else {
        sampled(&identity()?.hash, rate)
    };
    Ok(Selection(
        SELECTED.with(|slot| slot.replace(Some(selected))),
    ))
}

fn sampled(hash: &str, rate: u8) -> bool {
    // Invocation digests are uniformly distributed hex. This needs neither a
    // process-local counter nor shared mutable state across wrapper processes.
    hash.get(..16)
        .and_then(|prefix| u64::from_str_radix(prefix, 16).ok())
        .is_some_and(|bucket| bucket % 100 < u64::from(rate))
}

impl Drop for Selection {
    fn drop(&mut self) {
        SELECTED.with(|slot| slot.set(self.0));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn samples_are_stable_and_rates_are_nested() {
        let hashes: Vec<_> = (0..1000)
            .map(|n| CacheDigest::blake3(n.to_string().as_bytes()).hash)
            .collect();
        let first: Vec<_> = hashes.iter().map(|hash| sampled(hash, 10)).collect();
        assert!(first.iter().any(|selected| *selected));
        assert!(first.iter().any(|selected| !selected));
        // Simulate fresh processes and a different execution order.
        for (hash, selected) in hashes.iter().zip(&first).rev() {
            assert_eq!(sampled(hash, 10), *selected);
            assert!(!sampled(hash, 0));
            assert!(sampled(hash, 100));
            assert!(!selected || sampled(hash, 50));
        }
    }
}
