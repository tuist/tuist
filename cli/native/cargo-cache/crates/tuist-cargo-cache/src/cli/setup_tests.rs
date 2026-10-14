use super::*;

#[test]
fn setup_installs_the_cargo_shim() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join(if cfg!(windows) {
        "tuist_cargo_cache.exe"
    } else {
        "tuist_cargo_cache"
    });
    std::fs::write(&executable, b"tuist_cargo_cache binary").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        let mut permissions = std::fs::metadata(&executable).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&executable, permissions).unwrap();
    }
    let install = directory.path().join("data/bin");
    setup_at(&executable, &install).unwrap();

    let wrapper = install.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    assert!(wrapper.is_file());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;

        assert!(
            !std::fs::symlink_metadata(&wrapper)
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_ne!(
            std::fs::metadata(&wrapper).unwrap().permissions().mode() & 0o100,
            0
        );
        std::fs::remove_file(&executable).unwrap();
        std::fs::write(&executable, b"new tuist_cargo_cache binary").unwrap();
        assert_eq!(std::fs::read(&wrapper).unwrap(), CARGO_SHIM_LAUNCHER);
    }
}

#[test]
fn setup_puts_rust_analyzer_checks_through_the_stable_cargo_shim() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join(if cfg!(windows) {
        "tuist_cargo_cache.exe"
    } else {
        "tuist_cargo_cache"
    });
    std::fs::write(&executable, b"tuist_cargo_cache binary").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        let mut permissions = std::fs::metadata(&executable).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&executable, permissions).unwrap();
    }
    let install = directory.path().join("data/bin");
    let config = directory
        .path()
        .join("config/rust-analyzer/rust-analyzer.toml");

    assert_eq!(
        setup_with_rust_analyzer(
            &executable,
            &install,
            &MiseScope::None,
            &config,
            None,
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );

    let document = std::fs::read_to_string(&config)
        .unwrap()
        .parse::<toml_edit::DocumentMut>()
        .unwrap();
    let command = document["check"]["overrideCommand"].as_array().unwrap();
    let shim = install.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    assert!(command.iter().map(|value| value.as_str().unwrap()).eq([
        shim.to_str().unwrap(),
        "check",
        "--workspace",
        "--all-targets",
        "--target-dir",
        "target/rust-analyzer",
        "--message-format=json",
    ]));
    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Status).unwrap(),
        ExitCode::SUCCESS
    );
}

#[test]
fn setup_upgrades_its_existing_rust_analyzer_command() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("rust-analyzer.toml");
    let shim = directory.path().join("bin/cargo");
    let mut command = toml_edit::Array::new();
    command.extend([
        shim.to_string_lossy().into_owned(),
        "check".into(),
        "--workspace".into(),
        "--all-targets".into(),
        "--message-format=json".into(),
    ]);
    let mut document = toml_edit::DocumentMut::new();
    document["check"]["overrideCommand"] = toml_edit::value(command);
    std::fs::write(&config, document.to_string()).unwrap();

    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Status).unwrap(),
        ExitCode::FAILURE
    );
    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Install).unwrap(),
        ExitCode::SUCCESS
    );

    let written = std::fs::read_to_string(config).unwrap();
    assert!(written.contains("target/rust-analyzer"));
}

#[test]
fn setup_preserves_an_existing_rust_analyzer_command() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("rust-analyzer.toml");
    let original = "# keep me\n[check]\noverrideCommand = [\"cargo\", \"clippy\"]\n";
    std::fs::write(&config, original).unwrap();

    assert_eq!(
        configure_rust_analyzer(
            &config,
            &directory.path().join("bin/cargo"),
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
    assert_eq!(
        configure_rust_analyzer(
            &config,
            &directory.path().join("bin/cargo"),
            SetupAction::Uninstall,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );

    assert_eq!(std::fs::read_to_string(config).unwrap(), original);
}

#[test]
fn setup_preserves_existing_rust_analyzer_check_settings() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("rust-analyzer.toml");
    let original = "# keep me\n[check]\ncommand = \"clippy\"\nfeatures = [\"editor\"]\n";
    std::fs::write(&config, original).unwrap();

    assert_eq!(
        configure_rust_analyzer(
            &config,
            &directory.path().join("bin/cargo"),
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );

    assert_eq!(std::fs::read_to_string(config).unwrap(), original);
}

#[test]
fn project_rust_analyzer_config_follows_the_active_cargo_workspace() {
    let directory = tempfile::tempdir().unwrap();
    let project = directory.path().join("project");
    let crate_root = project.join("crates/app");
    let source = crate_root.join("src");
    std::fs::create_dir_all(&source).unwrap();
    std::fs::write(crate_root.join("Cargo.toml"), "[workspace]\n").unwrap();
    let mise_config = project.join("mise.toml");
    std::fs::write(&mise_config, "").unwrap();

    assert_eq!(
        project_rust_analyzer_config_path_from(&MiseScope::File(mise_config), &source).unwrap(),
        Some(crate_root.join("rust-analyzer.toml"))
    );
    assert_eq!(
        project_rust_analyzer_config_path_from(&MiseScope::Global, &source).unwrap(),
        Some(crate_root.join("rust-analyzer.toml"))
    );
    assert_eq!(
        project_rust_analyzer_config_path_from(&MiseScope::Global, directory.path()).unwrap(),
        None
    );
}

#[test]
fn setup_removes_a_project_override_rust_analyzer_never_ran() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("tuist_cargo_cache");
    std::fs::write(&executable, b"tuist_cargo_cache binary").unwrap();
    let install = directory.path().join("data/bin");
    let shim = install.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    let config = directory
        .path()
        .join("config/rust-analyzer/rust-analyzer.toml");
    let project_config = directory.path().join("project/rust-analyzer.toml");
    std::fs::create_dir_all(project_config.parent().unwrap()).unwrap();
    let mut command = toml_edit::Array::new();
    command.extend([
        shim.to_string_lossy().into_owned(),
        "check".into(),
        "--workspace".into(),
        "--all-targets".into(),
        "--target-dir".into(),
        "target/rust-analyzer".into(),
        "--message-format=json".into(),
    ]);
    let mut document = toml_edit::DocumentMut::new();
    document["check"]["overrideCommand"] = toml_edit::value(command);
    std::fs::write(&project_config, document.to_string()).unwrap();

    assert_eq!(
        setup_with_rust_analyzer(
            &executable,
            &install,
            &MiseScope::None,
            &config,
            Some(project_config.as_path()),
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );

    assert!(!project_config.exists());
    assert!(
        std::fs::read_to_string(&config)
            .unwrap()
            .contains("overrideCommand")
    );
}

#[test]
fn setup_keeps_project_rust_analyzer_settings_it_does_not_own() {
    let directory = tempfile::tempdir().unwrap();
    let shim = directory.path().join("bin/cargo");
    let config = directory.path().join("user/rust-analyzer.toml");
    let project_config = directory.path().join("project/rust-analyzer.toml");
    std::fs::create_dir_all(project_config.parent().unwrap()).unwrap();
    let original = "# keep me\n[check]\noverrideCommand = [\"cargo\", \"clippy\"]\n";
    std::fs::write(&project_config, original).unwrap();

    remove_inactive_project_override(&project_config, &shim, &config).unwrap();

    assert_eq!(std::fs::read_to_string(&project_config).unwrap(), original);

    let mut command = toml_edit::Array::new();
    command.extend([
        shim.to_string_lossy().into_owned(),
        "check".into(),
        "--workspace".into(),
        "--all-targets".into(),
        "--target-dir".into(),
        "target/rust-analyzer".into(),
        "--message-format=json".into(),
    ]);
    let mut document = "[cargo]\nfeatures = [\"editor\"]\n"
        .parse::<toml_edit::DocumentMut>()
        .unwrap();
    document["check"]["overrideCommand"] = toml_edit::value(command);
    std::fs::write(&project_config, document.to_string()).unwrap();

    remove_inactive_project_override(&project_config, &shim, &config).unwrap();

    let written = std::fs::read_to_string(&project_config).unwrap();
    assert!(written.contains("features"));
    assert!(!written.contains("overrideCommand"));
}

#[test]
fn setup_uninstall_removes_only_its_rust_analyzer_command() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("rust-analyzer.toml");
    let shim = directory.path().join("bin/cargo");
    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Install).unwrap(),
        ExitCode::SUCCESS
    );
    let mut document = std::fs::read_to_string(&config)
        .unwrap()
        .parse::<toml_edit::DocumentMut>()
        .unwrap();
    document["check"]["ignore"] = toml_edit::value(toml_edit::Array::from_iter(["dead_code"]));
    std::fs::write(&config, document.to_string()).unwrap();

    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Uninstall).unwrap(),
        ExitCode::SUCCESS
    );

    let written = std::fs::read_to_string(config).unwrap();
    assert!(written.contains("ignore"));
    assert!(!written.contains("overrideCommand"));
}

#[test]
fn uninstall_keeps_the_shared_override_until_the_machine_wide_scope_goes() {
    let directory = tempfile::tempdir().unwrap();
    let config = directory.path().join("rust-analyzer.toml");
    let shim = directory.path().join("bin/cargo");
    assert!(!rust_analyzer_override_is_installed(&config, &shim).unwrap());
    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Install).unwrap(),
        ExitCode::SUCCESS
    );
    assert!(rust_analyzer_override_is_installed(&config, &shim).unwrap());

    assert!(override_is_shared_with_other_scopes(&MiseScope::Local));
    assert!(override_is_shared_with_other_scopes(&MiseScope::File(
        directory.path().join("mise.toml")
    )));
    assert!(!override_is_shared_with_other_scopes(&MiseScope::Global));
    assert!(!override_is_shared_with_other_scopes(&MiseScope::None));

    assert_eq!(
        configure_rust_analyzer(&config, &shim, SetupAction::Uninstall).unwrap(),
        ExitCode::SUCCESS
    );
    assert!(!rust_analyzer_override_is_installed(&config, &shim).unwrap());
}

#[test]
fn mise_config_paths_compare_by_identity() {
    // `Path` equality already folds away `.`, so these cases use spellings it
    // keeps: a `..` component, and a symlinked directory.
    let directory = tempfile::tempdir().unwrap();
    let nested = directory.path().join("nested");
    std::fs::create_dir(&nested).unwrap();
    let config = directory.path().join("config.toml");
    std::fs::write(&config, "").unwrap();
    let detour = nested.join("..").join("config.toml");
    assert_ne!(config, detour);

    assert!(same_config_path(&config, &config));
    assert!(same_config_path(&config, &detour));
    assert!(!same_config_path(
        &config,
        &directory.path().join("other.toml")
    ));

    // A config mise has not written yet still resolves through its directory.
    let absent = nested.join("mise.toml");
    let absent_detour = nested.join("..").join("nested").join("mise.toml");
    assert_ne!(absent, absent_detour);
    assert!(same_config_path(&absent, &absent_detour));
    assert!(!same_config_path(&absent, &nested.join("other.toml")));

    #[cfg(unix)]
    {
        let link = directory.path().join("link");
        std::os::unix::fs::symlink(directory.path(), &link).unwrap();
        assert!(same_config_path(&config, &link.join("config.toml")));
    }
}

#[test]
fn setup_status_detects_a_missing_rust_analyzer_command() {
    let directory = tempfile::tempdir().unwrap();
    assert_eq!(
        configure_rust_analyzer(
            &directory.path().join("rust-analyzer.toml"),
            &directory.path().join("bin/cargo"),
            SetupAction::Status,
        )
        .unwrap(),
        ExitCode::FAILURE
    );
}

#[test]
fn setup_flags_are_mutually_exclusive() {
    let args = SetupArgs {
        yes: false,
        global: false,
        local: false,
        status: true,
        uninstall: true,
    };
    assert!(args.action().is_err());
    assert!(
        SetupArgs {
            yes: false,
            global: true,
            local: true,
            status: false,
            uninstall: false,
        }
        .validate()
        .is_err()
    );
    assert_eq!(
        SetupArgs {
            yes: false,
            global: false,
            local: false,
            status: false,
            uninstall: true,
        }
        .action()
        .unwrap(),
        SetupAction::Uninstall
    );
}

#[test]
fn setup_status_detects_and_setup_refreshes_a_replaced_wrapper() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("tuist_cargo_cache");
    std::fs::write(&executable, b"first tuist_cargo_cache binary").unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt as _;
        std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o755)).unwrap();
    }
    let install = directory.path().join("data/bin");
    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
    assert_eq!(
        setup_at_action(&executable, &install, &MiseScope::None, SetupAction::Status,).unwrap(),
        ExitCode::SUCCESS
    );

    let shim = install.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    std::fs::remove_file(&shim).unwrap();
    std::fs::write(&shim, b"stale tuist_cargo_cache binary").unwrap();
    #[cfg(windows)]
    std::fs::remove_file(install.join(super::CARGO_SHIM_TARGET_FILE)).unwrap();
    assert_eq!(
        setup_at_action(&executable, &install, &MiseScope::None, SetupAction::Status,).unwrap(),
        ExitCode::FAILURE
    );
    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
    assert!(cargo_shim_is_current(&executable, &shim).unwrap());
}

#[cfg(unix)]
#[test]
fn setup_status_reports_a_shim_whose_target_was_removed_as_outdated() {
    use std::os::unix::fs::PermissionsExt as _;

    let directory = tempfile::tempdir().unwrap();
    let removed = directory.path().join("removed/tuist_cargo_cache");
    std::fs::create_dir_all(removed.parent().unwrap()).unwrap();
    std::fs::write(&removed, b"old tuist_cargo_cache binary").unwrap();
    std::fs::set_permissions(&removed, std::fs::Permissions::from_mode(0o755)).unwrap();
    let install = directory.path().join("data/bin");
    assert_eq!(
        setup_at_action(&removed, &install, &MiseScope::None, SetupAction::Install).unwrap(),
        ExitCode::SUCCESS
    );
    std::fs::remove_dir_all(removed.parent().unwrap()).unwrap();

    let executable = directory.path().join("tuist_cargo_cache");
    std::fs::write(&executable, b"tuist_cargo_cache binary").unwrap();
    std::fs::set_permissions(&executable, std::fs::Permissions::from_mode(0o755)).unwrap();
    let shim = install.join("cargo");
    assert!(!cargo_shim_is_current(&executable, &shim).unwrap());
    assert_eq!(
        setup_at_action(&executable, &install, &MiseScope::None, SetupAction::Status).unwrap(),
        ExitCode::FAILURE
    );

    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
    assert!(cargo_shim_is_current(&executable, &shim).unwrap());
}

#[test]
fn setup_uninstall_keeps_the_shared_shim() {
    let directory = tempfile::tempdir().unwrap();
    let executable = directory.path().join("tuist_cargo_cache");
    std::fs::write(&executable, b"tuist_cargo_cache binary").unwrap();
    let install = directory.path().join("data/bin");
    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Install,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
    let shim = install.join(if cfg!(windows) { "cargo.exe" } else { "cargo" });
    assert!(shim.is_file());
    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Uninstall,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );

    assert!(shim.exists());
    assert_eq!(
        setup_at_action(
            &executable,
            &install,
            &MiseScope::None,
            SetupAction::Uninstall,
        )
        .unwrap(),
        ExitCode::SUCCESS
    );
}

#[test]
fn mise_config_selection_finds_the_first_config_that_defines_cargo_cache() {
    let configs = br#"[
        {"path":"/project/mise.toml","tools":["rust","github:jdx/mr-boxington"]},
        {"path":"/global/config.toml","tools":["mr-boxington"]}
    ]"#;

    assert_eq!(
        cargo_cache_mise_config_from_json(configs),
        Some(PathBuf::from("/project/mise.toml"))
    );
    assert_eq!(cargo_cache_mise_config_from_json(b"not json"), None);
}

#[test]
fn mise_wrapper_version_parsing_uses_the_calendar_version() {
    assert_eq!(
        mise_version_from_output(b"2026.8.16 linux-x64 (2026-08-31)"),
        Some((2026, 8, 16))
    );
    assert_eq!(
        mise_version_from_output(b"v2027.1.2 windows-x64"),
        Some((2027, 1, 2))
    );
    assert_eq!(mise_version_from_output(b"not-a-version"), None);
}

#[test]
fn mise_wrapper_detection_requires_cargo_cache_shim_mode() {
    let configured = r#"
[wrappers.cargo]
command = "tuist_cargo_cache"
env = { TUIST_CARGO_CACHE_CARGO_SHIM_MODE = "1" }
"#
    .parse::<toml_edit::DocumentMut>()
    .unwrap();
    assert!(mise_wrapper_is_configured_in(&configured));

    for raw in [
        "[wrappers]\ncargo = \"tuist_cargo_cache\"\n",
        "[wrappers.cargo]\ncommand = \"tuist_cargo_cache\"\n",
        "[wrappers.cargo]\ncommand = \"other\"\nenv = { TUIST_CARGO_CACHE_CARGO_SHIM_MODE = \"1\" }\n",
    ] {
        let document = raw.parse::<toml_edit::DocumentMut>().unwrap();
        assert!(!mise_wrapper_is_configured_in(&document));
    }
}
