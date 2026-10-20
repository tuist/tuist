#[cfg(unix)]
use super::shims::remove_stranded_binary_shims;
use super::shims::{ShimLease, binary_identity, installation_identity};
use super::shims::{first_in_path, is_shim_directory, mark_shim_directory};
use super::*;
use crate::config::SummaryStyle;

#[test]
fn low_disk_session_settings_require_an_explicit_session_policy() {
    let config = Config::for_test(Path::new("/cache"));
    let absolute = |path: &Path| {
        std::path::absolute(path)
            .unwrap()
            .to_string_lossy()
            .into_owned()
    };
    assert_eq!(
        session_gc_environment(&config, Some(crate::config::MinFree::Bytes(90))),
        vec![
            (GC_AUTO_ENV.to_string(), "1".to_string()),
            (GC_MIN_FREE_ENV.to_string(), "90".to_string()),
            (GC_CACHE_DIR_ENV.to_string(), absolute(Path::new("/cache"))),
            (
                GC_TARGET_ROOT_ENV.to_string(),
                absolute(&config.target.root)
            ),
            (
                GC_EXECUTABLE_ENV.to_string(),
                absolute(&std::env::current_exe().unwrap()),
            ),
        ]
    );
    assert_eq!(
        low_disk_min_free_from_environment(None, Some("90")),
        None,
        "a persistent wrapper has no session setting"
    );
    assert_eq!(
        low_disk_min_free_from_environment(Some("0"), Some("90")),
        None,
        "gc.auto=false is carried through the session"
    );
    assert_eq!(
        low_disk_min_free_from_environment(Some("1"), None),
        None,
        "a missing floor leaves the hook disabled"
    );
    assert_eq!(
        low_disk_min_free_from_environment(Some("1"), Some("share")),
        Some(crate::config::MinFree::ShareOfDisk)
    );
}

#[test]
fn low_disk_session_cache_dir_is_absolute_for_shims() {
    let config = Config::for_test(Path::new("relative-cache"));
    let environment = session_gc_environment(&config, None);
    let cache_dir = environment
        .iter()
        .find_map(|(name, value)| (name == GC_CACHE_DIR_ENV).then_some(value));
    let expected = std::path::absolute("relative-cache")
        .unwrap()
        .to_string_lossy()
        .into_owned();

    assert_eq!(cache_dir, Some(&expected));
}

#[test]
fn low_disk_session_target_root_is_absolute_for_shims() {
    let mut config = Config::for_test(Path::new("cache"));
    config.target.root = PathBuf::from("relative-targets");
    let environment = session_gc_environment(&config, None);
    let target_root = environment
        .iter()
        .find_map(|(name, value)| (name == GC_TARGET_ROOT_ENV).then_some(value));
    let expected = std::path::absolute("relative-targets")
        .unwrap()
        .to_string_lossy()
        .into_owned();

    assert_eq!(target_root, Some(&expected));
}

#[test]
fn clippy_workspace_wrapper_is_peeled_before_rustc_parsing() {
    let arguments = vec![
        Path::new("toolchain")
            .join(format!("rustc{}", std::env::consts::EXE_SUFFIX))
            .into_os_string(),
        "--crate-name".into(),
        "fixture".into(),
        "src/lib.rs".into(),
    ];
    let driver =
        Path::new("toolchain").join(format!("clippy-driver{}", std::env::consts::EXE_SUFFIX));

    let (wrapper_argument, compiler_arguments) =
        workspace_wrapper_arguments(driver.as_os_str(), &arguments);

    assert_eq!(wrapper_argument, Some(arguments[0].as_os_str()));
    assert_eq!(compiler_arguments, &arguments[1..]);
}

#[test]
fn an_unrecognized_workspace_wrapper_argument_is_left_for_transparent_execution() {
    let arguments = vec!["custom-compiler".into(), "src/lib.rs".into()];
    let (wrapper_argument, compiler_arguments) =
        workspace_wrapper_arguments(OsStr::new("custom-driver"), &arguments);

    assert_eq!(wrapper_argument, None);
    assert_eq!(compiler_arguments, arguments);
}

#[test]
fn ambiguous_build_script_sidecars_are_refused() {
    let directory = tempfile::tempdir().unwrap();
    let invoked = directory.path().join(format!(
        "build-script-build{}",
        std::env::consts::EXE_SUFFIX
    ));
    std::fs::write(&invoked, "shim").unwrap();
    for hash in ["one", "two"] {
        let name = format!(
            "build_script_build-{hash}{}{}",
            std::env::consts::EXE_SUFFIX,
            BUILD_SCRIPT_REAL_SUFFIX
        );
        std::fs::write(directory.path().join(name), "real").unwrap();
    }

    assert_eq!(find_build_script_real_path(&invoked), None);
}

#[test]
fn cargo_build_script_executable_names_are_recognized() {
    assert!(is_build_script_executable(Path::new("build-script-build")));
    assert!(is_build_script_executable(Path::new("build_script_build")));
    assert!(!is_build_script_executable(Path::new("build-script")));
    assert!(!is_build_script_executable(Path::new("build-script-")));
}

#[test]
fn only_a_binary_crate_type_is_a_possible_build_script() {
    let arguments = |values: &[&str]| values.iter().map(OsString::from).collect::<Vec<_>>();
    assert!(compiles_only_a_binary(&arguments(&["--crate-type", "bin"])));
    assert!(compiles_only_a_binary(&arguments(&["--crate-type=bin"])));
    assert!(!compiles_only_a_binary(&arguments(&[
        "--crate-type",
        "lib"
    ])));
    assert!(!compiles_only_a_binary(&arguments(&[
        "--crate-type",
        "bin,rlib"
    ])));
    assert!(!compiles_only_a_binary(&arguments(&["src/main.rs"])));
}

#[test]
fn a_build_script_with_a_custom_path_is_recognized() {
    // `build = "builder/main.rs"` runs as `build-script-main`, compiled from
    // the crate `build_script_main`.
    assert!(is_build_script_executable(Path::new("build-script-main")));
    assert_eq!(
        build_script_crate_name(Path::new("build-script-my-build")).as_deref(),
        Some("build_script_my_build")
    );

    let directory = tempfile::tempdir().unwrap();
    let invoked = directory
        .path()
        .join(format!("build-script-main{}", std::env::consts::EXE_SUFFIX));
    std::fs::write(&invoked, "shim").unwrap();
    // A sibling for some other script name must not be taken for this one.
    let other = directory.path().join(format!(
        "build_script_build-one{}{}",
        std::env::consts::EXE_SUFFIX,
        BUILD_SCRIPT_REAL_SUFFIX
    ));
    std::fs::write(&other, "other").unwrap();
    assert_eq!(find_build_script_real_path(&invoked), None);

    let real = directory.path().join(format!(
        "build_script_main-one{}{}",
        std::env::consts::EXE_SUFFIX,
        BUILD_SCRIPT_REAL_SUFFIX
    ));
    std::fs::write(&real, "real").unwrap();
    assert_eq!(find_build_script_real_path(&invoked), Some(real));
}

fn test_config(cache_dir: &Path) -> Config {
    Config {
        cache_dir: cache_dir.to_path_buf(),
        shims_dir: cache_dir.join("shims"),
        stats_report: None,
        ar_determinism: "auto".into(),
        verify: false,
        verify_sample_rate: 0,
        incremental: false,
        eager_incremental: false,
        share_out_dir: false,
        restore_hardlink: true,
        share_workspace_root: false,
        build_script_execution: false,
        events: false,
        cc: false,
        cc_store_path_specific: true,
        forward_compiler_notifications: true,
        remote: Default::default(),
        http: Default::default(),
        gc: Default::default(),
        scheduler: Default::default(),
        linker: Default::default(),
        target: crate::config::TargetSettings {
            views: false,
            lanes: true,
            seed: false,
            root: cache_dir.join("targets"),
        },
    }
}

#[tokio::test]
async fn cmake_selection_uses_the_final_build_environment() {
    let cache = tempfile::tempdir().unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let private = tempfile::tempdir().unwrap();
    let mut config = test_config(cache.path());
    config.shims_dir = private.path().join("shims");
    let mut session = CacheSession::start(session_dir.path(), &config)
        .await
        .unwrap();
    // Exercise CMake selection even on a runner with no native toolchain.
    session.cc_shims = Some(CcShims {
        cc: None,
        cxx: None,
        targeted: Vec::new(),
    });
    let workspace = tempfile::tempdir().unwrap();
    let selected = BTreeMap::from([
        ("CMAKE".to_string(), "/per-build/cmake".to_string()),
        ("HOST_CMAKE".into(), "/per-build/host-cmake".into()),
        ("TARGET_CMAKE".into(), "/per-build/target-cmake".into()),
        (
            "CMAKE_aarch64_unknown_linux_gnu".into(),
            "/per-build/arm-cmake".into(),
        ),
    ]);
    let mut environment = selected.clone();
    session
        .begin(
            workspace.path(),
            &workspace.path().join("target"),
            &["build".into()],
            &mut environment,
        )
        .await;
    let programs: BTreeMap<String, PathBuf> =
        serde_json::from_str(&environment["TUIST_CARGO_CACHE_CMAKE_PROGRAMS"]).unwrap();
    for (variable, program) in selected {
        let shim = Path::new(&environment[&variable]);
        assert!(shim.starts_with(&config.shims_dir));
        assert!(shim.is_file());
        assert_eq!(
            programs[shim.file_stem().unwrap().to_str().unwrap()],
            PathBuf::from(program)
        );
    }
    session.finish().await.unwrap();
}

#[tokio::test]
async fn session_environment_directs_cargo_at_the_shim() {
    let cache = tempfile::tempdir().unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let session = CacheSession::start(session_dir.path(), &test_config(cache.path()))
        .await
        .unwrap();

    let workspace = tempfile::tempdir().unwrap();
    let mut values = BTreeMap::from([
        ("RUSTC_WRAPPER".into(), "existing".into()),
        (
            "RUSTC_WORKSPACE_WRAPPER".into(),
            "workspace-existing".into(),
        ),
        ("RUSTDOC".into(), "custom-rustdoc".into()),
    ]);
    let run = session
        .begin(
            workspace.path(),
            &workspace.path().join("target"),
            &["build".to_string()],
            &mut values,
        )
        .await;

    assert!(run.is_some());
    assert!(values.contains_key(SOCKET_ENV));
    assert!(values.contains_key(STAGING_ENV));
    assert_eq!(values.get(BUILD_ENV).unwrap().len(), 64);
    // The shim carries an .exe suffix on Windows, so compare stems.
    let wrapper = Path::new(values.get("RUSTC_WRAPPER").unwrap());
    assert_eq!(wrapper.file_stem().unwrap(), RUSTC_SHIM_STEM);
    assert_eq!(values.get(PREVIOUS_RUSTC_WRAPPER_ENV).unwrap(), "existing");
    assert_eq!(
        values.get(PREVIOUS_RUSTC_WORKSPACE_WRAPPER_ENV).unwrap(),
        "workspace-existing"
    );
    assert_eq!(values.get(REAL_RUSTDOC_ENV).unwrap(), "custom-rustdoc");
    assert_eq!(
        Path::new(values.get("RUSTDOC").unwrap())
            .file_stem()
            .unwrap(),
        RUSTDOC_SHIM_STEM
    );
    assert_eq!(values.get("CARGO_INCREMENTAL").unwrap(), "0");
    assert_eq!(values.get(VERIFY_ENV).unwrap(), "0");
    assert_eq!(values.get(BUILD_SCRIPT_EXECUTION_ENV).unwrap(), "0");

    session.finish().await.unwrap();
}

#[tokio::test]
async fn failed_incremental_recording_replaces_an_inherited_root() {
    let cache = tempfile::tempdir().unwrap();
    // A file where the checkout-state directory belongs makes `touch` fail.
    std::fs::write(cache.path().join("incremental"), b"not a directory").unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let session = CacheSession::start(session_dir.path(), &test_config(cache.path()))
        .await
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let target = workspace.path().join("target");
    let mut values = BTreeMap::from([(
        INCREMENTAL_ROOT_ENV.into(),
        "/another/checkout/incremental".into(),
    )]);

    session
        .begin(
            workspace.path(),
            &target,
            &["build".to_string()],
            &mut values,
        )
        .await;

    assert_eq!(
        values.get(INCREMENTAL_ROOT_ENV).map(PathBuf::from),
        Some(target.join("tuist_cargo_cache-incremental"))
    );
    session.finish().await.unwrap();
}

/// Cargo caches rustc target and capability probes under the wrapper path. A
/// temporary path makes an otherwise no-op build repeat all of them, so the
/// rustc wrapper belongs to the tuist_cargo_cache binary rather than the session.
#[tokio::test]
async fn rustc_shim_path_survives_and_is_reused_across_sessions() {
    let cache = tempfile::tempdir().unwrap();
    let config = test_config(cache.path());

    let first_path = {
        let session_dir = tempfile::tempdir().unwrap();
        let session = CacheSession::start(session_dir.path(), &config)
            .await
            .unwrap();
        let path = session.rustc_shim.clone();
        session.finish().await.unwrap();
        path
    };

    assert!(
        first_path.is_file(),
        "the wrapper path cached by Cargo must survive its tuist_cargo_cache session"
    );

    let second_dir = tempfile::tempdir().unwrap();
    let second = CacheSession::start(second_dir.path(), &config)
        .await
        .unwrap();
    assert_eq!(second.rustc_shim, first_path);
    second.finish().await.unwrap();
}

#[cfg(windows)]
#[test]
fn concurrent_persistent_shim_installation_keeps_the_binary_intact() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("tuist_cargo_cache.exe");
    let destination = directory.path().join("tuist_cargo_cache-rustc.exe");
    let contents = vec![0x5a; 1024 * 1024];
    std::fs::write(&executable, &contents).unwrap();
    let barrier = std::sync::Arc::new(std::sync::Barrier::new(32));
    let mut installers = Vec::new();
    for _ in 0..32 {
        let executable = executable.clone();
        let destination = destination.clone();
        let barrier = std::sync::Arc::clone(&barrier);
        installers.push(std::thread::spawn(move || {
            barrier.wait();
            link_path_shim(&executable, &destination)
        }));
    }
    for installer in installers {
        installer.join().unwrap().unwrap();
    }

    assert_eq!(std::fs::read(&executable).unwrap(), contents);
    assert_eq!(std::fs::read(&destination).unwrap(), contents);
}

#[tokio::test]
async fn a_session_with_no_shim_connection_does_not_load_a_manifest() {
    let cache = tempfile::tempdir().unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let session = CacheSession::start(session_dir.path(), &test_config(cache.path()))
        .await
        .unwrap();
    let workspace = tempfile::tempdir().unwrap();
    let mut environment = BTreeMap::new();

    let run = session
        .begin(
            workspace.path(),
            &workspace.path().join("target"),
            &["build".to_string()],
            &mut environment,
        )
        .await
        .unwrap();

    assert!(session.task.initialized.get().is_none());
    run.commit().await.unwrap();
    assert!(session.task.initialized.get().is_none());
    assert_eq!(session.finish().await.unwrap().predictions_loaded, 0);
}

#[test]
fn nested_sessions_unwrap_the_outer_rustdoc_shim() {
    let values = BTreeMap::from([
        (
            "RUSTDOC".into(),
            Path::new("outer-session")
                .join(shim_file_name(RUSTDOC_SHIM_STEM))
                .to_string_lossy()
                .into_owned(),
        ),
        (REAL_RUSTDOC_ENV.into(), "custom-rustdoc".into()),
    ]);

    assert_eq!(configured_rustdoc(&values), "custom-rustdoc");
}

/// Build scripts may hand HOST_CC to CMake, which records its absolute path in
/// CMakeCache.txt and reuses it on later cargo invocations. That path must
/// therefore outlive the temporary tuist_cargo_cache session that first configured CMake.
#[cfg(unix)]
#[tokio::test]
async fn cc_shim_path_survives_and_is_reused_across_sessions() {
    if resolve_on_path(CcLanguage::C.default_driver()).is_none() {
        return;
    }
    let cache = tempfile::tempdir().unwrap();
    let mut config = test_config(cache.path());
    config.cc = true;

    let first_path = {
        let session_dir = tempfile::tempdir().unwrap();
        let session = CacheSession::start(session_dir.path(), &config)
            .await
            .unwrap();
        let path = session
            .cc_shims
            .as_ref()
            .and_then(|shims| shims.cc.as_ref())
            .map(|(shim, _)| shim.clone())
            .unwrap();
        session.finish().await.unwrap();
        path
    };

    assert!(
        first_path.is_file(),
        "the compiler path cached by a build system must survive its tuist_cargo_cache session"
    );

    let second_dir = tempfile::tempdir().unwrap();
    let second = CacheSession::start(second_dir.path(), &config)
        .await
        .unwrap();
    let second_path = second
        .cc_shims
        .as_ref()
        .and_then(|shims| shims.cc.as_ref())
        .map(|(shim, _)| shim.as_path())
        .unwrap();
    assert_eq!(
        second_path, first_path,
        "later sessions must reuse the compiler path a build system cached"
    );
    second.finish().await.unwrap();
}

/// The persistent shim directory is shared by every tuist_cargo_cache process using a cache.
/// Concurrent sessions must not contend on the temporary name used to install
/// the same shim.
#[cfg(unix)]
#[tokio::test(flavor = "multi_thread", worker_threads = 8)]
async fn concurrent_sessions_can_install_shared_cc_shims() {
    if resolve_on_path(CcLanguage::C.default_driver()).is_none() {
        return;
    }
    let cache = tempfile::tempdir().unwrap();
    let mut config = test_config(cache.path());
    config.cc = true;

    let barrier = Arc::new(tokio::sync::Barrier::new(8));
    let mut starts = tokio::task::JoinSet::new();
    for _ in 0..8 {
        let config = config.clone();
        let barrier = Arc::clone(&barrier);
        starts.spawn(async move {
            let session_dir = tempfile::tempdir().unwrap();
            barrier.wait().await;
            let session = CacheSession::start(session_dir.path(), &config).await?;
            let shim = session
                .cc_shims
                .as_ref()
                .and_then(|shims| shims.cc.as_ref())
                .map(|(shim, _)| shim.clone())
                .unwrap();
            session.finish().await?;
            Ok::<_, eyre::Report>(shim)
        });
    }

    let mut installed = Vec::new();
    while let Some(result) = starts.join_next().await {
        installed.push(result.unwrap().unwrap());
    }
    assert_eq!(installed.len(), 8);
    assert!(installed.iter().all(|shim| shim == &installed[0]));
    assert!(installed[0].is_file());
}

#[tokio::test]
async fn incremental_builds_leave_cargo_incremental_alone() {
    let cache = tempfile::tempdir().unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let mut config = test_config(cache.path());
    config.incremental = true;
    let session = CacheSession::start(session_dir.path(), &config)
        .await
        .unwrap();

    let workspace = tempfile::tempdir().unwrap();
    let mut values = BTreeMap::new();
    session
        .begin(
            workspace.path(),
            &workspace.path().join("target"),
            &["build".to_string()],
            &mut values,
        )
        .await;

    // Absent, not "1": cargo's own per-profile default is what we want, and
    // forcing the value on would turn incremental on for release too.
    assert!(!values.contains_key("CARGO_INCREMENTAL"));

    session.finish().await.unwrap();
}

#[tokio::test]
async fn verify_mode_is_passed_to_the_shim() {
    let cache = tempfile::tempdir().unwrap();
    let session_dir = tempfile::tempdir().unwrap();
    let mut config = test_config(cache.path());
    config.verify = true;
    let session = CacheSession::start(session_dir.path(), &config)
        .await
        .unwrap();

    let workspace = tempfile::tempdir().unwrap();
    let mut values = BTreeMap::new();
    session
        .begin(
            workspace.path(),
            &workspace.path().join("target"),
            &["build".to_string()],
            &mut values,
        )
        .await;

    assert_eq!(values.get(VERIFY_ENV).unwrap(), "1");

    session.finish().await.unwrap();
}

#[test]
fn identity_follows_the_dependency_graph_not_the_path() {
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    std::fs::write(first.path().join("Cargo.lock"), "version = 4\n").unwrap();
    std::fs::write(second.path().join("Cargo.lock"), "version = 4\n").unwrap();
    let command = ["build".to_string()];

    assert_eq!(
        build_identity(first.path(), &command),
        build_identity(second.path(), &command),
        "separate worktrees of one project must share a manifest"
    );

    std::fs::write(second.path().join("Cargo.lock"), "version = 3\n").unwrap();
    assert_ne!(
        build_identity(first.path(), &command),
        build_identity(second.path(), &command),
    );
    assert_eq!(
        build_identity(first.path(), &command),
        build_identity(first.path(), &["test".to_string()]),
        "Cargo commands in one dependency graph should share predictions",
    );
}

#[test]
fn identity_falls_back_to_the_directory_name() {
    let directory = tempfile::tempdir().unwrap();
    let command = ["build".to_string()];
    assert_eq!(
        build_identity(directory.path(), &command).len(),
        64,
        "a project without a lockfile still gets an identity"
    );
}

#[test]
fn path_shim_names_select_their_language() {
    assert_eq!(path_shim_language("cc"), Some(CcLanguage::C));
    assert_eq!(path_shim_language("gcc"), Some(CcLanguage::C));
    assert_eq!(path_shim_language("clang"), Some(CcLanguage::C));
    assert_eq!(path_shim_language("c++"), Some(CcLanguage::Cxx));
    assert_eq!(path_shim_language("g++"), Some(CcLanguage::Cxx));
    assert_eq!(path_shim_language("clang++"), Some(CcLanguage::Cxx));
    // A versioned driver was chosen deliberately and is never intercepted.
    assert_eq!(path_shim_language("gcc-13"), None);
    assert_eq!(path_shim_language("tuist_cargo_cache"), None);
}

#[test]
fn exec_identity_is_shared_across_checkouts_with_one_lockfile() {
    let first = tempfile::tempdir().unwrap();
    let second = tempfile::tempdir().unwrap();
    std::fs::write(first.path().join("Cargo.lock"), "version = 4\n").unwrap();
    std::fs::write(second.path().join("Cargo.lock"), "version = 4\n").unwrap();
    let command = ["make".to_string()];

    assert_eq!(
        exec_identity(first.path(), &command),
        exec_identity(second.path(), &command),
        "worktrees of one project must share a manifest for predictions to travel"
    );
    assert_ne!(
        exec_identity(first.path(), &command),
        exec_identity(first.path(), &["make".to_string(), "-j8".to_string()]),
    );
}

#[test]
fn exec_identity_falls_back_to_the_directory_name() {
    let directory = tempfile::tempdir().unwrap();
    let command = ["make".to_string()];
    assert_eq!(
        exec_identity(directory.path(), &command).len(),
        64,
        "a project with no lockfile and no git origin still gets an identity"
    );
}

#[test]
/// Jujutsu's remote listing names each remote before its URL.
fn reads_the_origin_from_jujutsu_remote_output() {
    let remotes = "backup ssh://example.com/backup\norigin https://example.com/project.git\n";

    assert_eq!(
        jj_origin_url(remotes),
        Some("https://example.com/project.git")
    );
    assert_eq!(
        jj_origin_url("upstream https://example.com/project.git\n"),
        None
    );
}

#[test]
fn reads_mercurial_and_sapling_default_paths_as_origins() {
    assert_eq!(
        origin_marker_from_output(b"https://example.com/project\n"),
        Some("origin\0https://example.com/project".to_string())
    );
    assert_eq!(origin_marker_from_output(b"\n"), None);
}

#[test]
/// A nested Git checkout must not inherit an enclosing Jujutsu remote.
fn a_nested_git_checkout_does_not_query_jujutsu() {
    let directory = tempfile::tempdir().unwrap();
    let outer = directory.path();
    let inner = outer.join("vendor");
    std::fs::create_dir(&inner).unwrap();
    std::fs::create_dir(outer.join(".jj")).unwrap();
    std::fs::create_dir(inner.join(".git")).unwrap();

    assert_eq!(jj_origin_marker(&inner), None);
}

#[test]
fn native_checkouts_do_not_inherit_an_enclosing_git_origin() {
    for marker in [".hg", ".sl"] {
        let directory = tempfile::tempdir().unwrap();
        let outer = directory.path();
        let inner = outer.join("vendor");
        std::fs::create_dir(&inner).unwrap();
        std::fs::create_dir(inner.join(marker)).unwrap();
        assert!(
            Command::new("git")
                .arg("init")
                .arg("--quiet")
                .arg(outer)
                .status()
                .unwrap()
                .success()
        );
        assert!(
            Command::new("git")
                .arg("-C")
                .arg(outer)
                .args(["remote", "add", "origin", "https://example.com/outer.git"])
                .status()
                .unwrap()
                .success()
        );

        assert_eq!(project_origin_marker(&inner), None, "marker: {marker}");
    }
}

#[cfg(unix)]
#[test]
fn a_shim_directory_never_supplies_the_real_compiler() {
    // The shim there stands for a *different* tuist_cargo_cache than the one resolving --
    // an upgrade, or another checkout's build -- so no identity check against
    // the running binary can rule it out. Taking it would pin a shim as its
    // own compiler and recurse forever, so the directory is excluded by
    // location.
    let directory = tempfile::tempdir().unwrap();
    let shims = directory.path().join("shims");
    let real_dir = directory.path().join("bin");
    std::fs::create_dir(&shims).unwrap();
    std::fs::create_dir(&real_dir).unwrap();
    let other_cargo_cache = directory.path().join("other-tuist_cargo_cache");
    std::fs::write(&other_cargo_cache, b"#!/bin/sh\n").unwrap();
    std::os::unix::fs::symlink(&other_cargo_cache, shims.join("cc")).unwrap();
    let real_cc = real_dir.join("cc");
    std::fs::write(&real_cc, b"#!/bin/sh\n").unwrap();

    let running = directory.path().join("tuist_cargo_cache");
    std::fs::write(&running, b"#!/bin/sh\n").unwrap();
    // Handed in rather than set: `PATH` is process global and these tests run
    // on a thread pool, so writing it would race whatever else reads one.
    let path = std::env::join_paths([shims.as_path(), real_dir.as_path()]).unwrap();
    let resolved = resolve_in_path(&path, "cc", &running, &shims);

    assert_eq!(
        resolved.map(|path| std::fs::canonicalize(path).unwrap()),
        Some(std::fs::canonicalize(&real_cc).unwrap()),
        "a shim must never be chosen as the compiler it stands in for"
    );
}

#[cfg(unix)]
#[test]
fn another_installations_shim_directory_never_supplies_the_real_compiler() {
    // The directory excluded by location is only ever this install's own. A
    // second tuist_cargo_cache on the machine -- a different container image, a checkout
    // built from source, an upgrade mid-rollout -- owns a shim directory that
    // matches neither that location nor this binary's device and inode. Taking
    // its `cc` makes the two installs hand the compilation back and forth
    // until the machine runs out of processes, so a marked directory is
    // skipped whoever wrote it.
    let directory = tempfile::tempdir().unwrap();
    let mine = directory.path().join("mine");
    let theirs = directory.path().join("theirs");
    let real_dir = directory.path().join("bin");
    for path in [&mine, &theirs, &real_dir] {
        std::fs::create_dir(path).unwrap();
    }
    let other_cargo_cache = directory.path().join("other-tuist_cargo_cache");
    std::fs::write(&other_cargo_cache, b"#!/bin/sh\n").unwrap();
    std::os::unix::fs::symlink(&other_cargo_cache, theirs.join("cc")).unwrap();
    mark_shim_directory(&theirs);
    let real_cc = real_dir.join("cc");
    std::fs::write(&real_cc, b"#!/bin/sh\n").unwrap();

    let running = directory.path().join("tuist_cargo_cache");
    std::fs::write(&running, b"#!/bin/sh\n").unwrap();
    let path =
        std::env::join_paths([mine.as_path(), theirs.as_path(), real_dir.as_path()]).unwrap();

    assert_eq!(
        resolve_in_path(&path, "cc", &running, &mine)
            .map(|path| std::fs::canonicalize(path).unwrap()),
        Some(std::fs::canonicalize(&real_cc).unwrap()),
        "another install's shim must never be chosen as the compiler"
    );
}

#[cfg(unix)]
#[test]
fn a_compiler_named_inside_another_installations_shims_is_left_alone() {
    // Same directory, reached the other way: a build that names its compiler
    // outright, having inherited `CC` from an outer session belonging to a
    // different install.
    let directory = tempfile::tempdir().unwrap();
    let mine = directory.path().join("mine");
    let theirs = directory.path().join("theirs");
    std::fs::create_dir(&mine).unwrap();
    std::fs::create_dir(&theirs).unwrap();
    let planted = theirs.join("aarch64-linux-musl-gcc");
    std::fs::write(&planted, b"#!/bin/sh\n").unwrap();
    mark_shim_directory(&theirs);
    let executable = directory.path().join("tuist_cargo_cache");
    std::fs::write(&executable, b"#!/bin/sh\n").unwrap();

    assert_eq!(
        resolve_named_compiler(&planted.display().to_string(), &executable, &mine),
        None,
        "a compiler inside another install's shim directory must not be wrapped"
    );
}

#[test]
fn a_pin_naming_a_shim_falls_back_to_the_search() {
    let directory = tempfile::tempdir().unwrap();
    let shims = directory.path().join("shims");
    let real_dir = directory.path().join("bin");
    std::fs::create_dir(&shims).unwrap();
    std::fs::create_dir(&real_dir).unwrap();
    mark_shim_directory(&shims);
    let running = directory.path().join("tuist_cargo_cache");
    std::fs::write(&running, b"#!/bin/sh\n").unwrap();

    // A pin left by an older tuist_cargo_cache, naming a shim rather than a compiler.
    assert!(!pin_names_a_compiler(&shims.join("cc"), Some(&running)));
    // The pin naming this very binary, which no marker is needed to catch.
    assert!(!pin_names_a_compiler(&running, Some(&running)));
    // An ordinary pin is still used.
    assert!(pin_names_a_compiler(&real_dir.join("cc"), Some(&running)));
}

#[cfg(unix)]
#[test]
fn host_driver_lookup_skips_another_installations_shims() {
    // `TUIST_CARGO_CACHE_REAL_CC` and `TUIST_CARGO_CACHE_REAL_CXX` are what the installed shim actually
    // runs. A foreign shim recorded there is a shim standing in for a shim,
    // which is the loop this marker exists to stop, so the plain first-match
    // lookup has to skip marked directories too.
    let directory = tempfile::tempdir().unwrap();
    let theirs = directory.path().join("theirs");
    let real_dir = directory.path().join("bin");
    std::fs::create_dir(&theirs).unwrap();
    std::fs::create_dir(&real_dir).unwrap();
    let other_cargo_cache = directory.path().join("other-tuist_cargo_cache");
    std::fs::write(&other_cargo_cache, b"#!/bin/sh\n").unwrap();
    std::os::unix::fs::symlink(&other_cargo_cache, theirs.join("cc")).unwrap();
    mark_shim_directory(&theirs);
    let real_cc = real_dir.join("cc");
    std::fs::write(&real_cc, b"#!/bin/sh\n").unwrap();

    let path = std::env::join_paths([theirs.as_path(), real_dir.as_path()]).unwrap();
    assert_eq!(
        first_in_path(&path, "cc").map(|path| std::fs::canonicalize(path).unwrap()),
        Some(std::fs::canonicalize(&real_cc).unwrap()),
        "a host driver must never resolve to another install's shim"
    );
}

#[test]
fn an_installation_keeps_its_identity_across_an_upgrade_in_place() {
    let directory = tempfile::tempdir().unwrap();
    let binary = directory.path().join("tuist_cargo_cache");
    std::fs::write(&binary, b"release one").unwrap();
    let before = (
        binary_identity(&binary).unwrap(),
        installation_identity(&binary).unwrap(),
    );
    std::fs::write(&binary, b"release two, a little longer").unwrap();
    let after = (
        binary_identity(&binary).unwrap(),
        installation_identity(&binary).unwrap(),
    );
    assert_ne!(before.0, after.0, "rustc shims follow the binary");
    assert_eq!(before.1, after.1, "native shims follow the installation");
    assert_ne!(
        installation_identity(&directory.path().join("other/tuist_cargo_cache")).unwrap(),
        after.1,
        "another installation gets its own native shims"
    );
}

#[cfg(unix)]
#[test]
fn only_shim_directories_nothing_can_use_are_collected() {
    let directory = tempfile::tempdir().unwrap();
    let shims = directory.path().join("shims");
    let binary = directory.path().join("tuist_cargo_cache");
    std::fs::write(&binary, b"#!/bin/sh\n").unwrap();
    let gone = directory.path().join("removed install/tuist_cargo_cache");
    let install = |kind: &str, identity: &str, target: Option<&Path>| {
        let per_binary = shims.join(kind).join(identity);
        std::fs::create_dir_all(&per_binary).unwrap();
        mark_shim_directory(&per_binary);
        if let Some(target) = target {
            let name = if kind == "rust" {
                "tuist_cargo_cache-rustc"
            } else {
                "tuist_cargo_cache-c"
            };
            std::os::unix::fs::symlink(target, per_binary.join(name)).unwrap();
        }
        per_binary
    };
    let stranded = install("native", "stranded", Some(&gone));
    let stranded_rust = install("rust", "stranded", Some(&gone));
    let live = install("native", "live", Some(&binary));
    // A concurrent session has created its directory but not linked yet.
    let installing = install("native", "installing", None);
    // The running binary's own directory is never judged, whatever it holds.
    let own = install("native", "own", Some(&gone));

    // Another container's binary lives on a path this process cannot see,
    // so its links dangle here, but it built recently.
    let elsewhere = install("native", "elsewhere", Some(&gone));
    // The binary at a path was replaced in place. Its old rustc shims still
    // resolve, and a session started before the upgrade still uses them.
    let superseded = install("rust", "superseded", Some(&binary));
    let _running = ShimLease::take(&superseded).unwrap();
    let long_ago = std::time::SystemTime::now() - std::time::Duration::from_secs(3600);
    for unused in [
        &stranded,
        &stranded_rust,
        &live,
        &installing,
        &own,
        &superseded,
    ] {
        std::fs::File::options()
            .write(true)
            .open(unused.join(".tuist_cargo_cache-shims"))
            .unwrap()
            .set_modified(long_ago)
            .unwrap();
    }

    remove_stranded_binary_shims(&shims, "own", "own", std::time::Duration::from_secs(60));

    assert!(!stranded.exists(), "a removed binary's shims should go");
    assert!(!stranded_rust.exists(), "rustc shims are collected too");
    assert!(live.exists(), "an installed binary's shims must stay");
    assert!(
        installing.exists(),
        "a directory still being filled must stay"
    );
    assert!(own.exists(), "the running binary's directory must stay");
    assert!(
        superseded.exists(),
        "a superseded wrapper a running session holds must stay"
    );
    assert!(
        elsewhere.exists(),
        "a directory used recently must stay even when its links dangle here"
    );
}

#[cfg(unix)]
#[test]
fn superseded_rustc_shims_go_once_no_session_holds_them() {
    let directory = tempfile::tempdir().unwrap();
    let shims = directory.path().join("shims");
    let binary = directory.path().join("tuist_cargo_cache");
    std::fs::write(&binary, b"#!/bin/sh\n").unwrap();
    let current = binary_identity(&binary).unwrap();
    let install = |identity: &str, target: &Path| {
        let per_binary = shims.join("rust").join(identity);
        std::fs::create_dir_all(&per_binary).unwrap();
        mark_shim_directory(&per_binary);
        std::os::unix::fs::symlink(target, per_binary.join("tuist_cargo_cache-rustc")).unwrap();
        per_binary
    };
    // Every release that was upgraded in place at this path left one of
    // these behind, and all of their links resolve to today's binary.
    let abandoned = install("before-upgrade", &binary);
    drop(ShimLease::take(&abandoned).unwrap());
    // Installed by a binary from before leases: a session it started may
    // still be running and has no way to say so.
    let legacy = install("before-leases", &binary);
    // A session started before the upgrade is still running.
    let held = install("still-running", &binary);
    let lease = ShimLease::take(&held).unwrap();
    // A session that died without cleaning up leaves a lease nobody holds.
    let crashed = install("crashed", &binary);
    std::fs::create_dir_all(crashed.join(".tuist_cargo_cache-leases")).unwrap();
    std::fs::write(crashed.join(".tuist_cargo_cache-leases/1-0-0.lease"), b"").unwrap();
    // Upgraded recently: a session may start with it before noticing.
    let recent = install("recent", &binary);
    // The binary the path holds now, used by another installation's
    // sessions, is not superseded however long it sits.
    let installed = install(&current, &binary);
    // Another container's binary, leased there, with links dangling here.
    let elsewhere = install(
        "elsewhere",
        &directory.path().join("gone/tuist_cargo_cache"),
    );
    let _elsewhere = ShimLease::take(&elsewhere).unwrap();
    let long_ago = std::time::SystemTime::now() - std::time::Duration::from_secs(3600);
    for unused in [&abandoned, &legacy, &held, &crashed, &installed, &elsewhere] {
        std::fs::File::options()
            .write(true)
            .open(unused.join(".tuist_cargo_cache-shims"))
            .unwrap()
            .set_modified(long_ago)
            .unwrap();
    }

    remove_stranded_binary_shims(&shims, "own", "own", std::time::Duration::from_secs(60));

    assert!(
        !abandoned.exists(),
        "a superseded wrapper nobody holds goes"
    );
    assert!(!crashed.exists(), "a dead session's lease holds nothing");
    assert!(held.exists(), "a running session's wrapper must stay");
    assert!(
        legacy.exists(),
        "a wrapper no session ever leased must stay"
    );
    assert!(recent.exists(), "a recently used wrapper must stay");
    assert!(
        installed.exists(),
        "the binary at the path is not superseded"
    );
    assert!(elsewhere.exists(), "a held lease keeps dangling links too");

    // Once the session ends, its lease file goes with it and so does the
    // directory on the next collection.
    drop(lease);
    assert!(
        std::fs::read_dir(held.join(".tuist_cargo_cache-leases"))
            .unwrap()
            .next()
            .is_none(),
        "a finished session removes its own lease"
    );
    remove_stranded_binary_shims(&shims, "own", "own", std::time::Duration::from_secs(60));
    assert!(!held.exists(), "a finished session's wrapper goes");
}

#[test]
fn marking_a_directory_agrees_with_reading_it_back() {
    let directory = tempfile::tempdir().unwrap();
    let plain = directory.path().join("plain");
    std::fs::create_dir(&plain).unwrap();
    assert!(!is_shim_directory(&plain));
    mark_shim_directory(&plain);
    assert!(is_shim_directory(&plain), "a marked directory reads back");
    // Idempotent: a second call leaves the existing marker alone.
    mark_shim_directory(&plain);
    assert!(is_shim_directory(&plain));

    // A `.tuist_cargo_cache-shims` that is not a file is not a marker, and marking must not
    // treat it as one and skip the write. It still cannot be written here, so
    // what this pins is that the two helpers agree rather than drift.
    let occupied = directory.path().join("occupied");
    std::fs::create_dir(&occupied).unwrap();
    std::fs::create_dir(occupied.join(".tuist_cargo_cache-shims")).unwrap();
    mark_shim_directory(&occupied);
    assert!(
        !is_shim_directory(&occupied),
        "a directory named .tuist_cargo_cache-shims must never count as a marker"
    );
}

#[cfg(unix)]
#[test]
fn a_hard_linked_shim_is_recognized_as_the_same_binary() {
    // Both files are created here rather than linked from the running test
    // binary: a hard link needs one filesystem, and a temporary directory is
    // on a different one from the build directory often enough that CI proves
    // it. `install_shim_named` falls back to a copy in that case, which would
    // test the fallback rather than the recognition below.
    let directory = tempfile::tempdir().unwrap();
    let binary = directory.path().join("tuist_cargo_cache");
    std::fs::write(&binary, b"#!/bin/sh\n").unwrap();
    let shim_dir = directory.path().join("cc-path");
    std::fs::create_dir(&shim_dir).unwrap();

    // The case a path comparison cannot see: a shim directory an outer
    // session left on PATH, holding a link to the same binary under a
    // compiler's name.
    let linked = shim_dir.join("cc");
    std::fs::hard_link(&binary, &linked).unwrap();
    assert!(is_same_binary(&linked, Some(&binary)));

    // A copy is a different file, and saying so is correct: the shim resolves
    // its own name away by path first, so recognition here only has to cover
    // the links that share an inode.
    let copied = shim_dir.join("c++");
    std::fs::copy(&binary, &copied).unwrap();
    assert!(!is_same_binary(&copied, Some(&binary)));
}

#[test]
fn handshake_rejects_version_skew() {
    let response = serde_json::to_string(&AgentResponse::Hello {
        protocol: AGENT_PROTOCOL_VERSION,
        agent_version: "another-version".into(),
    })
    .unwrap();
    assert!(validate_handshake_response(&response).is_err());
}

/// Build the statistics a test needs without naming every counter.
///
/// `AgentStats` is `#[non_exhaustive]` so that the agent can keep adding
/// counters, which also means no struct literal can be written from here.
fn agent_stats(fill: impl FnOnce(&mut AgentStats)) -> AgentStats {
    let mut stats = AgentStats::default();
    fill(&mut stats);
    stats
}

#[test]
fn qualification_results_are_not_reported_as_misses() {
    let stats = agent_stats(|stats| {
        stats.lookups = 5;
        stats.hits = 2;
        stats.verifications = 2;
        stats.compiler = BTreeMap::from([(
            "miss".into(),
            tuist_cargo_cache_core::CompilerStats::new(1, 4_000),
        )]);
    });
    assert_eq!(cache_misses(&stats), 1);
}

#[test]
fn a_compilation_that_probed_two_action_keys_is_one_miss() {
    // A crate that reads a portable environment value is looked up under both
    // its portable and its literal key, so its lookups outnumber its
    // compilations. Subtracting hits from lookups reported this crate twice.
    let stats = agent_stats(|stats| {
        stats.lookups = 2;
        stats.hits = 0;
        stats.compiler = BTreeMap::from([(
            "miss".into(),
            tuist_cargo_cache_core::CompilerStats::new(1, 4_000),
        )]);
    });
    assert_eq!(cache_misses(&stats), 1);
}

/// The two shapes an incremental compilation comes in, told apart.
///
/// One re-entered hot workspace state and asked the cache nothing; the other
/// had its state from a prediction, asked, and got nothing. Reporting both as
/// the same outcome meant the summary either invented a lookup or lost one.
#[test]
fn an_incremental_compilation_is_counted_by_what_its_lookup_did() {
    let stats = agent_stats(|stats| {
        stats.lookups = 1;
        stats.unconsulted = 1;
        stats.incremental_compilations = 2;
        stats.compiler = BTreeMap::from([
            (
                "miss".into(),
                tuist_cargo_cache_core::CompilerStats::new(1, 4_000),
            ),
            (
                "unconsulted".into(),
                tuist_cargo_cache_core::CompilerStats::new(1, 4_000),
            ),
        ]);
    });

    assert_eq!(cache_misses(&stats), 1);
    let summary = short_summary(&stats);
    assert!(
        summary.contains("0 hits, 1 misses, 1 not looked up, 2 incremental"),
        "{summary}"
    );
}

#[test]
fn a_build_that_was_only_incremental_still_reports() {
    // Nothing was looked up, stored or bypassed, so every other gate is closed
    // and the build would otherwise finish without a word about the work it did.
    let stats = agent_stats(|stats| {
        stats.incremental_compilations = 3;
        stats.compiler = BTreeMap::from([(
            "unconsulted".into(),
            tuist_cargo_cache_core::CompilerStats::new(3, 4_000),
        )]);
    });
    assert!(should_display_short_stats(&stats));
    assert!(short_summary(&stats).contains("3 incremental"));
}

#[test]
fn bypassed_and_unconsulted_compilations_are_not_misses() {
    // Neither asked the cache anything, so neither can have missed it.
    let stats = agent_stats(|stats| {
        stats.unconsulted = 4;
        stats.compiler = BTreeMap::from([
            (
                "bypass".into(),
                tuist_cargo_cache_core::CompilerStats::new(7, 4_000),
            ),
            (
                "unconsulted".into(),
                tuist_cargo_cache_core::CompilerStats::new(4, 4_000),
            ),
        ]);
    });
    assert_eq!(cache_misses(&stats), 0);
}

#[test]
fn a_hit_on_the_literal_key_is_not_also_a_miss() {
    // The portable key is probed first. Missing it and then hitting the
    // literal one is one hit, and no miss at all: nothing was compiled.
    let stats = agent_stats(|stats| {
        stats.lookups = 2;
        stats.hits = 1;
    });
    assert_eq!(cache_misses(&stats), 0);
}

#[test]
fn a_loaded_manifest_that_matched_nothing_is_called_out() {
    // The shape a toolchain update leaves behind: a warm store, a manifest
    // full of predictions, and not one lookup all build.
    let unmatched = agent_stats(|stats| {
        stats.unconsulted = 255;
        stats.predictions_loaded = 257;
    });
    assert!(stale_manifest_note(&unmatched).unwrap().contains("257"));

    // A genuinely cold store has nothing to explain.
    let cold = agent_stats(|stats| stats.unconsulted = 255);
    assert_eq!(stale_manifest_note(&cold), None);

    // A session whose lookups happened was matching its manifest fine; the
    // stragglers are ordinary cold units, not a stale baseline.
    let live = agent_stats(|stats| {
        stats.unconsulted = 2;
        stats.lookups = 253;
        stats.predictions_loaded = 257;
    });
    assert_eq!(stale_manifest_note(&live), None);

    // The first `cargo test --no-run` after `cargo build`: the shared manifest
    // predicts the whole build, and the two test harnesses it has never seen
    // are all that compiles. Nothing about the toolchain changed.
    let new_shape = agent_stats(|stats| {
        stats.unconsulted = 2;
        stats.predictions_loaded = 816;
    });
    assert_eq!(stale_manifest_note(&new_shape), None);
}

#[test]
fn compiler_only_sessions_are_reportable() {
    let stats = agent_stats(|stats| {
        stats.compiler = BTreeMap::from([(
            "bypass".into(),
            tuist_cargo_cache_core::CompilerStats::new(1, 42),
        )]);
    });

    assert!(should_display_stats(&stats));
}

#[test]
fn a_session_that_only_failed_its_remote_is_reportable() {
    // Nothing was looked up, stored or compiled, so every other signal this
    // gate reads is zero -- and a remote cache that answered nothing but
    // failures is the one thing the build most needs to be told about.
    let stats = agent_stats(|stats| stats.remote_failures = 3);

    assert!(should_display_stats(&stats));
}

#[test]
fn short_summary_omits_routine_compiler_probe_bypasses() {
    let routine = agent_stats(|stats| {
        stats.bypasses = BTreeMap::from([
            ("compiler-query".into(), 2),
            ("standard-input".into(), 1),
            ("cc-compiler-query".into(), 3),
            ("cc-standard-input".into(), 4),
        ]);
    });
    assert!(!should_display_short_stats(&routine));

    let mixed = agent_stats(|stats| {
        stats.lookups = 4;
        stats.hits = 3;
        stats.compiler = BTreeMap::from([(
            "miss".into(),
            tuist_cargo_cache_core::CompilerStats::new(1, 4_000),
        )]);
        stats.bypasses = BTreeMap::from([
            ("compiler-query".into(), 2),
            ("standard-input".into(), 1),
            ("cc-compiler-query".into(), 3),
            ("cc-standard-input".into(), 4),
            ("native-library".into(), 5),
        ]);
    });
    let summary = short_summary(&mixed);
    assert!(
        summary.contains("3 hits, 1 misses, 5 bypassed"),
        "{summary}"
    );
    assert!(!summary.contains("compiler-query"), "{summary}");
    assert!(!summary.contains("standard-input"), "{summary}");
}

#[test]
fn ci_summary_explains_a_cold_object_cache_and_real_bypasses() {
    let stats = agent_stats(|stats| {
        stats.unconsulted = 669;
        stats.session_duration_ns = 202_000_000_000;
        stats.bypasses = BTreeMap::from([
            ("compiler-query".into(), 7),
            ("standard-input".into(), 3),
            ("native-library".into(), 4),
            ("linking-disabled".into(), 160),
        ]);
    });
    let summary = ci_summary(&stats);
    assert!(
        summary.contains("object cache: 0 hits, 0 misses, 669 not looked up, 164 bypassed"),
        "{summary}"
    );
    assert!(
        summary.contains("no usable prior inputs or matching prediction"),
        "{summary}"
    );
    assert!(
        summary.contains("160 linking-disabled, 4 native-library"),
        "{summary}"
    );
    assert!(!summary.contains("compiler-query"), "{summary}");
    assert!(!summary.contains("standard-input"), "{summary}");
    assert!(
        summary.contains("Cargo artifact reuse and CI cache archive transfers are not included"),
        "{summary}"
    );
}

#[test]
fn ci_summary_preserves_verification_and_failure_diagnostics() {
    let stats = agent_stats(|stats| {
        stats.lookups = 10;
        stats.hits = 6;
        stats.compiler = BTreeMap::from([(
            "miss".into(),
            tuist_cargo_cache_core::CompilerStats::new(2, 4_000),
        )]);
        stats.verifications = 2;
        stats.divergences = 1;
        stats.remote_failures = 3;
        stats.background_upload_failures = 4;
        stats.avoided_compiler_duration_ns = 10_000_000_000;
    });
    let summary = ci_summary(&stats);
    assert!(summary.contains("6 hits, 2 misses"), "{summary}");
    assert!(summary.contains("2 verified, 1 diverged"), "{summary}");
    assert!(summary.contains("3 remote failures"), "{summary}");
    assert!(summary.contains("4 background uploads failed"), "{summary}");
    assert!(
        summary.contains("estimated compiler time avoided (summed across compilations)"),
        "{summary}"
    );
    let upload_only = agent_stats(|stats| stats.background_upload_failures = 1);
    assert!(should_display_short_stats(&upload_only));
}

#[test]
fn ci_summary_explains_an_unmatched_manifest() {
    let stats = agent_stats(|stats| {
        stats.unconsulted = 20;
        stats.predictions_loaded = 20;
    });
    assert!(ci_summary(&stats).contains("none matched this build"));
}

#[test]
fn an_off_summary_still_writes_the_versioned_stats_report() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("nested").join("stats.json");
    let stats = agent_stats(|stats| {
        stats.session_duration_ns = 42;
        stats.lookups = 6;
        stats.hits = 2;
        stats.verifications = 1;
        stats.prefetched_actions = 3;
        stats.downloaded_bytes = 1024;
        stats.restored_output_files = 7;
        stats.restored_output_bytes = 2048;
        stats.reflinked_output_files = 5;
        stats.reflinked_output_bytes = 1536;
        stats.copied_output_files = 2;
        stats.copied_output_bytes = 512;
        stats.avoided_compiler_duration_ns = 2_000;
        stats.compiler = BTreeMap::from([(
            "miss".into(),
            tuist_cargo_cache_core::CompilerStats::new(3, 4_000),
        )]);
        stats.slow_compilations = BTreeMap::from([("slow_crate".into(), 3_000)]);
        stats.remote_blob_requests = 4;
        stats.remote_blob_pack_requests = 2;
        stats.remote_blob_pack_blobs = 100;
        stats.materialization_duration_ns = 9;
        stats.predictions_loaded = 11;
    });

    let mut config = Config::for_test(directory.path());
    config.stats_report = Some(path.clone());
    display_stats(&stats, &config, SummaryStyle::Off);
    let report: serde_json::Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();

    // Bumped whenever the report grows a field, so a reader can tell from the
    // version alone which ones it may expect.
    // Bumped to 5 when `compiler` stopped carrying an "incremental" entry and
    // the count moved to a field of its own.
    assert_eq!(report["version"], 5);
    assert_eq!(report["predictions_loaded"], 11);
    assert_eq!(report["session_duration_ns"], 42);
    assert_eq!(report["hits"], 2);
    assert_eq!(report["misses"], 3);
    assert_eq!(report["compiler_invocations_avoided"], 2);
    assert_eq!(report["estimated_compiler_duration_avoided_ns"], 2_000);
    assert_eq!(report["compiler"]["miss"]["invocations"], 3);
    assert_eq!(report["compiler"]["miss"]["duration_ns"], 4_000);
    assert_eq!(report["slow_compilations"][0]["crate_name"], "slow_crate");
    assert_eq!(report["slow_compilations"][0]["duration_ns"], 3_000);
    assert_eq!(report["prefetched_actions"], 3);
    assert_eq!(report["downloaded_bytes"], 1024);
    assert_eq!(report["restored_output_files"], 7);
    assert_eq!(report["restored_output_bytes"], 2048);
    assert_eq!(report["reflinked_output_files"], 5);
    assert_eq!(report["reflinked_output_bytes"], 1536);
    assert_eq!(report["copied_output_files"], 2);
    assert_eq!(report["copied_output_bytes"], 512);
    assert_eq!(report["remote_blob_requests"], 4);
    assert_eq!(report["remote_blob_pack_requests"], 2);
    assert_eq!(report["remote_blob_pack_blobs"], 100);
    assert_eq!(report["materialization_duration_ns"], 9);
}

#[test]
fn finds_crate_names_in_transparent_invocations() {
    assert_eq!(
        crate_name_argument(&["--crate-name".into(), "fixture".into()]),
        Some("fixture".into())
    );
    assert_eq!(
        crate_name_argument(&["--crate-name=attached".into()]),
        Some("attached".into())
    );
    assert_eq!(crate_name_argument(&["--version".into()]), None);
}

/// Cargo can move a compilation's arguments into an `@argfile`. The crate
/// name, and so the unit's label and whether it is a probe, are inside it.
#[test]
fn finds_crate_names_inside_argfiles() {
    let directory = tempfile::tempdir().unwrap();
    let argfile = directory.path().join("args");
    std::fs::write(
        &argfile,
        "--crate-name\nfixture\n--crate-type\nlib\nsrc/lib.rs\n",
    )
    .unwrap();
    let mut given = std::ffi::OsString::from("@");
    given.push(&argfile);
    let arguments = vec![given];

    assert_eq!(crate_name_argument(&arguments), None);
    let described = tuist_cargo_cache_rustc::RustcInvocation::expand_arguments(&arguments).unwrap();
    assert_eq!(crate_name_argument(&described), Some("fixture".into()));
}

#[test]
fn recognizes_the_bypassed_invocations_that_run_a_linker() {
    // Native links bypass the cache today, so this is the only thing that
    // tells the scheduler one of them is about to run.
    for arguments in [
        vec!["--crate-type", "bin"],
        vec!["--crate-type=cdylib"],
        vec!["--crate-type", "lib,dylib"],
        vec!["--crate-type=proc-macro"],
        vec!["--crate-type=staticlib"],
        // A test harness links a program whatever its crate type says.
        vec!["--test", "--crate-type=lib"],
        // The emit that actually links, spelled both ways cargo spells it.
        vec!["--crate-type=bin", "--emit=dep-info,link"],
        vec!["--test", "--emit", "link=/tmp/out"],
    ] {
        let arguments: Vec<OsString> = arguments.iter().map(OsString::from).collect();
        assert!(links_natively(&arguments), "{arguments:?} links");
    }

    for arguments in [
        vec!["--crate-type", "lib"],
        vec!["--crate-type=rlib"],
        vec!["--crate-type", "lib,rlib"],
        vec!["--emit=metadata"],
        // The flag's own name is not its value: a crate called "bin" is not
        // a program.
        vec!["--crate-name", "bin"],
        // What `cargo check` and `clippy --all-targets` run: the same binary
        // and test targets, compiled to metadata, with no linker anywhere.
        vec!["--crate-type=bin", "--emit=metadata"],
        vec!["--test", "--emit", "dep-info,metadata"],
        vec!["--crate-type=cdylib", "--emit=dep-info,metadata"],
    ] {
        let arguments: Vec<OsString> = arguments.iter().map(OsString::from).collect();
        assert!(!links_natively(&arguments), "{arguments:?} does not link");
    }
}

#[test]
fn managed_linkers_are_added_only_to_native_links() {
    let mut link = vec!["--crate-type=bin".into(), "--emit=link".into()];
    use_managed_linker(&mut link, OsStr::new("/tools/mold"));
    assert!(link.contains(&OsString::from("-Clinker=clang")));
    assert!(link.contains(&OsString::from("-Clink-arg=-fuse-ld=/tools/mold")));

    let mut check = vec!["--crate-type=bin".into(), "--emit=metadata".into()];
    use_managed_linker(&mut check, OsStr::new("/tools/mold"));
    assert_eq!(check.len(), 2);
}

/// The session shim must be a symlink, not a hard link.
///
/// Cargo execs it within milliseconds of its creation, and a hard link that new
/// is not reliably runnable on macOS -- see [`install_shim`]. Asserted on the
/// kind of link rather than by racing the kernel, which no test can do
/// dependably.
#[cfg(unix)]
#[test]
fn the_session_shim_tracks_the_binary_it_was_installed_from() {
    let directory = tempfile::tempdir().unwrap();
    let executable = std::env::current_exe().unwrap();
    let shim = install_shim(&executable, directory.path(), ShimLink::Tracking).unwrap();

    let metadata = std::fs::symlink_metadata(&shim).unwrap();
    assert!(
        metadata.file_type().is_symlink(),
        "the session shim should be a symlink, found {metadata:?}"
    );
    assert_eq!(std::fs::read_link(&shim).unwrap(), executable);
}

/// The `tuist_cargo_cache setup` wrapper keeps the bytes it was installed from.
///
/// A symlink there would break the moment the binary it names is deleted, and
/// nothing execs it soon enough for the race to matter.
#[cfg(unix)]
#[test]
fn the_installed_wrapper_pins_the_bytes_it_was_made_from() {
    let directory = tempfile::tempdir().unwrap();
    let executable = std::env::current_exe().unwrap();
    let shim = install_shim(&executable, directory.path(), ShimLink::Pinned).unwrap();

    assert!(
        !std::fs::symlink_metadata(&shim)
            .unwrap()
            .file_type()
            .is_symlink()
    );
    // Length rather than contents: the point is that the shim is a file of its
    // own and not a name that can dangle, and reading the binary twice to prove
    // it costs a hundred megabytes.
    assert_eq!(
        std::fs::metadata(&shim).unwrap().len(),
        std::fs::metadata(&executable).unwrap().len()
    );
}

/// No shim is ever installed as a link to nothing.
///
/// A symlink can name a target that does not exist, so the tracking path has to
/// decline one; the hard link it falls back to then fails where the mistake was
/// made rather than when cargo execs the wrapper.
#[cfg(unix)]
#[test]
fn a_shim_is_never_installed_as_a_link_to_nothing() {
    let directory = tempfile::tempdir().unwrap();
    for missing in [
        directory.path().join("gone"),
        PathBuf::from("relative/tuist_cargo_cache"),
    ] {
        assert!(
            install_shim(&missing, directory.path(), ShimLink::Tracking).is_err(),
            "{} should not install a shim",
            missing.display()
        );
    }
}

/// A relative target is resolved before it is linked, not after.
///
/// A symlink resolves its target from the shim's own directory, and the session
/// shim's directory is a temporary one that shares nothing with the caller's, so
/// the relative target a hard link would have read from the working directory
/// has to be resolved against that directory here. `Cargo.toml` stands in for
/// the binary: under test is how the path is read, not what it points at.
#[cfg(unix)]
#[test]
fn a_relative_target_is_resolved_before_it_is_linked() {
    let directory = tempfile::tempdir().unwrap();
    let shim = directory.path().join(RUSTC_SHIM_STEM);
    assert!(symlink_shim(Path::new("Cargo.toml"), &shim));

    let target = std::fs::read_link(&shim).unwrap();
    assert!(
        target.is_absolute(),
        "{} should be absolute",
        target.display()
    );
    // Resolves through the link, which it could not if the target had been left
    // relative: the shim's own directory holds no `Cargo.toml`.
    assert_eq!(
        std::fs::canonicalize(&shim).unwrap(),
        std::fs::canonicalize("Cargo.toml").unwrap()
    );
}

/// An image with a C compiler and no C++ one is ordinary, and it must not cost
/// a C-only sys-crate its caching.
#[test]
fn a_missing_cpp_compiler_still_leaves_c_compilations_cached() {
    let shims = CcShims {
        cc: Some((
            PathBuf::from("/session/tuist_cargo_cache-c"),
            PathBuf::from("/usr/bin/cc"),
        )),
        cxx: None,
        targeted: Vec::new(),
    };
    let mut environment = BTreeMap::new();
    shims.apply_host(&mut environment);

    assert_eq!(
        environment.get("HOST_CC").map(String::as_str),
        Some("/session/tuist_cargo_cache-c")
    );
    assert_eq!(
        environment
            .get("TUIST_CARGO_CACHE_REAL_CC")
            .map(String::as_str),
        Some("/usr/bin/cc")
    );
    // Nothing is claimed for the language that has no compiler, so the `cc`
    // crate keeps whatever it would have chosen for C++.
    assert!(!environment.contains_key("HOST_CXX"));
    assert!(!environment.contains_key("TUIST_CARGO_CACHE_REAL_CXX"));
}

/// Both present is the ordinary case, and both get pointed at their shim.
#[test]
fn both_compilers_present_are_both_redirected() {
    let shims = CcShims {
        cc: Some((
            PathBuf::from("/session/tuist_cargo_cache-c"),
            PathBuf::from("/usr/bin/cc"),
        )),
        cxx: Some((
            PathBuf::from("/session/tuist_cargo_cache-cxx"),
            PathBuf::from("/usr/bin/c++"),
        )),
        targeted: Vec::new(),
    };
    let mut environment = BTreeMap::new();
    shims.apply_host(&mut environment);
    for name in [
        "HOST_CC",
        "HOST_CXX",
        "TUIST_CARGO_CACHE_REAL_CC",
        "TUIST_CARGO_CACHE_REAL_CXX",
    ] {
        assert!(environment.contains_key(name), "{name} should be set");
    }
}

/// The `cc` crate names a compiler for a target in four ways, and only those
/// four should be wrapped -- `CCACHE_DIR` and friends merely start with the
/// same letters.
#[test]
fn only_the_cc_crates_target_variables_name_a_cross_compiler() {
    use CcLanguage::{C, Cxx};
    for (variable, expected) in [
        ("TARGET_CC", Some(C)),
        ("TARGET_CXX", Some(Cxx)),
        ("CC_aarch64-unknown-linux-musl", Some(C)),
        ("CC_aarch64_unknown_linux_musl", Some(C)),
        ("CXX_aarch64-unknown-linux-musl", Some(Cxx)),
        ("CC", None),
        ("CXX", None),
        ("HOST_CC", None),
        ("CC_", None),
        ("CCACHE_DIR", None),
        ("CXXFLAGS", None),
        // The `cc` crate hangs its own controls off the same prefix, and
        // autotools adds one of its own. Redirecting any of them would answer
        // a question the build asked with a compiler path.
        ("CC_FORCE_DISABLE", None),
        ("CC_KNOWN_WRAPPER_CUSTOM", None),
        ("CC_ENABLE_DEBUG_OUTPUT", None),
        ("CC_FOR_BUILD", None),
        ("CXX_FOR_BUILD", None),
        // A bare word is not a triple either.
        ("CC_gcc", None),
    ] {
        assert_eq!(
            targeted_compiler_language(variable).map(|l| format!("{l:?}")),
            expected.map(|l| format!("{l:?}")),
            "{variable}"
        );
    }
}

/// A build already pointed at a shim -- an outer session's, or this one's --
/// must not have a second shim put in front of it, or the inner one execs
/// itself.
#[test]
fn a_compiler_that_is_already_a_shim_is_not_wrapped_again() {
    let executable = std::env::current_exe().expect("current exe");
    let shims = tempfile::tempdir().expect("tempdir");
    let planted = shims.path().join("aarch64-linux-musl-gcc");
    std::fs::write(&planted, "#!/bin/sh\nexit 0\n").expect("write shim");

    assert_eq!(
        resolve_named_compiler(&planted.display().to_string(), &executable, shims.path()),
        None,
        "a compiler inside the shim directory is a shim, not a compiler"
    );
}

/// A cross image is entitled to ship the driver it cross-compiles with and no
/// host `cc` at all, and that build is exactly the one this wrapping exists
/// for.
#[test]
fn a_cross_only_image_still_gets_its_named_compiler_wrapped() {
    let shims = CcShims {
        cc: None,
        cxx: None,
        targeted: vec![TargetedCompiler {
            variable: "CC_aarch64-unknown-linux-musl".into(),
            shim_name: "tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl".into(),
            shim: PathBuf::from("/session/tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl"),
            real: PathBuf::from("/usr/bin/aarch64-linux-musl-gcc"),
        }],
    };
    let mut environment = BTreeMap::new();
    shims.apply_host(&mut environment);
    shims.apply_targeted(&mut environment);

    // Nothing is claimed for a host compiler that is not there...
    assert!(!environment.contains_key("HOST_CC"));
    // ...and the cross one is still wrapped.
    assert_eq!(
        environment
            .get("CC_aarch64-unknown-linux-musl")
            .map(String::as_str),
        Some("/session/tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl")
    );
    assert!(!shims.pins().is_empty());
}

/// A value that is a command rather than a path is left alone: wrapping it
/// would mean running the first word and dropping the rest.
#[test]
fn a_compiler_named_as_a_command_is_not_wrapped() {
    let executable = std::env::current_exe().expect("current exe");
    let shims = tempfile::tempdir().expect("tempdir");
    for value in ["ccache gcc", "", "   ", "cc -m32"] {
        assert_eq!(
            resolve_named_compiler(value, &executable, shims.path()),
            None,
            "{value:?} is not a single executable"
        );
    }
}

/// A build that named its own cross compiler still gets it wrapped, even
/// though it named its host compiler too and tuist_cargo_cache stood aside for that one.
#[test]
fn naming_a_host_compiler_does_not_cost_the_cross_one_its_shim() {
    let shims = CcShims {
        cc: Some((
            PathBuf::from("/session/tuist_cargo_cache-c"),
            PathBuf::from("/usr/bin/cc"),
        )),
        cxx: None,
        targeted: vec![TargetedCompiler {
            variable: "CC_aarch64-unknown-linux-musl".into(),
            shim_name: "tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl".into(),
            shim: PathBuf::from("/session/tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl"),
            real: PathBuf::from("/usr/bin/aarch64-linux-musl-gcc"),
        }],
    };
    let mut environment = BTreeMap::new();
    shims.apply_targeted(&mut environment);

    assert_eq!(
        environment
            .get("CC_aarch64-unknown-linux-musl")
            .map(String::as_str),
        Some("/session/tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl")
    );
    // Standing aside for the host pair must not have been applied here.
    assert!(!environment.contains_key("HOST_CC"));
    // The shim finds its compiler by the name it is invoked under.
    assert_eq!(
        shims
            .pins()
            .get("tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl"),
        Some(&PathBuf::from("/usr/bin/aarch64-linux-musl-gcc"))
    );
}

/// A targeted shim has to be recognised as one, or it would exec nothing.
#[test]
fn targeted_shim_names_dispatch_to_their_language() {
    for (stem, expected) in [
        ("tuist_cargo_cache-c", Some(CcLanguage::C)),
        ("tuist_cargo_cache-cxx", Some(CcLanguage::Cxx)),
        (
            "tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl",
            Some(CcLanguage::C),
        ),
        (
            "tuist_cargo_cache-cxx-cxx_aarch64-unknown-linux-musl",
            Some(CcLanguage::Cxx),
        ),
        ("tuist_cargo_cache-c-target_cc", Some(CcLanguage::C)),
        ("tuist_cargo_cache-cxx-target_cxx", Some(CcLanguage::Cxx)),
        ("tuist_cargo_cache-rustc", None),
        ("gcc", Some(CcLanguage::C)),
        ("clang++", Some(CcLanguage::Cxx)),
    ] {
        assert_eq!(cc_shim_language(stem), expected, "{stem}");
    }
}

/// The shim directory outlives the session that wrote it: a configure step
/// records its compiler by absolute path, so a tree configured by an tuist_cargo_cache that
/// installed `tuist_cargo_cache-cc` still invokes that name after an upgrade. Recognising it
/// is what keeps that build compiling instead of running tuist_cargo_cache's CLI.
#[test]
fn the_shim_name_used_before_the_rename_is_still_recognised() {
    assert_eq!(
        cc_shim_language("tuist_cargo_cache-cc"),
        Some(CcLanguage::C)
    );
    assert_eq!(
        cc_shim_language("tuist_cargo_cache-cc-cc_aarch64-unknown-linux-musl"),
        Some(CcLanguage::C)
    );
}

/// Recognising the old name is not enough on its own. A targeted shim finds
/// its cross compiler by looking its own invocation name up in the pin map, so
/// a build whose makefiles recorded `tuist_cargo_cache-cc-<variable>` has to reach the same
/// entry as one that recorded `tuist_cargo_cache-c-<variable>`. Pinning only the new name
/// would not fail that build -- the lookup would fall through to `TUIST_CARGO_CACHE_REAL_CC`
/// and quietly build the cross target's objects with the host compiler.
#[test]
fn a_cross_compiler_is_pinned_under_its_pre_rename_name_too() {
    let shims = CcShims {
        cc: Some((
            PathBuf::from("/session/tuist_cargo_cache-c"),
            PathBuf::from("/usr/bin/cc"),
        )),
        cxx: Some((
            PathBuf::from("/session/tuist_cargo_cache-cxx"),
            PathBuf::from("/usr/bin/c++"),
        )),
        targeted: vec![
            TargetedCompiler {
                variable: "CC_aarch64-unknown-linux-musl".into(),
                shim_name: "tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl".into(),
                shim: PathBuf::from("/session/tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl"),
                real: PathBuf::from("/usr/bin/aarch64-linux-musl-gcc"),
            },
            TargetedCompiler {
                variable: "CXX_aarch64-unknown-linux-musl".into(),
                shim_name: "tuist_cargo_cache-cxx-cxx_aarch64-unknown-linux-musl".into(),
                shim: PathBuf::from(
                    "/session/tuist_cargo_cache-cxx-cxx_aarch64-unknown-linux-musl",
                ),
                real: PathBuf::from("/usr/bin/aarch64-linux-musl-g++"),
            },
        ],
    };
    let pins = shims.pins();

    let cross_cc = PathBuf::from("/usr/bin/aarch64-linux-musl-gcc");
    assert_eq!(
        pins.get("tuist_cargo_cache-c-cc_aarch64-unknown-linux-musl"),
        Some(&cross_cc)
    );
    assert_eq!(
        pins.get("tuist_cargo_cache-cc-cc_aarch64-unknown-linux-musl"),
        Some(&cross_cc),
        "the pre-rename name must reach the cross compiler, not the host one"
    );
    // C++ never carried a legacy spelling, so it gains no alias.
    assert_eq!(
        pins.keys().filter(|name| name.contains("cxx")).count(),
        1,
        "{pins:?}"
    );
}

/// A compiler path ending in `-cc` or `-gcc` reads as a cross-compiler prefix:
/// `aarch64-linux-gnu-gcc` compiles for `aarch64-linux-gnu`. The `autotools`
/// crate strips that suffix off whatever `CC` holds and passes the remainder to
/// `configure` as `--host`, so `CC=/var/cache/tuist_cargo_cache/shims/tuist_cargo_cache-cc` became
/// `--host=/var/cache/tuist_cargo_cache/shims/tuist_cargo_cache` and `config.sub` rejected it, failing
/// every `protobuf-src`-style build script. Every name a `CC` or `CXX`
/// variable can carry has to stay clear of both suffixes.
#[test]
fn no_shim_name_can_be_read_as_a_cross_compiler_prefix() {
    let targeted = |variable: &str, language: CcLanguage| {
        format!(
            "{}-{}",
            language.shim_stem(),
            variable.to_ascii_lowercase().replace(['.', '/'], "_")
        )
    };
    let names = [
        CC_SHIM_STEM.to_string(),
        CXX_SHIM_STEM.to_string(),
        targeted("TARGET_CC", CcLanguage::C),
        targeted("TARGET_CXX", CcLanguage::Cxx),
        targeted("CC_aarch64-unknown-linux-musl", CcLanguage::C),
        targeted("CXX_aarch64-unknown-linux-musl", CcLanguage::Cxx),
    ]
    .into_iter()
    .chain(PATH_SHIM_NAMES.iter().map(|(name, _)| (*name).to_string()));
    for name in names {
        // The absolute form is what a build script reads, and it is the whole
        // path that the suffix is stripped from.
        let installed = format!("/var/cache/tuist_cargo_cache/shims/{name}");
        for suffix in ["-cc", "-gcc"] {
            assert!(
                !installed.ends_with(suffix),
                "{installed} ends in {suffix}, which autoconf tooling reads as a machine triple"
            );
        }
    }
}

#[test]
fn managed_target_linkers_follow_rustc_target_and_leave_host_alone() {
    let selections = BTreeMap::from([
        (
            "aarch64-apple-darwin".into(),
            PathBuf::from("/tools/arm/ld64.lld"),
        ),
        (
            "x86_64-apple-darwin".into(),
            PathBuf::from("/tools/intel/ld64.lld"),
        ),
    ]);
    for (argument, expected) in [
        (
            vec!["--target", "aarch64-apple-darwin"],
            Some("/tools/arm/ld64.lld"),
        ),
        (
            vec!["--target=x86_64-apple-darwin"],
            Some("/tools/intel/ld64.lld"),
        ),
        (vec!["--crate-name", "build_script_build"], None),
        (vec!["--target=other"], None),
    ] {
        let arguments = argument.into_iter().map(OsString::from).collect::<Vec<_>>();
        assert_eq!(
            target_linker(&arguments, &selections).map(|p| p.as_path()),
            expected.map(Path::new)
        );
    }
}

#[test]
fn json_target_linkers_match_equivalent_paths() {
    let directory = tempfile::tempdir().unwrap();
    let target = directory.path().join("custom.json");
    std::fs::write(&target, "{}").unwrap();
    let canonical = std::fs::canonicalize(&target).unwrap();
    let linker = PathBuf::from("/tools/linker");
    let selections = BTreeMap::from([(canonical.to_str().unwrap().to_owned(), linker.clone())]);
    // tempdir's ordinary Windows path lacks canonicalize's verbatim prefix.
    assert_eq!(
        target_linker(&["--target".into(), target.into_os_string()], &selections),
        Some(&linker)
    );
    #[cfg(unix)]
    {
        let alias = directory.path().join("alias.json");
        std::os::unix::fs::symlink(&canonical, &alias).unwrap();
        assert_eq!(
            target_linker(&["--target".into(), alias.into_os_string()], &selections),
            Some(&linker)
        );
    }
}

/// Expected cache limitations stay at debug severity; failed cache reads and
/// unknown errors must retain warnings so actionable failures remain visible.
#[test]
fn routine_bypasses_are_debug_but_failed_cache_paths_are_warnings() {
    assert!(super::expected_rustc_bypass(Some(
        &tuist_cargo_cache_rustc::BypassReason::CompilerQuery
    )));
    assert!(super::expected_rustc_bypass(Some(
        &tuist_cargo_cache_rustc::BypassReason::BuildScriptInputOverlapsOutputs(".".into())
    )));
    assert!(super::expected_cc_bypass(Some(
        &tuist_cargo_cache_cc::CcBypassReason::NotACompile
    )));
    assert!(!super::expected_rustc_bypass(Some(
        &tuist_cargo_cache_rustc::BypassReason::InputRead {
            path: "input.rs".into(),
            message: "permission denied".into(),
        }
    )));
    assert!(!super::expected_cc_bypass(Some(
        &tuist_cargo_cache_cc::CcBypassReason::CompilerIdentityUnavailable("probe failed".into())
    )));
    assert!(!super::expected_rustc_bypass(None));
    assert!(!super::expected_cc_bypass(None));
    assert!(super::expected_cc_bypass(Some(
        &tuist_cargo_cache_cc::CcBypassReason::SearchPathModifiedDuringCompilation(
            "include".into()
        )
    )));
    assert!(
        matches!(super::bypass_diagnostic(true, "routine"), AgentRequest::RecordDebug { target, .. } if target == "tuist_cargo_cache::session")
    );
    assert!(matches!(
        super::bypass_diagnostic(false, "failed"),
        AgentRequest::RecordWarning { .. }
    ));
}
