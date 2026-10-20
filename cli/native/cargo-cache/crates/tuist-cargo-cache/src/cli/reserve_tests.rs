use super::*;

#[test]
fn reserve_keeps_its_command_arguments_after_a_separator() {
    let argv = [
        "tuist_cargo_cache",
        "reserve",
        "--memory",
        "6GiB",
        "--cpus",
        "4",
        "--",
        "sh",
        "-c",
        "echo hi",
    ]
    .map(std::ffi::OsStr::new);

    let cli = Cli::try_parse_from(&argv).unwrap();
    let Commands::Reserve(args) = cli.command else {
        panic!("reserve should be reserved by tuist_cargo_cache");
    };
    assert_eq!(args.command, ["sh", "-c", "echo hi"]);
}

#[test]
fn a_toolchain_is_refused_for_reserve() {
    let argv = [
        "tuist_cargo_cache",
        "+nightly",
        "reserve",
        "--cpus",
        "1",
        "true",
    ]
    .map(std::ffi::OsStr::new);
    let cli = Cli::try_parse_from(&argv).unwrap();
    assert_eq!(compiles_nothing(&cli.command), Some("reserve"));
}

#[test]
fn external_work_skips_nested_admission_without_leaking_the_worker_marker() {
    let command = reserve::external_command("echo", &[]);
    let environment = command
        .get_envs()
        .map(|(name, value)| {
            (
                name.to_string_lossy(),
                value.map(|value| value.to_string_lossy()),
            )
        })
        .collect::<std::collections::BTreeMap<_, _>>();

    assert_eq!(
        environment.get("TUIST_CARGO_CACHE_SCHED_DIR"),
        Some(&Some("".into()))
    );
    assert_eq!(
        environment.get("TUIST_CARGO_CACHE_SCHED_DISABLE"),
        Some(&Some("1".into()))
    );
    assert_eq!(
        environment.get("TUIST_CARGO_CACHE_RESERVE_WORKER"),
        Some(&None)
    );
}
