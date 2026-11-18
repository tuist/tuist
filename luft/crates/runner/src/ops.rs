//! The operations a thread runs on this machine, one JSON request in, one JSON
//! response out. They are what a Condukt sandbox needs (files, globs, commands)
//! plus display sharing. Every path must be inside one of the runner's folders,
//! symlinks included; commands need terminal access and display operations
//! need display sharing.
//!
//! Requests: `{"id":…, "op":…, …}`. Responses: `{"id":…, "ok":true, "result":…}`
//! or `{"id":…, "ok":false, "error":"…"}`.
use serde_json::{Value, json};
use std::io::Read;
use std::path::{Component, Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use crate::config::Config;
use crate::{display, paths};

const MAX_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_OUTPUT_BYTES: usize = 1024 * 1024;
const MAX_LIST_ENTRIES: usize = 10_000;
const DEFAULT_TIMEOUT_MS: u64 = 120_000;
const MAX_TIMEOUT_MS: u64 = 30 * 60 * 1000;

/// Runs one request. `state` is the runner's state directory: threads never
/// reach it, nor the log, even inside a shared folder, because it holds the
/// settings and the server secret.
pub fn handle(state: &Path, config: &Config, request: &Value) -> Value {
    let id = request.get("id").cloned().unwrap_or(Value::Null);
    match dispatch(state, config, request) {
        Ok(result) => json!({"id":id, "ok":true, "result":result}),
        Err(error) => json!({"id":id, "ok":false, "error":error}),
    }
}

fn string<'a>(request: &'a Value, key: &str) -> Result<&'a str, String> {
    request[key]
        .as_str()
        .ok_or_else(|| format!("{key} must be a string"))
}

fn dispatch(state: &Path, config: &Config, request: &Value) -> Result<Value, String> {
    let op = string(request, "op")?;
    let folders = Folders::new(state, config);
    match op {
        "info" => Ok(json!({
            "name": config.name,
            "platform": std::env::consts::OS,
            "folders": folders.roots.iter().map(|root| root.display().to_string()).collect::<Vec<_>>(),
            "new_project_folder": paths::expand(&config.new_project_folder).map(|path| path.display().to_string()),
            "terminal": config.allow_terminal,
            "portals": config.allow_portals,
            "display": config.share_display && display::SUPPORTED,
        })),
        "read_file" => {
            let path = folders.resolve_existing(string(request, "path")?)?;
            let metadata = std::fs::metadata(&path).map_err(|error| error.to_string())?;
            if !metadata.is_file() {
                return Err("Not a file".into());
            }
            if metadata.len() > MAX_FILE_BYTES {
                return Err(format!("The file is larger than {MAX_FILE_BYTES} bytes"));
            }
            let bytes = std::fs::read(&path).map_err(|error| error.to_string())?;
            use base64::Engine;
            // Text with NUL goes as base64 too: the server stores answers as
            // `jsonb`, which can't hold `\u0000`.
            Ok(match String::from_utf8(bytes) {
                Ok(text) if !text.contains('\0') => json!({"text":text}),
                Ok(text) => {
                    json!({"base64":base64::engine::general_purpose::STANDARD.encode(text)})
                }
                Err(error) => {
                    json!({"base64":base64::engine::general_purpose::STANDARD.encode(error.into_bytes())})
                }
            })
        }
        "write_file" => {
            let path = folders.resolve_for_write(string(request, "path")?)?;
            let bytes = match (request["text"].as_str(), request["base64"].as_str()) {
                (Some(text), None) => text.as_bytes().to_vec(),
                (None, Some(data)) => {
                    use base64::Engine;
                    base64::engine::general_purpose::STANDARD
                        .decode(data)
                        .map_err(|_| "Invalid base64")?
                }
                _ => return Err("Pass text or base64".into()),
            };
            std::fs::write(&path, &bytes).map_err(|error| error.to_string())?;
            Ok(json!({"bytes":bytes.len()}))
        }
        "list_dir" => {
            let path = folders.resolve_existing(string(request, "path")?)?;
            let mut entries = Vec::new();
            for entry in std::fs::read_dir(&path).map_err(|error| error.to_string())? {
                let entry = entry.map_err(|error| error.to_string())?;
                let kind = match entry.file_type() {
                    Ok(kind) if kind.is_symlink() => "symlink",
                    Ok(kind) if kind.is_dir() => "directory",
                    Ok(_) => "file",
                    Err(_) => continue,
                };
                entries.push(json!({"name":entry.file_name().to_string_lossy(), "kind":kind}));
                if entries.len() >= MAX_LIST_ENTRIES {
                    break;
                }
            }
            entries.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));
            Ok(json!({"entries":entries}))
        }
        "exec" => {
            if !config.allow_terminal {
                return Err("Terminal access is off on this runner".into());
            }
            let cwd = folders.resolve_existing(string(request, "cwd")?)?;
            let timeout = request["timeout_ms"]
                .as_u64()
                .unwrap_or(DEFAULT_TIMEOUT_MS)
                .min(MAX_TIMEOUT_MS);
            exec(
                string(request, "command")?,
                &cwd,
                Duration::from_millis(timeout),
            )
        }
        "screenshot" | "mouse_move" | "click" | "scroll" | "type_text" | "key" => {
            if !config.share_display {
                return Err("Display sharing is off on this runner".into());
            }
            display::perform(op, request)
        }
        _ => Err(format!("Unknown operation {op}")),
    }
}

fn requested(path: &str) -> Result<PathBuf, String> {
    let path = paths::expand(path).ok_or("Paths must be absolute")?;
    if path
        .components()
        .any(|part| matches!(part, Component::ParentDir))
    {
        return Err("Paths must not contain ..".into());
    }
    Ok(path)
}

/// The runner's folders, minus the paths threads must never reach.
struct Folders {
    roots: Vec<PathBuf>,
    protected: Vec<PathBuf>,
}

impl Folders {
    fn new(state: &Path, config: &Config) -> Self {
        let log = paths::log_file(state);
        let protected = [Some(state), log.parent()]
            .into_iter()
            .flatten()
            .map(|path| path.canonicalize().unwrap_or_else(|_| path.to_path_buf()))
            .collect();
        Self {
            roots: config.roots(),
            protected,
        }
    }

    fn inside(&self, path: &Path) -> Result<(), String> {
        if self
            .protected
            .iter()
            .any(|protected| path.starts_with(protected))
        {
            return Err("The path is the runner's own settings".into());
        }
        if self.roots.iter().any(|root| path.starts_with(root)) {
            Ok(())
        } else {
            Err("The path is outside the runner's folders".into())
        }
    }

    /// An existing path, after following every symlink, inside a runner folder.
    fn resolve_existing(&self, path: &str) -> Result<PathBuf, String> {
        let resolved = requested(path)?
            .canonicalize()
            .map_err(|error| error.to_string())?;
        self.inside(&resolved)?;
        Ok(resolved)
    }

    /// A file to write: its nearest existing ancestor must resolve inside a
    /// runner folder, missing parents are created there, and an existing final
    /// component that is a symlink must point inside one too.
    fn resolve_for_write(&self, path: &str) -> Result<PathBuf, String> {
        let path = requested(path)?;
        let name = path.file_name().ok_or("Name a file")?.to_owned();
        let parent = path.parent().ok_or("Name a file")?;
        let mut existing = parent;
        while !existing.exists() {
            existing = existing
                .parent()
                .ok_or("The path is outside the runner's folders")?;
        }
        let base = existing.canonicalize().map_err(|error| error.to_string())?;
        self.inside(&base)?;
        let parent = base.join(parent.strip_prefix(existing).map_err(|_| "Invalid path")?);
        std::fs::create_dir_all(&parent).map_err(|error| error.to_string())?;
        let parent = parent.canonicalize().map_err(|error| error.to_string())?;
        self.inside(&parent)?;
        let target = parent.join(name);
        if std::fs::symlink_metadata(&target)
            .is_ok_and(|metadata| metadata.file_type().is_symlink())
        {
            let resolved = target
                .canonicalize()
                .map_err(|_| "The link points nowhere")?;
            self.inside(&resolved)?;
            return Ok(resolved);
        }
        Ok(target)
    }
}

fn shell(command: &str) -> Command {
    #[cfg(windows)]
    {
        // `cmd` parses its own command line, so the command goes verbatim
        // rather than with the C runtime's quoting, which `cmd` doesn't undo.
        use std::os::windows::process::CommandExt;
        let mut shell = Command::new("cmd");
        shell.arg("/S").arg("/C").raw_arg(format!("\"{command}\""));
        shell
    }
    #[cfg(not(windows))]
    {
        // A login shell, so commands see the PATH the person's terminal has.
        let program = std::env::var("SHELL")
            .ok()
            .filter(|shell| Path::new(shell).is_absolute())
            .unwrap_or_else(|| {
                if cfg!(target_os = "macos") {
                    "/bin/zsh".into()
                } else {
                    "/bin/sh".into()
                }
            });
        let mut shell = Command::new(program);
        shell.args(["-lc", command]);
        shell
    }
}

/// Output read so far from one of a command's pipes, kept up to
/// `MAX_OUTPUT_BYTES`, and whether the pipe has closed.
#[derive(Default)]
struct Captured {
    bytes: Vec<u8>,
    truncated: bool,
    closed: bool,
}

fn capture(mut reader: impl Read + Send + 'static) -> Arc<Mutex<Captured>> {
    let captured = Arc::new(Mutex::new(Captured::default()));
    let shared = Arc::clone(&captured);
    std::thread::spawn(move || {
        let mut buffer = [0; 16 * 1024];
        loop {
            let count = reader.read(&mut buffer).unwrap_or(0);
            let mut captured = shared.lock().unwrap_or_else(|poison| poison.into_inner());
            if count == 0 {
                captured.closed = true;
                break;
            }
            let room = MAX_OUTPUT_BYTES.saturating_sub(captured.bytes.len());
            captured.bytes.extend_from_slice(&buffer[..count.min(room)]);
            captured.truncated |= count > room;
        }
    });
    captured
}

fn closed(captured: &Mutex<Captured>) -> bool {
    captured
        .lock()
        .unwrap_or_else(|poison| poison.into_inner())
        .closed
}

/// The output as text for the thread. NUL, as in `find -print0`, shows as
/// `␀`: the server stores answers as `jsonb`, which can't hold `\u0000`.
fn text(captured: &Mutex<Captured>) -> (String, bool) {
    let captured = captured.lock().unwrap_or_else(|poison| poison.into_inner());
    (
        String::from_utf8_lossy(&captured.bytes).replace('\0', "\u{2400}"),
        captured.truncated,
    )
}

/// On Windows, `taskkill /T` ends the command's whole process tree, as the
/// process group does on Unix.
#[cfg(windows)]
fn kill_group(child: &std::process::Child) {
    let _ = Command::new("taskkill")
        .args(["/T", "/F", "/PID"])
        .arg(child.id().to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

#[cfg(unix)]
fn kill_group(child: &std::process::Child) {
    unsafe extern "C" {
        fn kill(pid: i32, signal: i32) -> i32;
    }
    const SIGKILL: i32 = 9;
    if let Ok(pid) = i32::try_from(child.id()) {
        // SAFETY: signals the process group the shell leads (`process_group(0)`).
        unsafe { kill(-pid, SIGKILL) };
    }
}

/// Runs a command in its own process group. A timeout kills the whole group,
/// so pipelines and background jobs stop too. Background jobs the command
/// leaves running (a dev server) keep running; the answer comes once the shell
/// exits and the output has had `OUTPUT_GRACE` to arrive, not when they exit.
fn exec(command: &str, cwd: &Path, timeout: Duration) -> Result<Value, String> {
    const OUTPUT_GRACE: Duration = Duration::from_millis(500);
    let mut shell = shell(command);
    #[cfg(unix)]
    std::os::unix::process::CommandExt::process_group(&mut shell, 0);
    let mut child = shell
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("Could not start the shell: {error}"))?;
    let stdout = capture(child.stdout.take().ok_or("No stdout")?);
    let stderr = capture(child.stderr.take().ok_or("No stderr")?);
    let started = Instant::now();
    let (status, timed_out) = loop {
        if let Some(status) = child.try_wait().map_err(|error| error.to_string())? {
            break (Some(status), false);
        }
        if started.elapsed() >= timeout {
            kill_group(&child);
            let _ = child.kill();
            break (child.wait().ok(), true);
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let exited = Instant::now();
    while !(closed(&stdout) && closed(&stderr)) && exited.elapsed() < OUTPUT_GRACE {
        std::thread::sleep(Duration::from_millis(10));
    }
    let (stdout, stdout_truncated) = text(&stdout);
    let (stderr, stderr_truncated) = text(&stderr);
    Ok(json!({
        "exit_code": status.and_then(|status| status.code()),
        "timed_out": timed_out,
        "stdout": stdout,
        "stderr": stderr,
        "truncated": stdout_truncated || stderr_truncated,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixture {
        base: PathBuf,
        state: PathBuf,
        config: Config,
    }

    fn fixture(name: &str) -> Fixture {
        let base = std::env::temp_dir().join(format!("runner-ops-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        std::fs::create_dir_all(base.join("allowed/project")).unwrap();
        std::fs::create_dir_all(base.join("secret")).unwrap();
        std::fs::write(base.join("secret/key"), "hunter2").unwrap();
        std::fs::write(base.join("allowed/project/README.md"), "hello").unwrap();
        let base = base.canonicalize().unwrap();
        let config = Config {
            folders: vec![base.join("allowed").display().to_string()],
            new_project_folder: base.join("allowed").display().to_string(),
            allow_terminal: true,
            ..Config::default()
        };
        let state = base.join("state");
        Fixture {
            base,
            state,
            config,
        }
    }

    fn call(fixture: &Fixture, request: Value) -> Value {
        handle(&fixture.state, &fixture.config, &request)
    }

    #[test]
    fn reads_inside_and_refuses_outside_the_folders() {
        let f = fixture("read");
        let base = f.base.clone();
        let inside = call(
            &f,
            json!({"id":1,"op":"read_file","path":base.join("allowed/project/README.md")}),
        );
        assert_eq!(inside, json!({"id":1,"ok":true,"result":{"text":"hello"}}));

        let outside = call(
            &f,
            json!({"id":2,"op":"read_file","path":base.join("secret/key")}),
        );
        assert_eq!(outside["ok"], false);
        // A prefix that only shares a string with the folder is still outside.
        std::fs::create_dir_all(base.join("allowed-not")).unwrap();
        std::fs::write(base.join("allowed-not/file"), "x").unwrap();
        assert_eq!(
            call(
                &f,
                json!({"op":"read_file","path":base.join("allowed-not/file")})
            )["ok"],
            false
        );
        assert_eq!(
            call(&f, json!({"op":"read_file","path":"relative.txt"}))["ok"],
            false
        );
        let dotted = format!("{}/allowed/../secret/key", base.display());
        assert_eq!(
            call(&f, json!({"op":"read_file","path":dotted}))["ok"],
            false
        );
    }

    #[cfg(unix)]
    #[test]
    fn symlinks_cannot_lead_out_of_the_folders() {
        let f = fixture("links");
        let base = f.base.clone();
        std::os::unix::fs::symlink(base.join("secret"), base.join("allowed/escape")).unwrap();
        std::os::unix::fs::symlink(base.join("secret/key"), base.join("allowed/key-link")).unwrap();

        let read = call(
            &f,
            json!({"op":"read_file","path":base.join("allowed/escape/key")}),
        );
        assert_eq!(read["ok"], false, "{read}");
        let write = call(
            &f,
            json!({"op":"write_file","path":base.join("allowed/escape/new"),"text":"x"}),
        );
        assert_eq!(write["ok"], false, "{write}");
        let overwrite = call(
            &f,
            json!({"op":"write_file","path":base.join("allowed/key-link"),"text":"x"}),
        );
        assert_eq!(overwrite["ok"], false, "{overwrite}");
        assert_eq!(
            std::fs::read_to_string(base.join("secret/key")).unwrap(),
            "hunter2"
        );
        assert!(!base.join("secret/new").exists());
    }

    #[test]
    fn writes_create_missing_parents_inside_a_folder() {
        let f = fixture("write");
        let base = f.base.clone();
        let path = base.join("allowed/new/deep/file.txt");
        let response = call(&f, json!({"op":"write_file","path":path,"text":"hi"}));
        assert_eq!(response["result"]["bytes"], 2, "{response}");
        assert_eq!(std::fs::read_to_string(path).unwrap(), "hi");

        let listing = call(&f, json!({"op":"list_dir","path":base.join("allowed")}));
        let names: Vec<&str> = listing["result"]["entries"]
            .as_array()
            .unwrap()
            .iter()
            .map(|e| e["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, ["new", "project"]);
    }

    #[cfg(unix)]
    #[test]
    fn commands_need_terminal_access_and_a_folder() {
        let mut f = fixture("exec");
        let base = f.base.clone();
        let request = json!({"op":"exec","cwd":base.join("allowed/project"),"command":"pwd; echo oops >&2; exit 3"});
        let response = call(&f, request.clone());
        assert_eq!(response["result"]["exit_code"], 3, "{response}");
        assert_eq!(
            response["result"]["stdout"].as_str().unwrap().trim(),
            base.join("allowed/project").display().to_string()
        );
        assert_eq!(response["result"]["stderr"], "oops\n");

        let outside = call(
            &f,
            json!({"op":"exec","cwd":base.join("secret"),"command":"true"}),
        );
        assert_eq!(outside["ok"], false);

        let slow = call(
            &f,
            json!({"op":"exec","cwd":base.join("allowed"),"command":"sleep 5","timeout_ms":200}),
        );
        assert_eq!(slow["result"]["timed_out"], true, "{slow}");

        f.config.allow_terminal = false;
        assert_eq!(
            call(&f, request)["error"],
            "Terminal access is off on this runner"
        );
    }

    #[cfg(unix)]
    #[test]
    fn the_runners_own_settings_are_out_of_reach_inside_a_folder() {
        let mut f = fixture("state");
        let base = f.base.clone();
        // The default `~` share used to contain the state directory.
        f.state = base.join("allowed/.runner");
        std::fs::create_dir_all(&f.state).unwrap();
        std::fs::write(f.state.join("connection.curlrc"), "secret").unwrap();
        std::os::unix::fs::symlink(&f.state, base.join("allowed/project/state-link")).unwrap();

        for request in [
            json!({"op":"read_file","path":f.state.join("connection.curlrc")}),
            json!({"op":"read_file","path":base.join("allowed/project/state-link/connection.curlrc")}),
            json!({"op":"write_file","path":f.state.join("config.json"),"text":"{}"}),
            json!({"op":"write_file","path":base.join("allowed/project/state-link/new"),"text":"x"}),
            json!({"op":"list_dir","path":f.state}),
            json!({"op":"exec","cwd":f.state,"command":"true"}),
        ] {
            let response = call(&f, request.clone());
            assert_eq!(
                response["error"], "The path is the runner's own settings",
                "{request}"
            );
        }
        assert!(!f.state.join("config.json").exists());
        assert!(!f.state.join("new").exists());
        let listing = call(&f, json!({"op":"list_dir","path":base.join("allowed")}));
        assert_eq!(listing["ok"], true, "the folder around it still works");
    }

    #[test]
    fn text_with_nul_is_read_as_base64() {
        let f = fixture("nul");
        let path = f.base.join("allowed/list");
        std::fs::write(&path, "a\0b").unwrap();
        let response = call(&f, json!({"op":"read_file","path":path}));
        assert_eq!(response["result"], json!({"base64":"YQBi"}), "{response}");
    }

    #[cfg(unix)]
    #[test]
    fn commands_answer_without_waiting_for_what_they_leave_running() {
        let f = fixture("background");
        let cwd = f.base.join("allowed");
        let started = Instant::now();
        let background = call(
            &f,
            json!({"op":"exec","cwd":cwd,"command":"sleep 5 & echo started"}),
        );
        assert_eq!(background["result"]["stdout"], "started\n", "{background}");
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "{:?}",
            started.elapsed()
        );

        let started = Instant::now();
        let pipeline = call(
            &f,
            json!({"op":"exec","cwd":cwd,"command":"sleep 5 | cat","timeout_ms":300}),
        );
        assert_eq!(pipeline["result"]["timed_out"], true, "{pipeline}");
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "{:?}",
            started.elapsed()
        );

        let nul = call(
            &f,
            json!({"op":"exec","cwd":cwd,"command":"printf 'a\\0b'"}),
        );
        assert_eq!(nul["result"]["stdout"], "a\u{2400}b", "{nul}");
    }

    #[test]
    fn display_operations_need_display_sharing() {
        let f = fixture("display");
        assert!(!f.config.share_display);
        let response = call(&f, json!({"op":"screenshot"}));
        assert_eq!(response["error"], "Display sharing is off on this runner");
    }
}
