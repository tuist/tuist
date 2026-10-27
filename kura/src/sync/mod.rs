//! Pull-based replication (design: `docs/replication-design.md`).
//!
//! Two links, both pulling with long-polls:
//!
//! - **replica** (intra-region): a sibling reads this node's bounded arrival
//!   feed forward ([`feed`]) after a horizon-bounded backward pass; lossless.
//! - **region** (inter-region): the region's gateway reads each remote
//!   gateway's `version_ms` index ascending from a per-origin watermark;
//!   best-effort.
//!
//! [`roles`] decides who is a gateway from the membership view (and from the
//! roles the control plane publishes when it has better information).

pub mod coordinator;
pub mod feed;
pub mod region;
pub mod replica;
pub mod roles;

#[cfg(test)]
mod link_tests;
#[cfg(test)]
mod tests;
