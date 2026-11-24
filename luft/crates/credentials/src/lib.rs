//! The credential files and refresh lock shared with the Tuist CLI and the
//! Swift app (`cli/Sources/TuistServer/Utilities/ServerCredentialsStore.swift`
//! and `CachedValueStore.swift`). Paths, file format, and lock identity must
//! stay byte-compatible with them, so every client sees one session per server
//! and no two processes spend the same refresh token.

mod directories;
mod lock;
mod store;

pub use directories::{Directories, Platform};
pub use lock::{LockError, RefreshLock};
pub use store::{Credentials, CredentialsStore, StoreError, atomic_write_private};
