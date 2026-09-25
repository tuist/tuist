//! Action types and cache-aware execution.
//!
//! Currently exposes one action kind ([`Action::RunCommand`]) and an
//! async executor ([`Runner`]) that consults a cache provider before
//! spawning a subprocess. All filesystem and process I/O is async;
//! subprocess output is streamed through the CAS rather than buffered.

mod action;
mod directory_blob;
mod env;
mod error;
mod execute;
mod file_blob;
mod input_digest;
mod local;
mod outputs;
mod path;
mod plan;
mod remote;
mod resources;
mod runner;
mod stream;
mod xdg;

pub use action::{Action, OutputSymlinkMode, RemoteExecution};
pub use env::{
    select_tool_env, tool_env, workspace_tool, workspace_tool_env, workspace_tool_var, ToolEnvError,
};
pub use error::{Error, Result};
pub use input_digest::InputDigestBuilder;
pub use path::{WorkspacePath, WorkspacePathError};
pub use plan::{BuiltPlan, NodeInfo, Plan, PlanError, PlanNode, PlanOutcome};
pub use resources::{ResourceLimits, ResourcePool, ResourceRequest};
pub use runner::{
    run, run_with_cache, run_with_cache_streaming, CacheState, Outcome, RunOpts, Runner,
};
pub use xdg::Xdg;
