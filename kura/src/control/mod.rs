//! The local control surface that `kura runtime inspect` and its siblings read.
//!
//! It is served over a Unix socket inside the data directory rather than on a
//! TCP port. That choice is deliberate:
//!
//! - The reports include the resolved configuration and the peer sets. Putting
//!   that on a network listener means one ingress or NetworkPolicy mistake
//!   exposes it. A socket in the data directory cannot be reached off-box.
//! - Authorization becomes "can you get into this container", which is already
//!   the boundary the cluster enforces. No second auth story to build.
//! - Liveness detection is free. A clean shutdown unlinks the socket and a
//!   crash leaves one whose `connect` fails, so the CLI never has to guess
//!   whether a recorded pid is still the process it wants.
//!
//! Reaching a *different* node stays explicit (`--node`) and goes over the
//! existing internal listener, which already has an mTLS identity.

pub mod client;
pub mod grant;
pub mod report;
pub mod runtime_file;
pub mod server;

pub use runtime_file::RuntimeInfo;
