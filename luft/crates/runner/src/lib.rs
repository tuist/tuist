//! Luft's runner: a per-user daemon that lets threads work on this
//! machine. The desktop apps bundle the `luft-runner` binary and drive it
//! through its command line (`status`, `install`, `uninstall`, `set`,
//! `request-permissions`); the service manager starts `run`.
pub mod config;
pub mod connection;
pub mod display;
pub mod ops;
pub mod paths;
pub mod service;
pub mod status;

/// Cargo sets the package version; Struo's rustc actions do not.
pub const VERSION: &str = match option_env!("CARGO_PKG_VERSION") {
    Some(version) => version,
    None => "0.1.0",
};
