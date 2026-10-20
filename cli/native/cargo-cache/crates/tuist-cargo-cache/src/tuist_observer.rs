//! Tuist-owned compiler telemetry. Runs only for actual compiler processes,
//! never on cache hits, and never participates in authentication or cache keys.
use serde_json::{Value, json};
use std::{
    ffi::OsString,
    process::Command,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

#[cfg(unix)]
pub(crate) fn bypass_output(
    command: &mut Command,
    mut action: Option<crate::supervision::Action>,
) -> std::io::Result<std::process::Output> {
    use std::io::{Read, Write};
    let mut child = command.stderr(std::process::Stdio::piped()).spawn()?;
    if let Some(action) = &mut action {
        action.started();
    }
    let mut stream = child.stderr.take().expect("stderr was piped");
    let mut captured = Vec::new();
    let mut buffer = [0u8; 16 * 1024];
    let mut sink = std::io::stderr().lock();
    loop {
        let count = match stream.read(&mut buffer) {
            Ok(count) => count,
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(error) => {
                let _ = child.wait();
                return Err(error);
            }
        };
        if count == 0 {
            break;
        }
        let _ = sink.write_all(&buffer[..count]);
        let retained = count.min((2 * 1024 * 1024usize).saturating_sub(captured.len()));
        captured.extend_from_slice(&buffer[..retained]);
    }
    Ok(std::process::Output {
        status: child.wait()?,
        stdout: Vec::new(),
        stderr: captured,
    })
}

pub(crate) fn record_command(
    command: &Command,
    started: SystemTime,
    elapsed: Duration,
    success: bool,
    stderr: &[u8],
) {
    if !matches!(
        std::path::Path::new(command.get_program())
            .file_name()
            .and_then(|name| name.to_str()),
        Some("rustc" | "rustc.exe")
    ) {
        return;
    }
    let args: Vec<_> = command.get_args().map(OsString::from).collect();
    record(&args, started, elapsed, success, stderr);
}

pub(crate) fn record(
    args: &[OsString],
    started: SystemTime,
    elapsed: Duration,
    success: bool,
    stderr: &[u8],
) {
    let Ok(session) = std::env::var("TUIST_CARGO_SESSION") else {
        return;
    };
    let Some(origin) = std::env::var("TUIST_CARGO_STARTED")
        .ok()
        .and_then(|v| v.parse::<f64>().ok())
        .filter(|v| v.is_finite())
    else {
        return;
    };
    let args: Vec<_> = args.iter().filter_map(|a| a.to_str()).collect();
    if args.first().is_some_and(|argument| {
        matches!(
            std::path::Path::new(argument)
                .file_name()
                .and_then(|name| name.to_str()),
            Some("rustc" | "rustc.exe")
        )
    }) {
        return;
    }
    if args.iter().any(|a| a.starts_with("--print")) {
        return;
    }
    let Some(source) = args.iter().find(|a| a.ends_with(".rs")) else {
        return;
    };
    let option = |name: &str| {
        args.windows(2)
            .find(|pair| pair[0] == name)
            .map(|pair| pair[1])
    };
    let dependencies: Vec<_> = args
        .windows(2)
        .filter(|pair| pair[0] == "--extern")
        .take(5000)
        .map(|pair| pair[1].split('=').next().unwrap_or(""))
        .collect();
    let diagnostics: Vec<Value> = stderr.split(|b| *b == b'\n').filter(|line| line.len() <= 1_000_000).filter_map(|line| {
        let value: Value = serde_json::from_slice(line).ok()?;
        let level = value.get("level")?.as_str()?;
        if !matches!(level, "warning" | "error") { return None; }
        let message: String = value.get("message")?.as_str()?.chars().take(10_000).collect();
        let span = value.get("spans").and_then(Value::as_array).and_then(|spans| spans.iter().find(|span| span.get("is_primary").and_then(Value::as_bool) == Some(true)));
        Some(json!({"severity": level, "message": message, "file": span.and_then(|s| s.get("file_name")), "line": span.and_then(|s| s.get("line_start"))}))
    }).take(100).collect();
    let epoch = started.duration_since(UNIX_EPOCH).unwrap_or_default();
    let milliseconds = |seconds: f64| (seconds * 1000.0).round().clamp(0.0, u32::MAX as f64) as u32;
    let value = json!({
        "name": option("--crate-name").unwrap_or("unknown"), "source": source,
        "kind": if args.contains(&"--test") { "test" } else { option("--crate-type").unwrap_or("lib") },
        "dependencies": dependencies, "start_offset_ms": milliseconds(epoch.as_secs_f64() - origin),
        "duration_ms": milliseconds(elapsed.as_secs_f64()), "status": if success { "success" } else { "failure" }, "diagnostics": diagnostics
    });
    let path = std::path::Path::new(&session).join(format!(
        "{}-{}.json",
        std::process::id(),
        epoch.as_nanos()
    ));
    if let Ok(bytes) = serde_json::to_vec(&value) {
        let _ = std::fs::write(path, bytes);
    }
}
