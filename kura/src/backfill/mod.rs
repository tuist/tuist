//! Backfill: the recency-first replacement for bootstrap. A backfill walks
//! one peer's entries newest → oldest inside a bounded window; recent entries
//! are guaranteed, completeness is best-effort.

pub mod claims;
pub mod window;
