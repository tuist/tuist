//! `luft-runner`: the daemon the service manager starts (`run`) and the
//! commands the app uses to manage it. Every command prints one JSON value.
use serde_json::{Value, json};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use luft_runner::config::{Change, Config};
use luft_runner::connection::{self, Connection};
use luft_runner::status::{self, Status};
use luft_runner::{display, ops, paths, service};

const USAGE: &str = "usage: luft-runner <status | install | uninstall | set <key> <value> | reset | connect <server> <runner-id> (secret on stdin) | disconnect | request-permissions | serve-stdio | run>";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(state) = paths::state_dir() else {
        fail("Could not find the home folder");
    };
    let result = match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["status"] => Ok(report(&state)),
        ["install"] => std::env::current_exe()
            .map_err(|error| error.to_string())
            .and_then(|program| install(&program, &state)),
        ["uninstall"] => service::uninstall().map(|()| report(&state)),
        ["set", key, value] => set(&state, key, value),
        ["reset"] => Config::default().save(&state).map(|()| report(&state)),
        ["connect", server, runner_id] => connect(&state, server, runner_id),
        ["disconnect"] => Connection::remove(&state).map(|()| report(&state)),
        ["request-permissions"] => {
            paths::write_atomically(&paths::permission_request_file(&state), b"")
                .map(|()| report(&state))
                .map_err(|error| error.to_string())
        }
        ["serve-stdio"] => serve_stdio(&state),
        ["run"] => run(&state),
        _ => Err(USAGE.to_string()),
    };
    match result {
        Ok(value) => println!("{value}"),
        Err(error) => fail(&error),
    }
}

fn fail(error: &str) -> ! {
    println!("{}", json!({ "error": error }));
    std::process::exit(1);
}

/// Everything the settings pane shows, in one value.
fn report(state: &Path) -> Value {
    let config = Config::load(state);
    let installation = service::status();
    // A heartbeat outlives the daemon by a few seconds, so right after
    // `uninstall` it still looks fresh; only a loaded service is running.
    let running = Status::read(state)
        .filter(|status| status.fresh(status::now()))
        .filter(|_| installation.loaded);
    let this_program = std::env::current_exe()
        .ok()
        .and_then(|path| path.canonicalize().ok());
    let current = match (&installation.program, &this_program) {
        (Some(installed), Some(this)) => installed.canonicalize().ok().as_ref() == Some(this),
        _ => false,
    };
    let (config, config_error) = match config {
        Ok(config) => (config, None),
        // Not the defaults: the daemon serves its last good settings, which
        // may share more, and the pane must not claim less is shared.
        Err(error) => (Config::locked(), Some(error)),
    };
    json!({
        "installed": installation.installed,
        "loaded": installation.loaded,
        // The installed service starts this copy of the runner, not one from
        // another copy of the app that may since have moved.
        "current": current,
        "running": running.is_some(),
        "status": running,
        "config": config,
        "connection": Connection::load(state),
        "config_error": config_error,
        "display_supported": display::SUPPORTED,
        "log": paths::log_file(state),
    })
}

fn install(program: &Path, state: &Path) -> Result<Value, String> {
    // Write the defaults first, so the daemon and the app agree from the start.
    let config = Config::load(state)?;
    config.save(state)?;
    // The default projects folder may not exist yet; a runner folder that
    // doesn't exist shares nothing.
    if let Some(folder) = paths::expand(&config.new_project_folder) {
        std::fs::create_dir_all(folder).map_err(|error| error.to_string())?;
    }
    service::install(program, state)?;
    Ok(report(state))
}

/// Saves the server connection. The secret comes on stdin, so no other process
/// sees it in an argument list.
fn connect(state: &Path, server: &str, runner_id: &str) -> Result<Value, String> {
    let mut token = String::new();
    std::io::stdin()
        .read_line(&mut token)
        .map_err(|error| error.to_string())?;
    let connection = Connection {
        server: server.into(),
        runner_id: runner_id.into(),
    };
    connection.save(state, token.trim())?;
    Ok(report(state))
}

fn set(state: &Path, key: &str, value: &str) -> Result<Value, String> {
    let mut config = Config::load(state)?;
    config.apply(&Change::parse(key, value)?)?;
    config.save(state)?;
    Ok(report(state))
}

/// Runs operations from JSON lines on stdin, one response line each. This is the
/// transport-free form of what the server connection will carry, so the
/// operations can be exercised locally before the server has a runner endpoint.
fn serve_stdio(state: &Path) -> Result<Value, String> {
    let stdout = std::io::stdout();
    for line in std::io::stdin().lock().lines() {
        let line = line.map_err(|error| error.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let response = match serde_json::from_str::<Value>(&line) {
            Ok(request) => ops::handle(state, &Config::load(state)?, &request),
            Err(_) => json!({"id":null, "ok":false, "error":"Invalid JSON"}),
        };
        let mut out = stdout.lock();
        writeln!(out, "{response}").map_err(|error| error.to_string())?;
        out.flush().map_err(|error| error.to_string())?;
    }
    Ok(Value::Null)
}

/// Keeps the machine awake while plugged in, for as long as the daemon lives.
/// `caffeinate -s` only holds the assertion on AC power; `-w` ends it with us.
struct Awake(Option<std::process::Child>);

impl Awake {
    fn set(&mut self, on: bool) {
        if let Some(child) = &mut self.0
            && (!on || child.try_wait().ok().flatten().is_some())
        {
            let _ = child.kill();
            let _ = child.wait();
            self.0 = None;
        }
        if on && self.0.is_none() && cfg!(target_os = "macos") {
            self.0 = std::process::Command::new("/usr/bin/caffeinate")
                .args(["-s", "-w", &std::process::id().to_string()])
                .spawn()
                .ok();
        }
    }
}

fn run(state: &Path) -> Result<Value, String> {
    std::fs::create_dir_all(state).map_err(|error| error.to_string())?;
    eprintln!(
        "luft-runner {} started (pid {})",
        luft_runner::VERSION,
        std::process::id()
    );
    let mut awake = Awake(None);
    let link = Arc::new(Mutex::new(connection::State::Connecting));
    let reported = Arc::clone(&link);
    connection::run(state.to_path_buf(), move |state| {
        let mut current = reported.lock().unwrap_or_else(|poison| poison.into_inner());
        if *current != state {
            eprintln!("connection: {}", state.id());
            *current = state;
        }
    });
    let mut last_config: Option<Config> = None;
    loop {
        let config = Config::load_for_serving(state);
        // Turning display sharing on, or the app asking, lists the daemon in
        // System Settings and shows macOS's prompts once.
        let asked = std::fs::remove_file(paths::permission_request_file(state)).is_ok();
        let turned_on =
            config.share_display && last_config.as_ref().is_some_and(|last| !last.share_display);
        if asked || turned_on {
            display::request_missing();
        }
        if last_config.as_ref() != Some(&config) {
            let roots: Vec<PathBuf> = config.roots();
            eprintln!(
                "runner {:?}: {} folder(s), display {}, terminal {}",
                config.name,
                roots.len(),
                config.share_display,
                config.allow_terminal
            );
            last_config = Some(config.clone());
        }
        awake.set(config.keep_awake);
        let permissions = display::permissions();
        let heartbeat = Status {
            pid: std::process::id(),
            version: luft_runner::VERSION.into(),
            heartbeat: status::now(),
            folders: config.roots().len(),
            activity: if connection::busy() { "busy" } else { "idle" }.into(),
            connection: link
                .lock()
                .unwrap_or_else(|poison| poison.into_inner())
                .id()
                .into(),
            server: Connection::load(state).map(|connection| connection.server),
            keeping_awake: awake.0.is_some(),
            screen_recording: permissions.screen_recording,
            accessibility: permissions.accessibility,
        };
        if let Err(error) = heartbeat.write(state) {
            eprintln!("Could not write the runner status: {error}");
        }
        std::thread::sleep(Duration::from_secs(5));
    }
}
