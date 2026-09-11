//! Backfill: the catch-up pass both pull links run (design §3.1, §4.1). A
//! pass walks one peer's entries newest → oldest inside a bounded window;
//! recent entries are guaranteed, completeness is best-effort.

pub mod claims;
pub mod pass;
pub mod window;
