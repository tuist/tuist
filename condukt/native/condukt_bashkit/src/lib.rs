//! Rustler NIF wrapping bashkit's virtual sandbox so Condukt can offer a
//! `Sandbox.Virtual` backend that runs against an in-memory virtual
//! filesystem and a Rust-implemented bash interpreter, with no host process
//! spawning by default.
//!
//! All operations run on a shared multi-threaded tokio runtime and are
//! scheduled on a dirty I/O scheduler so they don't block BEAM's regular
//! schedulers.

use bashkit::{Bash, FileSystem, PosixFs, RealFs, RealFsMode};
use rustler::{Atom, Binary, Env, NifResult, NifTuple, NifUnitEnum, ResourceArc};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::runtime::Runtime;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        // I/O errors mirroring File.* atoms.
        enoent,
        eisdir,
        eexist,
        eacces,
        // Other errors.
        timeout,
        invalid_mount_mode,
        not_found,
        already_mounted,
        invalid_path,
        // Result keys.
        output,
        exit_code,
        occurrences,
        content,
        path,
        line_number,
        line,
    }
}

// Build a fresh current-thread tokio runtime per NIF call. Reasons:
//
// 1. NIF calls already run on a dedicated dirty-IO scheduler thread, so
//    spawning a tokio runtime there has no extra OS-thread cost.
// 2. A current-thread runtime built and dropped within a single call has
//    well-defined lifetime: no lingering bashkit-internal `spawn_blocking`
//    tasks across calls, no risk of dropping a runtime that still has
//    work in flight.
// 3. A shared (per-session or global) runtime previously caused Linux
//    segfaults during test cleanup: bashkit's parser uses
//    `tokio::task::spawn_blocking` internally and a runtime dropped while
//    a blocking task still holds references would crash. Per-call
//    construction sidesteps this by tying the runtime to one block_on
//    call's lifetime.
fn build_runtime() -> Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("failed to build bashkit tokio runtime")
}

// ============================================================================
// Resource
// ============================================================================

pub struct Session {
    bash: Mutex<Bash>,
}

#[rustler::resource_impl]
impl rustler::Resource for Session {}

// ============================================================================
// Init options
// ============================================================================

#[derive(NifUnitEnum, Clone, Copy)]
pub enum MountMode {
    Readonly,
    Readwrite,
}

#[derive(NifTuple)]
pub struct MountSpec {
    pub host_path: String,
    pub vfs_path: String,
    pub mode: MountMode,
}

// ============================================================================
// Result encodings
// ============================================================================

#[derive(rustler::NifMap)]
pub struct ExecResult {
    pub output: String,
    pub exit_code: i32,
}

#[derive(rustler::NifMap)]
pub struct EditResult {
    pub occurrences: usize,
    pub content: String,
}

#[derive(rustler::NifMap)]
pub struct GrepMatch {
    pub path: String,
    pub line_number: u64,
    pub line: String,
}

// ============================================================================
// NIFs
// ============================================================================

#[rustler::nif(schedule = "DirtyIo")]
fn new_session(mounts: Vec<MountSpec>) -> NifResult<ResourceArc<Session>> {
    let bash = build_bash(&mounts).map_err(|e| rustler::Error::Term(Box::new(format!("{e}"))))?;
    Ok(ResourceArc::new(Session {
        bash: Mutex::new(bash),
    }))
}

#[rustler::nif(schedule = "DirtyIo")]
fn shutdown(_session: ResourceArc<Session>) -> Atom {
    // Nothing to release explicitly: dropping the ResourceArc drops the
    // Bash instance and any owned filesystem state. This nif exists for
    // symmetry with start so callers can opt into eager release.
    atoms::ok()
}

#[rustler::nif(schedule = "DirtyIo")]
fn exec(
    session: ResourceArc<Session>,
    command: String,
    timeout_ms: Option<u64>,
) -> NifResult<Result<ExecResult, Atom>> {
    let mut bash = session.bash.lock().map_err(|_| poisoned())?;
    let timeout = timeout_ms.map(Duration::from_millis);

    let fut = bash.exec(&command);
    let result = match timeout {
        Some(d) => build_runtime().block_on(async move { tokio::time::timeout(d, fut).await }),
        None => Ok(build_runtime().block_on(fut)),
    };

    match result {
        Err(_) => Ok(Err(atoms::timeout())),
        Ok(Err(e)) => Ok(Err(map_bashkit_error(&e))),
        Ok(Ok(r)) => Ok(Ok(ExecResult {
            output: combine_output(&r.stdout, &r.stderr),
            exit_code: r.exit_code,
        })),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn read_file<'a>(
    env: Env<'a>,
    session: ResourceArc<Session>,
    path: String,
) -> NifResult<Result<Binary<'a>, Atom>> {
    let bash = session.bash.lock().map_err(|_| poisoned())?;
    let fs = bash.fs().clone();
    drop(bash);

    let path_buf = PathBuf::from(&path);
    let read = build_runtime().block_on(fs.read_file(&path_buf));

    match read {
        Ok(bytes) => {
            let mut owned = rustler::OwnedBinary::new(bytes.len()).ok_or_else(|| {
                rustler::Error::Term(Box::new("failed to allocate binary".to_string()))
            })?;
            owned.as_mut_slice().copy_from_slice(&bytes);
            Ok(Ok(Binary::from_owned(owned, env)))
        }
        Err(e) => Ok(Err(map_bashkit_error(&e))),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn write_file(
    session: ResourceArc<Session>,
    path: String,
    content: Binary,
) -> NifResult<Result<Atom, Atom>> {
    let bash = session.bash.lock().map_err(|_| poisoned())?;
    let fs = bash.fs().clone();
    drop(bash);

    let path_buf = PathBuf::from(&path);
    let bytes = content.as_slice().to_vec();

    let result = build_runtime().block_on(async move {
        if let Some(parent) = path_buf.parent() {
            if !parent.as_os_str().is_empty() {
                let _ = fs.mkdir(parent, true).await;
            }
        }
        fs.write_file(&path_buf, &bytes).await
    });

    match result {
        Ok(()) => Ok(Ok(atoms::ok())),
        Err(e) => Ok(Err(map_bashkit_error(&e))),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn edit_file(
    session: ResourceArc<Session>,
    path: String,
    old_text: String,
    new_text: String,
) -> NifResult<Result<EditResult, Atom>> {
    let bash = session.bash.lock().map_err(|_| poisoned())?;
    let fs = bash.fs().clone();
    drop(bash);

    let path_buf = PathBuf::from(&path);
    let read = build_runtime().block_on(fs.read_file(&path_buf));
    let bytes = match read {
        Ok(b) => b,
        Err(e) => return Ok(Err(map_bashkit_error(&e))),
    };

    let content = String::from_utf8_lossy(&bytes).into_owned();
    let occurrences = count_occurrences(&content, &old_text);

    if occurrences != 1 {
        return Ok(Ok(EditResult { occurrences, content }));
    }

    let new_content = content.replacen(&old_text, &new_text, 1);
    let write = build_runtime().block_on(fs.write_file(&path_buf, new_content.as_bytes()));
    match write {
        Ok(()) => Ok(Ok(EditResult {
            occurrences: 1,
            content: new_content,
        })),
        Err(e) => Ok(Err(map_bashkit_error(&e))),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn glob(
    session: ResourceArc<Session>,
    pattern: String,
    cwd: Option<String>,
) -> NifResult<Result<Vec<String>, Atom>> {
    // Use bash's own glob expansion via `printf '%s\n' <pattern>`.
    // `nullglob` makes the pattern expand to empty (rather than the literal
    // pattern string) when there are no matches.
    //
    // The pattern is intentionally left unquoted so the shell can expand it.
    // Sanitize defensively: reject patterns with characters that would let
    // a malicious caller break out into arbitrary shell.
    let mut bash = session.bash.lock().map_err(|_| poisoned())?;

    if !is_safe_glob(&pattern) {
        return Ok(Ok(Vec::new()));
    }

    let cd = cwd
        .map(|c| format!("cd '{}' && ", escape_single_quotes(&c)))
        .unwrap_or_default();

    let script = format!("{cd}shopt -s nullglob 2>/dev/null; printf '%s\\n' {}", pattern);
    let result = build_runtime().block_on(bash.exec(&script));

    match result {
        Err(e) => Ok(Err(map_bashkit_error(&e))),
        Ok(r) => Ok(Ok(r
            .stdout
            .lines()
            .filter(|l| !l.is_empty())
            .map(|l| l.to_string())
            .collect())),
    }
}

/// Allow only characters that appear in shell glob syntax. Reject anything
/// that could let a caller terminate the glob argument and inject code:
/// no quotes, backticks, `$`, `;`, `|`, `&`, `<`, `>`, `(`, `)`, `\n`, `\r`.
fn is_safe_glob(pattern: &str) -> bool {
    pattern
        .chars()
        .all(|c| !matches!(c, '`' | '$' | ';' | '|' | '&' | '<' | '>' | '(' | ')' | '\n' | '\r' | '\'' | '"'))
}

#[rustler::nif(schedule = "DirtyIo")]
fn grep(
    session: ResourceArc<Session>,
    pattern: String,
    path: Option<String>,
    case_sensitive: bool,
    file_glob: Option<String>,
) -> NifResult<Result<Vec<GrepMatch>, Atom>> {
    let mut bash = session.bash.lock().map_err(|_| poisoned())?;
    let search_root = path.unwrap_or_else(|| "/".to_string());
    let case_flag = if case_sensitive { "" } else { "-i" };

    // bashkit's grep doesn't support --include, so we filter file matches in
    // Rust after the fact based on `file_glob` (a shell-style glob applied to
    // each path's basename).
    let script = format!(
        "grep -rnHE{case} '{pat}' '{root}' || true",
        case = case_flag,
        pat = escape_single_quotes(&pattern),
        root = escape_single_quotes(&search_root),
    );

    let result = build_runtime().block_on(bash.exec(&script));

    match result {
        Err(e) => Ok(Err(map_bashkit_error(&e))),
        Ok(r) => {
            let matches = parse_grep(&r.stdout);
            let filtered = match file_glob {
                None => matches,
                Some(g) => matches
                    .into_iter()
                    .filter(|m| matches_basename_glob(&m.path, &g))
                    .collect(),
            };
            Ok(Ok(filtered))
        }
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn mount(
    session: ResourceArc<Session>,
    host_path: String,
    vfs_path: String,
    mode: MountMode,
) -> NifResult<Result<Atom, Atom>> {
    let bash = session.bash.lock().map_err(|_| poisoned())?;

    let backend = match RealFs::new(&host_path, mode.into()) {
        Ok(b) => b,
        Err(_) => return Ok(Err(atoms::invalid_path())),
    };
    let fs: Arc<dyn FileSystem> = Arc::new(PosixFs::new(backend));

    match bash.mount(&vfs_path, fs) {
        Ok(()) => Ok(Ok(atoms::ok())),
        Err(e) => Ok(Err(map_bashkit_error(&e))),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn unmount(session: ResourceArc<Session>, vfs_path: String) -> NifResult<Result<Atom, Atom>> {
    let bash = session.bash.lock().map_err(|_| poisoned())?;
    match bash.unmount(&vfs_path) {
        Ok(()) => Ok(Ok(atoms::ok())),
        Err(_) => Ok(Err(atoms::not_found())),
    }
}

// ============================================================================
// Helpers
// ============================================================================

impl From<MountMode> for RealFsMode {
    fn from(value: MountMode) -> Self {
        match value {
            MountMode::Readonly => RealFsMode::ReadOnly,
            MountMode::Readwrite => RealFsMode::ReadWrite,
        }
    }
}

fn build_bash(mounts: &[MountSpec]) -> Result<Bash, String> {
    let mut builder = Bash::builder();
    for m in mounts {
        let host = PathBuf::from(&m.host_path);
        match m.mode {
            MountMode::Readonly => {
                builder = builder.mount_real_readonly_at(host, m.vfs_path.clone());
            }
            MountMode::Readwrite => {
                builder = builder.mount_real_readwrite_at(host, m.vfs_path.clone());
            }
        }
    }
    Ok(builder.build())
}

fn map_bashkit_error(error: &bashkit::Error) -> Atom {
    let s = format!("{error}");
    let lower = s.to_ascii_lowercase();
    if lower.contains("not found") || lower.contains("no such") {
        atoms::enoent()
    } else if lower.contains("is a directory") {
        atoms::eisdir()
    } else if lower.contains("already exists") {
        atoms::eexist()
    } else if lower.contains("permission") || lower.contains("denied") {
        atoms::eacces()
    } else {
        atoms::error()
    }
}

fn poisoned() -> rustler::Error {
    rustler::Error::Term(Box::new("bashkit session lock poisoned".to_string()))
}

fn count_occurrences(haystack: &str, needle: &str) -> usize {
    if needle.is_empty() {
        return 0;
    }
    haystack.matches(needle).count()
}

fn escape_single_quotes(s: &str) -> String {
    s.replace('\'', "'\\''")
}

fn combine_output(stdout: &str, stderr: &str) -> String {
    if stderr.is_empty() {
        stdout.to_string()
    } else if stdout.is_empty() {
        stderr.to_string()
    } else {
        format!("{stdout}{stderr}")
    }
}

/// Minimal shell-style glob match for the file basename. Supports `*`, `?`,
/// and literal characters. Used to filter grep results by extension or
/// filename pattern when bashkit's grep can't (no --include support).
fn matches_basename_glob(full_path: &str, glob: &str) -> bool {
    let basename = std::path::Path::new(full_path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(full_path);
    glob_match(glob, basename)
}

fn glob_match(pattern: &str, text: &str) -> bool {
    fn helper(pattern: &[u8], text: &[u8]) -> bool {
        match (pattern.first(), text.first()) {
            (None, None) => true,
            (None, _) => false,
            (Some(b'*'), _) => {
                if helper(&pattern[1..], text) {
                    return true;
                }
                if let Some((_, rest)) = text.split_first() {
                    return helper(pattern, rest);
                }
                false
            }
            (Some(b'?'), Some(_)) => helper(&pattern[1..], &text[1..]),
            (Some(p), Some(t)) if p == t => helper(&pattern[1..], &text[1..]),
            _ => false,
        }
    }
    helper(pattern.as_bytes(), text.as_bytes())
}

fn parse_grep(output: &str) -> Vec<GrepMatch> {
    output
        .lines()
        .filter_map(|line| {
            // Format: path:line_number:line_content
            let mut parts = line.splitn(3, ':');
            let path = parts.next()?;
            let line_num_str = parts.next()?;
            let content = parts.next()?;
            let line_number: u64 = line_num_str.parse().ok()?;
            Some(GrepMatch {
                path: path.to_string(),
                line_number,
                line: content.to_string(),
            })
        })
        .collect()
}

// ============================================================================
// Module init
// ============================================================================

rustler::init!("Elixir.Condukt.Bashkit.NIF");
