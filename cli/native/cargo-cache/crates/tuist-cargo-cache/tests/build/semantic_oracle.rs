//! A real compiler is the authority for whether a perturbation changes behavior.
//! Every case proves a hit before the edit, then compares the changed cached
//! build with an uncached rustc build and requires that the old entry missed.
use super::*;

#[derive(Clone, Copy)]
struct State {
    cfg: &'static str,
    environment: &'static str,
    included: &'static str,
    module_a: &'static str,
    module_b: &'static str,
    assertions: bool,
}

const BASE: State = State {
    cfg: "oracle_a",
    environment: "env-a",
    included: "include-a",
    module_a: "a",
    module_b: "b",
    assertions: false,
};

fn write_state(project: &Path, state: State) {
    std::fs::write(project.join("src/value.txt"), state.included).unwrap();
    for (module, value) in [("a", state.module_a), ("b", state.module_b)] {
        std::fs::write(
            project.join(format!("src/{module}.rs")),
            format!("pub fn value() -> &'static str {{ {value:?} }}\n"),
        )
        .unwrap();
    }
}

fn succeeded(command: &mut Command) -> std::process::Output {
    let output = command.output().unwrap();
    assert!(
        output.status.success(),
        "{command:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    output
}

/// Link an observer against the produced library so an rlib's runtime behavior,
/// rather than its path or incidental binary metadata, is what gets compared.
fn observe(library: &Path) -> String {
    let observer = tempfile::tempdir().unwrap();
    let source = observer.path().join("observe.rs");
    let executable = observer
        .path()
        .join(format!("observe{}", std::env::consts::EXE_SUFFIX));
    std::fs::write(&source, "fn main() { print!(\"{}\", fixture::value()); }\n").unwrap();
    let mut command = Command::new("rustc");
    command
        .arg(&source)
        .args(["--edition=2021", "--extern"])
        .arg(format!("fixture={}", library.display()));
    // An rlib built with `-Zembed-metadata=no` is linkable only together with
    // its rmeta, which Cargo passes as a second `--extern` for the same crate.
    let metadata = library.with_extension("rmeta");
    if metadata.is_file() {
        command
            .arg("--extern")
            .arg(format!("fixture={}", metadata.display()));
    }
    succeeded(command.arg("-o").arg(&executable));
    String::from_utf8(succeeded(&mut Command::new(executable)).stdout).unwrap()
}

fn bare(project: &Path, state: State) -> String {
    write_state(project, state);
    let output = tempfile::tempdir().unwrap();
    let library = output.path().join("libfixture.rlib");
    let assertion_flags = if state.assertions {
        ["-Cdebug-assertions=no", "-Cdebug-assertions=yes"]
    } else {
        ["-Cdebug-assertions=yes", "-Cdebug-assertions=no"]
    };
    succeeded(
        Command::new("rustc")
            .current_dir(project)
            .args([
                "--crate-type=rlib",
                "--crate-name=fixture",
                "--edition=2021",
                "src/lib.rs",
                "--cfg",
                state.cfg,
                "-o",
            ])
            .arg(&library)
            .args(assertion_flags)
            .env("ORACLE_VALUE", state.environment),
    );
    observe(&library)
}

fn cached(project: &Path, store: &Path, state: State) -> (String, serde_json::Value) {
    write_state(project, state);
    let target = project.join("target");
    if target.exists() {
        std::fs::remove_dir_all(&target).unwrap();
    }
    let report = tempfile::tempdir().unwrap();
    let assertion_flags = if state.assertions {
        ["-Cdebug-assertions=no", "-Cdebug-assertions=yes"]
    } else {
        ["-Cdebug-assertions=yes", "-Cdebug-assertions=no"]
    };
    let flags = format!(
        "--cfg {} {} {}",
        state.cfg, assertion_flags[0], assertion_flags[1]
    );
    let encoded_flags = flags.split_whitespace().collect::<Vec<_>>().join("\x1f");
    let (stats, _) = build_with(
        project,
        store,
        &report.path().join("stats.json"),
        &[
            ("TUIST_CARGO_CACHE_TARGET_VIEWS", "0"),
            ("TUIST_CARGO_CACHE_INCREMENTAL", "0"),
            ("TUIST_CARGO_CACHE_LEARNED_INCREMENTAL", "0"),
            ("TUIST_CARGO_CACHE_VERIFY", "0"),
            ("TUIST_CARGO_CACHE_VERIFY_SAMPLE_RATE", "0"),
            ("RUSTFLAGS", &flags),
            ("CARGO_ENCODED_RUSTFLAGS", &encoded_flags),
            ("ORACLE_VALUE", state.environment),
        ],
    );
    (observe(&unit_library(&target.join("debug"))), stats)
}

/// The fixture's rlib at its unit path, where its rmeta sits beside it. From
/// Cargo 1.100 rlibs are built with `-Zembed-metadata=no`, so the copy Cargo
/// uplifts to `libfixture.rlib` cannot be linked against on its own.
fn unit_library(profile: &Path) -> PathBuf {
    let libraries = find_files(profile, |path| {
        file_name_is(path, |name| {
            name.starts_with("libfixture-") && name.ends_with(".rlib")
        })
    });
    assert_eq!(libraries.len(), 1, "one fixture unit: {libraries:?}");
    libraries.into_iter().next().unwrap()
}

#[test]
fn semantic_changes_miss_and_match_bare_rustc() {
    let cases = [
        (
            "cfg value",
            State {
                cfg: "oracle_b",
                ..BASE
            },
        ),
        (
            "last-wins codegen order",
            State {
                assertions: true,
                ..BASE
            },
        ),
        (
            "env! value",
            State {
                environment: "env-b",
                ..BASE
            },
        ),
        (
            "include_str! contents",
            State {
                included: "include-b",
                ..BASE
            },
        ),
        (
            "module path-to-content mapping",
            State {
                module_a: BASE.module_b,
                module_b: BASE.module_a,
                ..BASE
            },
        ),
    ];
    for (name, changed) in cases {
        let project = tempfile::tempdir().unwrap();
        let store = tempfile::tempdir().unwrap();
        write_project(project.path());
        std::fs::write(
            project.path().join("src/lib.rs"),
            r#"
mod a;
mod b;
pub fn value() -> String {
    format!("{}|{}|{}|{}|{}|{}", cfg!(debug_assertions), if cfg!(oracle_b) { "b" } else { "a" },
        env!("ORACLE_VALUE"), include_str!("value.txt"), a::value(), b::value())
}
"#,
        )
        .unwrap();
        let before = bare(project.path(), BASE);
        let after = bare(project.path(), changed);
        assert_ne!(
            before, after,
            "{name}: rustc must prove the change affects behavior"
        );

        let (actual, cold) = cached(project.path(), store.path(), BASE);
        assert_eq!(actual, before, "{name}: cold build");
        assert_eq!(count(&cold, "hits"), 0, "{name}: {cold}");
        let (actual, warm) = cached(project.path(), store.path(), BASE);
        assert_eq!(actual, before, "{name}: warm build");
        assert_eq!(
            count(&warm, "hits"),
            1,
            "{name}: unchanged input must hit: {warm}"
        );

        let (actual, edited) = cached(project.path(), store.path(), changed);
        assert_eq!(
            actual, after,
            "{name}: changed cached build must match bare rustc"
        );
        assert_eq!(
            count(&edited, "hits"),
            0,
            "{name}: semantic edit must miss: {edited}"
        );
        let (actual, warm) = cached(project.path(), store.path(), changed);
        assert_eq!(actual, after, "{name}: repeated changed build");
        assert_eq!(
            count(&warm, "hits"),
            1,
            "{name}: changed input must become cacheable: {warm}"
        );
    }
}
