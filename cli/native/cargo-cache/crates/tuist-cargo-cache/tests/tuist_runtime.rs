#![cfg(unix)]
use std::{fs, os::unix::fs::PermissionsExt, path::Path, process::Command};
use tuist_cargo_cache_core::{CacheDigest, LocalCas};

fn runtime(root: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_tuist-cargo-cache"));
    command
        .current_dir(root)
        .env("TUIST_CARGO_NATIVE", "1")
        .env("TUIST_CARGO_CACHE_DIR", root.join("cache"))
        .env("TUIST_CARGO_CACHE_GC_INTERVAL", "0s")
        .env("TUIST_CARGO_CACHE_REMOTE_URL", "")
        .env("TUIST_CARGO_CACHE_TARGET_VIEWS", "false")
        .env("TUIST_CARGO_CACHE_SCHEDULER_ENABLED", "false");
    command
}

fn script(root: &Path, name: &str, body: &str) -> std::path::PathBuf {
    let path = root.join(name);
    fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    path
}

#[test]
fn private_cleanup_collects_the_store_without_invoking_cargo() {
    let root = tempfile::tempdir().unwrap();
    let cas = LocalCas::new(root.path().join("cache/actions"));
    let contents = vec![1u8; 128 * 1024];
    let digest = CacheDigest::blake3(&contents);
    let blob = cas.store_bytes(&digest, &contents).unwrap();
    filetime::set_file_mtime(&blob, filetime::FileTime::from_unix_time(1, 0)).unwrap();
    let cargo = script(root.path(), "cargo", "touch cargo-was-invoked; exit 97");
    let output = runtime(root.path())
        .env("CARGO", cargo)
        .env("TUIST_CARGO_CACHE_GC_MAX_SIZE", "0B")
        .arg("__tuist_gc_automatic")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(!root.path().join("cargo-was-invoked").exists());
    assert!(
        !blob.exists(),
        "the real shipped runtime must collect old CAS objects"
    );
}

#[test]
fn failed_cache_setup_falls_back_once_and_preserves_the_cargo_result() {
    let root = tempfile::tempdir().unwrap();
    fs::write(root.path().join("cache"), "not a directory").unwrap();
    let cargo = script(
        root.path(),
        "cargo",
        "echo invocation >> cargo-invocations; printf '%s\\n' \"$@\"; exit 31",
    );
    let output = runtime(root.path())
        .env("CARGO", cargo)
        .args(["build", "--locked", "--offline"])
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(31));
    assert_eq!(
        fs::read_to_string(root.path().join("cargo-invocations"))
            .unwrap()
            .lines()
            .count(),
        1
    );
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        "build\n--locked\n--offline\n"
    );
}

#[test]
fn cargo_failure_is_not_rerun_and_progress_policy_is_preserved() {
    for block_store in [false, true] {
        let root = tempfile::tempdir().unwrap();
        fs::create_dir(root.path().join("src")).unwrap();
        fs::write(
            root.path().join("Cargo.toml"),
            "[package]\nname = 'tuist_status_probe'\nversion = '0.1.0'\nedition = '2024'\n",
        )
        .unwrap();
        fs::write(root.path().join("src/lib.rs"), "pub fn example() {}\n").unwrap();
        if block_store {
            fs::create_dir(root.path().join("cache")).unwrap();
            fs::write(root.path().join("cache/actions"), "not a directory").unwrap();
        }
        let cargo = script(
            root.path(),
            "cargo",
            "if [ \"$1\" = build ]; then echo invocation >> cargo-invocations; echo \"$CARGO_TERM_PROGRESS_WHEN\"; exit 31; fi; exec \"$ACTUAL_CARGO\" \"$@\"",
        );
        let output = runtime(root.path())
            .env("CARGO", cargo)
            .env("ACTUAL_CARGO", env!("CARGO"))
            .env("CARGO_TERM_PROGRESS_WHEN", "always")
            .env("CARGO_TERM_PROGRESS_WIDTH", "80")
            .arg("build")
            .output()
            .unwrap();
        assert_eq!(
            output.status.code(),
            Some(31),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(String::from_utf8(output.stdout).unwrap(), "always\n");
        assert_eq!(
            fs::read_to_string(root.path().join("cargo-invocations"))
                .unwrap()
                .lines()
                .count(),
            1
        );
    }
}

#[test]
fn incrementally_compiled_workspace_warnings_are_observed_without_changing_cargo_status() {
    let root = tempfile::tempdir().unwrap();
    fs::create_dir(root.path().join("src")).unwrap();
    fs::create_dir(root.path().join("observations")).unwrap();
    fs::write(
        root.path().join(".tuist_cargo_cache.toml"),
        "not valid configuration !",
    )
    .unwrap();
    fs::write(
        root.path().join("Cargo.toml"),
        "[package]\nname = 'tuist_observed_bypass'\nversion = '0.1.0'\nedition = '2024'\n",
    )
    .unwrap();
    fs::write(
        root.path().join("src/lib.rs"),
        "fn unused_private_function() {}\n",
    )
    .unwrap();
    let origin = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs_f64();
    let output = runtime(root.path())
        .env("CARGO_INCREMENTAL", "1")
        .env("CARGO_TERM_PROGRESS_WHEN", "never")
        .env("TUIST_CARGO_SESSION", root.path().join("observations"))
        .env("TUIST_CARGO_STARTED", origin.to_string())
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stderr).contains("unused_private_function"));
    let observations: Vec<serde_json::Value> = fs::read_dir(root.path().join("observations"))
        .unwrap()
        .map(|entry| serde_json::from_slice(&fs::read(entry.unwrap().path()).unwrap()).unwrap())
        .collect();
    assert!(observations.iter().any(|row| {
        row["name"] == "tuist_observed_bypass"
            && row["diagnostics"]
                .as_array()
                .is_some_and(|items| items.iter().any(|item| item["severity"] == "warning"))
    }));
}

#[test]
fn unavailable_public_report_storage_does_not_change_cargo_status() {
    let root = tempfile::tempdir().unwrap();
    let destination = root.path().join("blocked-report");
    fs::write(&destination, "not a directory").unwrap();
    fs::create_dir(root.path().join("src")).unwrap();
    fs::write(
        root.path().join("Cargo.toml"),
        "[package]\nname='tuist_report_failure'\nversion='0.1.0'\nedition='2024'\n",
    )
    .unwrap();
    fs::write(root.path().join("src/lib.rs"), "pub fn example() {}\n").unwrap();
    let output = runtime(root.path())
        .env("CARGO_INCREMENTAL", "0")
        .env("TUIST_CARGO_CACHE_PUBLIC_REPORT_DIR", &destination)
        .args(["build", "--offline"])
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(fs::read_to_string(destination).unwrap(), "not a directory");
}

#[test]
fn public_inspection_records_real_library_decisions_without_private_inputs() {
    let root = tempfile::tempdir().unwrap();
    fs::create_dir(root.path().join("src")).unwrap();
    fs::create_dir(root.path().join("details")).unwrap();
    fs::write(
        root.path().join("Cargo.toml"),
        "[package]\nname='tuist_public_cache_probe'\nversion='0.1.0'\nedition='2024'\n",
    )
    .unwrap();
    fs::write(
        root.path().join("src/lib.rs"),
        "pub fn example() -> usize { 42 }\n",
    )
    .unwrap();
    fs::write(
        root.path().join("build.rs"),
        "fn main() { println!(\"cargo:rerun-if-changed=build.rs\"); }\n",
    )
    .unwrap();
    for _ in 0..2 {
        let target = root.path().join("target");
        if target.exists() {
            fs::remove_dir_all(target).unwrap();
        }
        let output = runtime(root.path())
            .env("CARGO_INCREMENTAL", "0")
            .env("RUSTFLAGS", "--cfg tuist_secret_not_in_reports")
            .env("PRIVATE_SECRET", "do-not-publish-me")
            .env(
                "TUIST_CARGO_CACHE_PUBLIC_REPORT_DIR",
                root.path().join("details"),
            )
            .args(["build", "--offline"])
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let contents = fs::read_dir(root.path().join("details"))
        .unwrap()
        .map(|entry| fs::read_to_string(entry.unwrap().path()).unwrap())
        .collect::<Vec<_>>()
        .join("\n");
    assert!(!contents.contains("do-not-publish-me"));
    assert!(!contents.contains("tuist_secret_not_in_reports"));
    assert!(!contents.contains(&root.path().to_string_lossy().to_string()));
    let records = contents
        .lines()
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
        .collect::<Vec<_>>();
    assert!(records.iter().any(|row| row["record"] == "task"
        && row["status"] == "unconsulted"
        && row["name"] == "tuist_public_cache_probe"
        && row["kind"] == "rust"));
    assert!(
        records
            .iter()
            .any(|row| row["record"] == "task" && row["status"] == "hit")
    );
    assert!(records.iter().any(|row| row["record"] == "task"
        && row["kind"] == "build_script"
        && row["status"] == "unconsulted"));
    assert!(
        records
            .iter()
            .any(|row| row["record"] == "adapter" && row["kind"] == "build_script")
    );
    assert!(
        records
            .iter()
            .any(|row| row["record"] == "timing" && row["operation"] == "read")
    );
    assert!(
        !records.iter().any(|row| row["record"] == "cas"),
        "local restores must not invent remote operations"
    );
}
