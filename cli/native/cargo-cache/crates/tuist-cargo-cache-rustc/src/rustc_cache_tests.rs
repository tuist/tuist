#[test]
fn verbose_version_is_a_query_not_an_unmodeled_flag() {
    // cargo runs `rustc -vV` to identify the compiler; reporting it as an
    // unmodeled flag sends people hunting for a gap that is not there.
    assert_eq!(
        RustcInvocation::parse(&args(&["-vV"])).unwrap_err(),
        BypassReason::CompilerQuery
    );
}

#[test]
fn bypass_kinds_are_stable_and_field_independent() {
    assert_eq!(BypassReason::CompilerQuery.kind(), "compiler-query");
    assert_eq!(BypassReason::Incremental.kind(), "incremental");
    assert_eq!(
        BypassReason::UnsupportedCrateType("bin".into()).kind(),
        "unsupported-crate-type"
    );
    assert_eq!(
        BypassReason::UnportableNativeLink("rpath=yes".into()).kind(),
        "unportable-native-link"
    );
    assert_eq!(
        BypassReason::UnmodeledLinkArgument("link-arg=-Tlink.x".into()).kind(),
        "unmodeled-link-argument"
    );
    assert_eq!(
        BypassReason::AmbiguousOutputName(PathBuf::from("a.rlib")).kind(),
        "ambiguous-output-name"
    );
    // Two reasons of one kind group together despite differing fields.
    assert_eq!(
        BypassReason::UnmappedAbsolutePath(PathBuf::from("/a")).kind(),
        BypassReason::UnmappedAbsolutePath(PathBuf::from("/b")).kind()
    );
}

#[test]
fn actionable_bypasses_carry_remediation() {
    let codegen_remediation = BypassReason::UnportableNativeLink("split-debuginfo=packed".into())
        .remediation()
        .unwrap();
    assert!(codegen_remediation.contains("Cargo profile"));
    assert!(codegen_remediation.contains("RUSTFLAGS"));

    let linker_remediation =
        BypassReason::UnportableNativeLink("the linker could not be identified".into())
            .remediation()
            .unwrap();
    assert!(linker_remediation.contains("linker"));
    assert!(!linker_remediation.contains("RUSTFLAGS"));
    assert!(BypassReason::CompilerQuery.remediation().is_none());
}

#[cfg(unix)]
#[test]
fn path_mappings_resolve_symlinked_roots_for_missing_outputs() {
    use std::os::unix::fs::symlink;

    let directory = tempfile::tempdir().unwrap();
    let physical = directory.path().join("physical");
    let alias = directory.path().join("alias");
    std::fs::create_dir(&physical).unwrap();
    symlink(&physical, &alias).unwrap();

    let mappings = vec![PathMapping::new(alias, "target")];
    let output = physical.join("debug/deps/not-created.wasm");
    assert_eq!(
        normalize_mapped_path(&output, directory.path(), &mappings).unwrap(),
        "${target}/debug/deps/not-created.wasm"
    );
}

use super::*;

fn args(values: &[&str]) -> Vec<OsString> {
    values.iter().map(OsString::from).collect()
}

fn digest(value: &str) -> CacheDigest {
    CacheDigest::blake3(value.as_bytes())
}

fn absolute(segments: &[&str]) -> PathBuf {
    let mut path = if cfg!(windows) {
        PathBuf::from(r"C:\")
    } else {
        PathBuf::from("/")
    };
    path.extend(segments);
    path
}

fn workspace() -> PathBuf {
    absolute(&["work", "project"])
}

fn sysroot() -> PathBuf {
    absolute(&["toolchains", "1.97.1"])
}

fn context(inputs: &[(&str, &str)]) -> ActionContext {
    ActionContext {
        compiler: CompilerIdentity {
            toolchain: "core:rust@1.97.1".into(),
            rustc_version: "1.97.1 (8bab26f4f 2026-07-14)".into(),
            host: "x86_64-unknown-linux-gnu".into(),
            driver: None,
        },
        working_dir: workspace(),
        path_mappings: vec![
            PathMapping::new(workspace().join("target"), "target"),
            PathMapping::new(workspace(), "workspace"),
            PathMapping::new(absolute(&["home", "user", ".cargo"]), "cargo_home"),
            PathMapping::new(sysroot(), "sysroot"),
        ],
        environment: BTreeMap::from([("CARGO_PKG_VERSION".into(), Some("1.0.0".into()))]),
        portable_environment: BTreeSet::new(),
        inputs: inputs
            .iter()
            .map(|(path, contents)| ActionInput {
                path: (*path).into(),
                digest: digest(contents),
            })
            .collect(),
    }
}

fn common_invocation() -> RustcInvocation {
    let output = workspace().join("target/debug/deps");
    RustcInvocation::parse(&[
        "--crate-name".into(),
        "widget".into(),
        "--edition=2024".into(),
        "src/lib.rs".into(),
        "--crate-type".into(),
        "lib".into(),
        "--emit=dep-info,metadata,link".into(),
        "-Cembed-bitcode=no".into(),
        "-C".into(),
        "metadata=abc123".into(),
        "--out-dir".into(),
        output.clone().into_os_string(),
        format!("-Ldependency={}", output.display()).into(),
        "--extern".into(),
        format!("serde={}", output.join("libserde.rlib").display()).into(),
        format!("--sysroot={}", sysroot().display()).into(),
        "--cap-lints".into(),
        "allow".into(),
    ])
    .unwrap()
}

#[test]
fn parses_a_cargo_library_invocation() {
    let invocation = common_invocation();
    assert_eq!(invocation.source(), Path::new("src/lib.rs"));
    let action = invocation
        .action(context(&[
            ("src/lib.rs", "source"),
            ("target/debug/deps/libserde.rlib", "serde"),
        ]))
        .unwrap();
    let json = String::from_utf8(action.bytes).unwrap();
    assert!(json.contains(r#""kind":"rustc""#));
    assert!(json.contains(r#""--out-dir=${target}/debug/deps""#));
    assert!(json.contains(r#""--extern=serde=${target}/debug/deps/libserde.rlib""#));
    assert_eq!(action.digest.algorithm, "blake3");
}

#[test]
fn compiler_driver_identity_distinguishes_clippy_actions() {
    let invocation = common_invocation();
    let inputs = [
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ];
    let rustc = invocation.action(context(&inputs)).unwrap();
    let mut clippy_context = context(&inputs);
    clippy_context.compiler.driver = Some("clippy 0.1.97 (8bab26f4f6 2026-07-14)".into());
    let clippy = invocation.action(clippy_context).unwrap();

    assert_ne!(clippy.digest, rustc.digest);
    assert!(
        String::from_utf8(clippy.bytes)
            .unwrap()
            .contains(r#""driver":"clippy 0.1.97 (8bab26f4f6 2026-07-14)""#)
    );
    assert!(
        !String::from_utf8(rustc.bytes)
            .unwrap()
            .contains(r#""driver""#)
    );
}

#[test]
fn tracks_native_search_path_contents_and_hashes_a_named_static_library() {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path().join("registry/widget");
    let native = directory.path().join("target/native");
    std::fs::create_dir_all(&working_dir).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    std::fs::write(native.join("fixture.lib"), "first").unwrap();
    let native_argument = format!("-Lnative={}", native.display());
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &native_argument,
        "src.rs",
    ]))
    .unwrap();
    let dep_info = RustcDepInfo::parse("target/debug/deps/widget.d: src.rs\n").unwrap();
    let discovered = invocation
        .discover_inputs_with_mappings(
            &dep_info,
            &working_dir,
            &[PathMapping::new(directory.path().join("target"), "target")],
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    assert!(
        discovered
            .inputs
            .iter()
            .any(|input| input.path == native.join("fixture.lib"))
    );

    let action_context = ActionContext {
        working_dir: working_dir.clone(),
        path_mappings: vec![
            PathMapping::new(&working_dir, "workspace"),
            PathMapping::new(directory.path().join("target"), "target"),
        ],
        inputs: discovered.inputs.clone(),
        ..context(&[])
    };
    let prediction = invocation.prediction(&action_context, &discovered).unwrap();
    assert_eq!(prediction.version, 4);
    std::fs::write(native.join("added.lib"), "second").unwrap();
    let predicted = prediction
        .discover(
            &working_dir,
            &action_context.path_mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    assert!(
        predicted
            .inputs
            .iter()
            .any(|input| input.path == native.join("added.lib"))
    );

    // Naming a static library in that directory is what a `-sys` crate's
    // build script does with `cargo:rustc-link-lib=static`. rustc bundles the
    // archive into the rlib, so it is a required input rather than a bypass.
    // A name of its own, so no host spelling of `fixture` shadows it.
    std::fs::write(native.join("libbundled.a"), "archive").unwrap();
    let linked = RustcInvocation::parse(&args(&[
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        &native_argument,
        "-lstatic=bundled",
        "src/lib.rs",
    ]))
    .unwrap();
    assert!(
        linked
            .required_inputs_in(&working_dir)
            .contains(&native.join("libbundled.a"))
    );
}

/// A `-sys` crate compiled as a library: its build script placed the archive
/// in `OUT_DIR` and told cargo to pass `-L native` and `-l static` for it.
fn static_library_fixture() -> (tempfile::TempDir, PathBuf, PathBuf) {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path().join("registry/zstd-sys");
    let native = directory.path().join("target/debug/build/zstd-sys-abc/out");
    std::fs::create_dir_all(&working_dir).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    (directory, working_dir, native)
}

fn library_linking(native: &[(&str, &Path)], libraries: &[&str]) -> Vec<OsString> {
    let mut arguments = args(&[
        "--crate-name=zstd_sys",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
    ]);
    for (kind, directory) in native {
        arguments.push(format!("-L{kind}{}", directory.display()).into());
    }
    for library in libraries {
        arguments.push("-l".into());
        arguments.push((*library).into());
    }
    arguments.push("src.rs".into());
    arguments
}

fn required_inputs(invocation: &RustcInvocation, working_dir: &Path) -> Vec<PathBuf> {
    let mut inputs = invocation.required_inputs_in(working_dir);
    inputs.retain(|input| input.file_name().is_some_and(|name| name != "src.rs"));
    inputs
}

/// Every `-l` kind that only records a name: rustc reads no file for a
/// dynamic library, a framework, a raw link argument, or the default kind
/// when nothing links, so the flag text is the whole input and stays in the
/// key as written.
#[test]
fn name_only_native_libraries_are_keyed_as_text_on_a_library_emit() {
    let (_directory, working_dir, native) = static_library_fixture();
    let invocation = RustcInvocation::parse(&library_linking(
        &[("native=", &native)],
        &[
            "dylib=z",
            "framework=Security",
            "link-arg=-Wl,--as-needed",
            "m",
        ],
    ))
    .unwrap();
    assert!(required_inputs(&invocation, &working_dir).is_empty());
    let action = invocation
        .action(ActionContext {
            working_dir: working_dir.clone(),
            path_mappings: vec![
                PathMapping::new(&working_dir, "workspace"),
                PathMapping::new(
                    native
                        .parent()
                        .unwrap()
                        .parent()
                        .unwrap()
                        .parent()
                        .unwrap()
                        .parent()
                        .unwrap(),
                    "target",
                ),
            ],
            inputs: vec![ActionInput {
                path: working_dir.join("src.rs"),
                digest: digest("source"),
            }],
            ..context(&[])
        })
        .unwrap();
    let json = String::from_utf8(action.bytes).unwrap();
    for flag in [
        r#""-ldylib=z""#,
        r#""-lframework=Security""#,
        r#""-llink-arg=-Wl,--as-needed""#,
        r#""-lm""#,
    ] {
        assert!(json.contains(flag), "{flag} missing from {json}");
    }
}

/// A static library is read: rustc bundles the archive into the rlib, so the
/// archive is a required input whatever modifiers travel with it.
#[test]
fn a_static_library_is_a_required_input_with_any_bundling_modifiers() {
    let (_directory, working_dir, native) = static_library_fixture();
    std::fs::write(native.join("libzstd.a"), "archive").unwrap();
    for library in [
        "static=zstd",
        "static:+whole-archive=zstd",
        "static:+bundle=zstd",
        "static:-bundle,+bundle=zstd",
        "static:+verbatim,-verbatim=zstd",
    ] {
        let invocation =
            RustcInvocation::parse(&library_linking(&[("native=", &native)], &[library]))
                .unwrap_or_else(|error| panic!("{library}: {error}"));
        assert_eq!(
            required_inputs(&invocation, &working_dir),
            vec![native.join("libzstd.a")],
            "{library}"
        );
    }
}

/// With `-bundle` rustc records the name for the downstream link and never
/// opens the archive, so the flag is text: the archive need not exist, and
/// its contents do not reach the key. The last spelling of the modifier wins.
#[test]
fn an_unbundled_static_library_is_keyed_as_text() {
    let (_directory, working_dir, native) = static_library_fixture();
    for library in [
        "static:-bundle=zstd",
        "static:+whole-archive,-bundle=zstd",
        "static:+bundle,-bundle=zstd",
    ] {
        let invocation =
            RustcInvocation::parse(&library_linking(&[("native=", &native)], &[library]))
                .unwrap_or_else(|error| panic!("{library}: {error}"));
        assert!(
            required_inputs(&invocation, &working_dir).is_empty(),
            "{library}"
        );
    }
}

/// UEFI targets use MSVC library names without `msvc` in the triple, and a
/// custom target specification chooses its own, which the adapter does not
/// read: guessing `libNAME.a` there could hash an archive rustc never bundles.
#[test]
fn static_library_naming_follows_the_target_specification() {
    let (_directory, working_dir, native) = static_library_fixture();
    std::fs::write(native.join("zstd.lib"), "msvc").unwrap();
    std::fs::write(native.join("libzstd.a"), "unix").unwrap();
    let mut uefi = library_linking(&[("native=", &native)], &["static=zstd"]);
    uefi.insert(0, "--target=x86_64-unknown-uefi".into());
    assert_eq!(
        required_inputs(&RustcInvocation::parse(&uefi).unwrap(), &working_dir),
        vec![native.join("zstd.lib")]
    );

    let spec = working_dir.join("custom.json");
    std::fs::write(&spec, "{}").unwrap();
    let mut custom = library_linking(&[("native=", &native)], &["static=zstd"]);
    custom.insert(0, format!("--target={}", spec.display()).into());
    assert_eq!(
        RustcInvocation::parse(&custom),
        Err(BypassReason::CustomTargetNativeLibrary(
            "static=zstd".into()
        ))
    );
    // A bare name is only proven built-in when rustc has nowhere else to
    // look it up.
    let mut bare = library_linking(&[("native=", &native)], &["static=zstd"]);
    bare.insert(0, "--target=x86_64-unknown-linux-gnu".into());
    let options = ParseOptions::default().with_custom_target_search(true);
    assert_eq!(
        RustcInvocation::parse_with(&bare, options),
        Err(BypassReason::CustomTargetNativeLibrary(
            "static=zstd".into()
        ))
    );
    // rustc reads the first `--target`; a second one does not change which
    // naming the archive is looked up under.
    let mut twice = library_linking(&[("native=", &native)], &["static=zstd"]);
    twice.insert(0, "--target=x86_64-unknown-linux-gnu".into());
    twice.insert(1, "--target=x86_64-pc-windows-msvc".into());
    assert_eq!(
        required_inputs(&RustcInvocation::parse(&twice).unwrap(), &working_dir),
        vec![native.join("libzstd.a")]
    );
    // An ignored later specification is keyed but is not read, so it need
    // not exist.
    let mut ignored_spec = library_linking(&[("native=", &native)], &["static=zstd"]);
    ignored_spec.insert(0, "--target=x86_64-unknown-linux-gnu".into());
    ignored_spec.insert(1, "--target=/nowhere/unused.json".into());
    assert_eq!(
        required_inputs(
            &RustcInvocation::parse(&ignored_spec).unwrap(),
            &working_dir
        ),
        vec![native.join("libzstd.a")]
    );

    // `+verbatim` names the file itself, so the specification is not needed.
    let mut verbatim = library_linking(&[("native=", &native)], &["static:+verbatim=libzstd.a"]);
    verbatim.insert(0, format!("--target={}", spec.display()).into());
    let inputs = required_inputs(&RustcInvocation::parse(&verbatim).unwrap(), &working_dir);
    assert!(inputs.contains(&native.join("libzstd.a")), "{inputs:?}");
}

/// `-l static=NAME:RENAME` links RENAME in place of the `#[link]` attribute's
/// NAME, so RENAME is the archive rustc opens.
#[test]
fn a_renamed_static_library_resolves_under_its_new_name() {
    let (_directory, working_dir, native) = static_library_fixture();
    std::fs::write(native.join("librenamed.a"), "archive").unwrap();
    let invocation = RustcInvocation::parse(&library_linking(
        &[("native=", &native)],
        &["static=original:renamed"],
    ))
    .unwrap();
    assert_eq!(
        required_inputs(&invocation, &working_dir),
        vec![native.join("librenamed.a")]
    );
}

/// `+verbatim` turns off the platform naming: the file is NAME itself.
#[test]
fn a_verbatim_static_library_is_named_literally() {
    let (_directory, working_dir, native) = static_library_fixture();
    std::fs::write(native.join("libzstd.a"), "conventional").unwrap();
    std::fs::write(native.join("zstd.lib"), "literal").unwrap();
    let invocation = RustcInvocation::parse(&library_linking(
        &[("native=", &native)],
        &["static:+verbatim=zstd.lib"],
    ))
    .unwrap();
    assert_eq!(
        required_inputs(&invocation, &working_dir),
        vec![native.join("zstd.lib")]
    );
    assert_eq!(
        RustcInvocation::parse(&library_linking(
            &[("native=", &native)],
            &["static:+verbatim=zstd"],
        )),
        Err(BypassReason::MissingNativeLibrary(
            "static:+verbatim=zstd".into()
        ))
    );
}

/// rustc takes the first `-L native` directory, in command order, that holds
/// the archive; `-L dependency` directories are for rlibs and are never
/// searched.
#[test]
fn a_static_library_resolves_in_search_path_order() {
    let (directory, working_dir, native) = static_library_fixture();
    let vendored = directory.path().join("target/vendored");
    let dependency = directory.path().join("target/debug/deps");
    for path in [&vendored, &dependency] {
        std::fs::create_dir_all(path).unwrap();
        std::fs::write(path.join("libzstd.a"), "elsewhere").unwrap();
    }
    std::fs::write(native.join("libzstd.a"), "archive").unwrap();

    let first_wins = RustcInvocation::parse(&library_linking(
        &[
            ("dependency=", &dependency),
            ("native=", &vendored),
            ("native=", &native),
        ],
        &["static=zstd"],
    ))
    .unwrap();
    assert_eq!(
        required_inputs(&first_wins, &working_dir),
        vec![vendored.join("libzstd.a")]
    );

    let order_matters = RustcInvocation::parse(&library_linking(
        &[
            ("dependency=", &dependency),
            ("native=", &native),
            ("native=", &vendored),
        ],
        &["static=zstd"],
    ))
    .unwrap();
    assert_eq!(
        required_inputs(&order_matters, &working_dir),
        vec![native.join("libzstd.a")]
    );

    assert_eq!(
        RustcInvocation::parse(&library_linking(
            &[("dependency=", &dependency)],
            &["static=zstd"],
        )),
        Err(BypassReason::MissingNativeLibrary("static=zstd".into()))
    );
}

/// An MSVC target names its archives `NAME.lib`, and rustc still falls back
/// to the `libNAME.a` a GNU toolchain would have written. Other targets never
/// look for `NAME.lib`.
#[test]
fn a_static_library_is_named_for_the_target() {
    let (_directory, working_dir, native) = static_library_fixture();
    std::fs::write(native.join("zstd.lib"), "msvc").unwrap();
    let mut msvc = library_linking(&[("native=", &native)], &["static=zstd"]);
    msvc.insert(0, "--target=x86_64-pc-windows-msvc".into());
    let invocation = RustcInvocation::parse(&msvc).unwrap();
    assert_eq!(
        required_inputs(&invocation, &working_dir),
        vec![native.join("zstd.lib")]
    );

    let mut gnu = library_linking(&[("native=", &native)], &["static=zstd"]);
    gnu.insert(0, "--target=x86_64-unknown-linux-gnu".into());
    assert_eq!(
        RustcInvocation::parse(&gnu),
        Err(BypassReason::MissingNativeLibrary("static=zstd".into()))
    );
    std::fs::write(native.join("libzstd.a"), "gnu").unwrap();
    assert_eq!(
        required_inputs(&RustcInvocation::parse(&gnu).unwrap(), &working_dir),
        vec![native.join("libzstd.a")]
    );
    assert_eq!(
        required_inputs(&RustcInvocation::parse(&msvc).unwrap(), &working_dir),
        vec![native.join("zstd.lib")]
    );
}

/// A kind rustc itself rejects is not guessed at.
#[test]
fn an_unknown_native_library_kind_bypasses_as_an_unknown_flag() {
    let (_directory, _working_dir, native) = static_library_fixture();
    assert_eq!(
        RustcInvocation::parse(&library_linking(&[("native=", &native)], &["shared=zstd"])),
        Err(BypassReason::UnknownFlag("-lshared=zstd".into()))
    );
}

/// The archive is keyed by content like an `--extern` artifact, along both
/// discovery paths: a rebuilt archive with the same name can never be
/// restored against, and a prediction replays exactly the key dep-info
/// discovery built.
#[test]
fn a_static_library_changes_the_action_key_with_its_contents() {
    let (directory, working_dir, native) = static_library_fixture();
    let archive = native.join("libzstd.a");
    std::fs::write(&archive, "first").unwrap();
    let invocation =
        RustcInvocation::parse(&library_linking(&[("native=", &native)], &["static=zstd"]))
            .unwrap();
    let mappings = vec![
        PathMapping::new(&working_dir, "workspace"),
        PathMapping::new(directory.path().join("target"), "target"),
    ];
    let base = ActionContext {
        working_dir: working_dir.clone(),
        path_mappings: mappings.clone(),
        inputs: Vec::new(),
        ..context(&[])
    };
    let dep_info = RustcDepInfo::parse("target/debug/deps/zstd_sys.d: src.rs\n").unwrap();
    let discovered = invocation
        .discover_inputs_with_mappings(
            &dep_info,
            &working_dir,
            &mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    let mut from_dep_info = base.clone();
    discovered.clone().apply_to(&mut from_dep_info).unwrap();
    let first = invocation.action(from_dep_info).unwrap();
    let json = String::from_utf8(first.bytes.clone()).unwrap();
    assert!(
        json.contains(r#""${target}/debug/build/zstd-sys-abc/out/libzstd.a""#),
        "{json}"
    );
    assert!(json.contains(&CacheDigest::blake3(b"first").hash), "{json}");

    let prediction = invocation.prediction(&base, &discovered).unwrap();
    let replay = |base: &ActionContext| {
        let predicted = prediction
            .discover(
                &working_dir,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .unwrap();
        let mut from_prediction = base.clone();
        predicted.apply_to(&mut from_prediction).unwrap();
        invocation.action(from_prediction)
    };
    assert_eq!(replay(&base).unwrap().digest, first.digest);

    std::fs::write(&archive, "second").unwrap();
    assert_ne!(replay(&base).unwrap().digest, first.digest);

    // The archive sits beneath a walked native directory, so the prediction
    // rediscovers whatever is there; once it is gone, no key can be built
    // rather than one that omits it.
    std::fs::remove_file(&archive).unwrap();
    assert_eq!(
        replay(&base).unwrap_err(),
        BypassReason::MissingRequiredInput(
            "${target}/debug/build/zstd-sys-abc/out/libzstd.a".into()
        )
    );
}

/// A static archive outside every mapped root has no portable name, so the
/// invocation bypasses like an `--extern` there would, on both discovery
/// paths.
#[test]
fn a_static_library_outside_every_mapped_root_bypasses_as_unmapped() {
    let (directory, working_dir, _native) = static_library_fixture();
    let system = directory.path().join("usr/lib");
    std::fs::create_dir_all(&system).unwrap();
    let archive = system.join("libzstd.a");
    std::fs::write(&archive, "system").unwrap();
    let invocation =
        RustcInvocation::parse(&library_linking(&[("native=", &system)], &["static=zstd"]))
            .unwrap();
    let mappings = vec![
        PathMapping::new(&working_dir, "workspace"),
        PathMapping::new(directory.path().join("target"), "target"),
    ];
    let dep_info = RustcDepInfo::parse("target/debug/deps/zstd_sys.d: src.rs\n").unwrap();
    assert_eq!(
        invocation.discover_inputs_with_mappings(
            &dep_info,
            &working_dir,
            &mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        ),
        Err(BypassReason::UnsupportedSearchPath("native".into()))
    );
    let action_context = ActionContext {
        working_dir: working_dir.clone(),
        path_mappings: mappings,
        inputs: Vec::new(),
        ..context(&[])
    };
    assert_eq!(
        invocation.invocation_digest(&action_context),
        Err(BypassReason::UnmappedAbsolutePath(system.clone()))
    );
    assert_eq!(
        invocation.action(action_context).unwrap_err(),
        BypassReason::UnmappedAbsolutePath(system)
    );
}

#[test]
fn expands_utf8_response_files_one_argument_per_line() {
    let directory = tempfile::tempdir().unwrap();
    let response = directory.path().join("rustc.args");
    std::fs::write(
        &response,
        "--crate-name\r\nwidget\r\n--crate-type=lib\r\n--emit=metadata,link\r\nsrc/lib.rs\r\n",
    )
    .unwrap();

    let invocation = RustcInvocation::parse(&[format!("@{}", response.display()).into()]).unwrap();

    assert_eq!(invocation.source(), Path::new("src/lib.rs"));
    assert!(!invocation.required_inputs.contains(&response));
}

#[test]
fn response_file_arguments_are_not_recursively_expanded() {
    let directory = tempfile::tempdir().unwrap();
    let outer = directory.path().join("outer.args");
    let nested = directory.path().join("nested.args");
    std::fs::write(&nested, "src/wrong.rs\n").unwrap();
    std::fs::write(&outer, format!("@{}\n", nested.display())).unwrap();

    let expanded = expand_response_files(&[format!("@{}", outer.display()).into()]).unwrap();

    assert_eq!(
        expanded.arguments,
        [OsString::from(format!("@{}", nested.display()))]
    );
}

#[test]
fn shell_response_files_follow_the_rustc_unstable_switch() {
    let directory = tempfile::tempdir().unwrap();
    let response = directory.path().join("shell.args");
    std::fs::write(
        &response,
        "--crate-name 'shell widget' --crate-type=lib --emit=metadata,link src/lib.rs",
    )
    .unwrap();

    let invocation = RustcInvocation::parse(&[
        "-Zshell-argfiles".into(),
        format!("@shell:{}", response.display()).into(),
    ])
    .unwrap();

    assert_eq!(invocation.crate_name, "shell widget");
    assert!(!invocation.required_inputs.contains(&response));
}

#[test]
fn unreadable_response_files_bypass_with_the_stable_reason_kind() {
    let error = RustcInvocation::parse(&["@does-not-exist.args".into()]).unwrap_err();

    assert_eq!(error.kind(), "response-file");
    assert!(error.to_string().contains("does-not-exist.args"));
}

#[test]
fn equivalent_response_file_paths_share_an_action_key() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("lib.rs");
    let first_response = directory.path().join("rustc-123.args");
    let second_response = directory.path().join("rustc-456.args");
    std::fs::write(&source, "pub fn fixture() {}\n").unwrap();
    let lines = [
        "--crate-name=fixture",
        "--crate-type=lib",
        "--emit=metadata,link",
        source.to_str().unwrap(),
    ];
    let keyed = |response: &Path, separator: &str| {
        let contents = format!("{}{}", lines.join(separator), separator);
        std::fs::write(response, &contents).unwrap();
        let invocation =
            RustcInvocation::parse(&[format!("@{}", response.display()).into()]).unwrap();
        let mut action_context = context(&[]);
        action_context.working_dir = directory.path().to_path_buf();
        action_context.path_mappings = vec![PathMapping::new(directory.path(), "workspace")];
        action_context.inputs = vec![ActionInput {
            path: source.clone(),
            digest: CacheDigest::blake3_file(&source).unwrap(),
        }];
        invocation.action(action_context).unwrap().digest
    };

    assert_eq!(
        keyed(&first_response, "\n"),
        keyed(&second_response, "\r\n")
    );
}

#[test]
fn resolves_cargo_library_outputs() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        "-Cextra-filename=-abc123",
        "src/lib.rs",
    ]))
    .unwrap();
    assert_eq!(
        invocation.outputs(&working_dir).unwrap(),
        RustcOutputs {
            directory: working_dir.join("target/debug/deps"),
            files: vec![
                working_dir.join("target/debug/deps/libwidget-abc123.rlib"),
                working_dir.join("target/debug/deps/libwidget-abc123.rmeta"),
            ],
            dep_info: working_dir.join("target/debug/deps/widget-abc123.d"),
        }
    );
}

#[test]
fn resolves_a_compiler_linked_wasm_binary() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--out-dir=target/wasm32-unknown-unknown/debug/deps",
        "--target=wasm32-unknown-unknown",
        "-Cextra-filename=-abc123",
        "src/main.rs",
    ]))
    .unwrap();
    let executable =
        working_dir.join("target/wasm32-unknown-unknown/debug/deps/widget-abc123.wasm");

    assert_eq!(
        invocation.outputs(&working_dir).unwrap(),
        RustcOutputs {
            directory: working_dir.join("target/wasm32-unknown-unknown/debug/deps"),
            files: vec![executable],
            dep_info: working_dir.join("target/wasm32-unknown-unknown/debug/deps/widget-abc123.d"),
        }
    );
}

#[test]
fn accepts_wasm_tests_but_not_native_tests() {
    for target in COMPILER_BUNDLED_WASM_TARGETS {
        let wasm = args(&[
            "--test",
            "--emit=dep-info,link",
            &format!("--target={target}"),
            "src/lib.rs",
        ]);
        assert!(
            RustcInvocation::parse(&wasm).is_ok(),
            "{target} should use its compiler-bundled linker"
        );
        let cdylib = args(&[
            "--crate-type=cdylib",
            "--emit=dep-info,link",
            &format!("--target={target}"),
            "src/lib.rs",
        ]);
        assert!(RustcInvocation::parse(&cdylib).is_ok());
    }

    let implicit_binary = args(&[
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&implicit_binary),
        Err(BypassReason::UnsupportedCrateType("bin".into()))
    );

    let native = args(&["--test", "--emit=dep-info,link", "src/lib.rs"]);
    assert_eq!(
        RustcInvocation::parse(&native),
        Err(BypassReason::UnsupportedCrateType("test".into()))
    );
}

#[test]
fn rejects_webassembly_targets_that_require_external_toolchains() {
    for target in ["wasm32-unknown-emscripten", "wasm32-wali-linux-musl"] {
        let arguments = args(&[
            "--crate-type=bin",
            "--emit=dep-info,link",
            &format!("--target={target}"),
            "src/main.rs",
        ]);
        assert_eq!(
            RustcInvocation::parse(&arguments),
            Err(BypassReason::UnsupportedCrateType("bin".into()))
        );
    }
}

#[test]
fn custom_wasm_linker_modes_still_bypass() {
    let arguments = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "-Clink-self-contained=no",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&arguments),
        Err(BypassReason::UnknownCodegenOption(
            "link-self-contained".into()
        ))
    );

    let arguments = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "-Clinker=/tmp/custom-linker",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&arguments),
        Err(BypassReason::UnknownCodegenOption("linker".into()))
    );

    let arguments = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-wasip1",
        "-Ctarget-feature=-crt-static",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&arguments),
        Err(BypassReason::UnknownCodegenOption(
            "target-feature=-crt-static".into()
        ))
    );

    let self_contained = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-wasip1",
        "-Clink-self-contained=yes",
        "src/main.rs",
    ]);
    assert!(RustcInvocation::parse(&self_contained).is_ok());
}

#[test]
fn infers_a_valid_crate_name_from_a_hyphenated_source() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-type=lib",
        "--emit=dep-info,metadata",
        "my-library.rs",
    ]))
    .unwrap();

    assert_eq!(
        invocation.outputs(&working_dir).unwrap().dep_info,
        working_dir.join("my_library.d")
    );
}

#[test]
fn refuses_an_output_file_with_implicit_emit_paths() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "-o",
        "target/custom.rlib",
        "src/lib.rs",
    ]))
    .unwrap();

    // rustc applies -o to every emit that has no path of its own, so the
    // artifact names cannot be derived from the crate name.
    assert_eq!(
        invocation.outputs(&working_dir).unwrap_err(),
        BypassReason::ImplicitEmitWithOutputFile(working_dir.join("target/custom.rlib"))
    );
}

#[test]
fn resolves_an_output_file_when_every_emit_names_its_path() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info=target/widget.d,metadata=target/widget.rmeta,link=target/widget.rlib",
        "-o",
        "target/custom.rlib",
        "src/lib.rs",
    ]))
    .unwrap();

    assert_eq!(
        invocation.outputs(&working_dir).unwrap(),
        RustcOutputs {
            directory: working_dir.join("target"),
            files: vec![
                working_dir.join("target/widget.rlib"),
                working_dir.join("target/widget.rmeta"),
            ],
            dep_info: working_dir.join("target/widget.d"),
        }
    );
}

#[test]
fn dep_info_must_share_the_artifact_output_directory() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info=target/dep-info/widget.d,metadata,link",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]))
    .unwrap();

    assert_eq!(
        invocation.outputs(&working_dir),
        Err(BypassReason::SplitOutputDirectories)
    );
}

#[test]
fn equivalent_worktrees_produce_the_same_action_key() {
    let first_context = context(&[
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ]);
    let first = common_invocation().action(first_context).unwrap();
    let other = absolute(&["other", "checkout"]);
    let output = other.join("target/debug/deps");
    let invocation = RustcInvocation::parse(&[
        "--crate-name=widget".into(),
        "--edition=2024".into(),
        "src/lib.rs".into(),
        "--crate-type=lib".into(),
        "--emit=dep-info,metadata,link".into(),
        "-Cembed-bitcode=no".into(),
        "-Cmetadata=abc123".into(),
        format!("--out-dir={}", output.display()).into(),
        format!("-Ldependency={}", output.display()).into(),
        format!("--extern=serde={}", output.join("libserde.rlib").display()).into(),
        format!("--sysroot={}", sysroot().display()).into(),
        "--cap-lints=allow".into(),
    ])
    .unwrap();
    let mut second_context = context(&[]);
    second_context.working_dir = other.clone();
    second_context.path_mappings[0].root = other.join("target");
    second_context.path_mappings[1].root = other.clone();
    second_context.inputs = vec![
        ActionInput {
            path: "src/lib.rs".into(),
            digest: digest("source"),
        },
        ActionInput {
            path: "target/debug/deps/libserde.rlib".into(),
            digest: digest("serde"),
        },
    ];
    let second = invocation.action(second_context).unwrap();
    assert_eq!(first.digest, second.digest);
}

#[test]
fn predicts_inputs_without_reusing_stale_contents() {
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().canonicalize().unwrap();
    std::fs::create_dir(workspace.join("src")).unwrap();
    std::fs::write(workspace.join("src/lib.rs"), "pub fn value() -> u8 { 1 }").unwrap();
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]))
    .unwrap();
    let compiler = CompilerIdentity {
        toolchain: "stable".into(),
        rustc_version: "rustc test".into(),
        host: "test-host".into(),
        driver: None,
    };
    let context = ActionContext {
        compiler,
        working_dir: workspace.clone(),
        path_mappings: vec![PathMapping::new(&workspace, "workspace")],
        environment: BTreeMap::new(),
        portable_environment: BTreeSet::new(),
        inputs: Vec::new(),
    };
    let dep_info = RustcDepInfo {
        files: vec!["src/lib.rs".into()],
        environment: BTreeMap::new(),
    };
    let discovered = invocation.discover_inputs(&dep_info, &workspace).unwrap();
    let mut initial_context = context.clone();
    discovered.clone().apply_to(&mut initial_context).unwrap();
    let initial = invocation.action(initial_context).unwrap();
    let prediction = invocation.prediction(&context, &discovered).unwrap();
    assert_eq!(prediction.inputs, ["${workspace}/src/lib.rs"]);
    assert_eq!(prediction.compiler_duration_ns, 0);
    assert!(prediction.crate_name.is_empty());

    let predicted = prediction
        .discover(
            &workspace,
            &context.path_mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    let mut predicted_context = context.clone();
    predicted.apply_to(&mut predicted_context).unwrap();
    assert_eq!(invocation.action(predicted_context).unwrap(), initial);

    std::fs::write(workspace.join("src/lib.rs"), "pub fn value() -> u8 { 2 }").unwrap();
    let changed = prediction
        .discover(
            &workspace,
            &context.path_mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    let mut changed_context = context;
    changed.apply_to(&mut changed_context).unwrap();
    assert_ne!(
        invocation.action(changed_context).unwrap().digest,
        initial.digest
    );
}

#[test]
fn a_native_search_directory_is_predicted_by_name_not_by_its_contents() {
    // A C dependency leaves its whole object tree in the directory it asks
    // rustc to search: `aws-lc-sys` leaves thousands of files there. Naming
    // each one alongside the directory that already rediscovers them pushed
    // the serialized prediction past MAX_ACTION_PREDICTION_PAYLOAD, and the
    // agent rejected every prediction that crate recorded.
    let directory = tempfile::tempdir().unwrap();
    let workspace = directory.path().canonicalize().unwrap();
    let native = workspace.join("target/native");
    std::fs::create_dir_all(workspace.join("src")).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    std::fs::write(workspace.join("src/lib.rs"), "pub fn value() {}\n").unwrap();
    for index in 0..1_200 {
        // Object files a CMake build leaves behind carry paths this long.
        std::fs::write(native.join(format!("{index:0>230}.o")), "object").unwrap();
    }

    let native_argument = format!("-Lnative={}", native.display());
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &native_argument,
        "src/lib.rs",
    ]))
    .unwrap();
    let mappings = vec![
        PathMapping::new(workspace.join("target"), "target"),
        PathMapping::new(&workspace, "workspace"),
    ];
    let context = ActionContext {
        working_dir: workspace.clone(),
        path_mappings: mappings.clone(),
        ..context(&[])
    };
    let dep_info = RustcDepInfo {
        files: vec!["src/lib.rs".into()],
        environment: BTreeMap::new(),
    };
    let discovered = invocation
        .discover_inputs_with_mappings(
            &dep_info,
            &workspace,
            &mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    assert_eq!(discovered.inputs.len(), 1_201);

    let prediction = invocation.prediction(&context, &discovered).unwrap();
    // Counted rather than compared, so a regression reports how much of the
    // object tree leaked into the payload instead of printing all of it.
    assert_eq!(
        prediction
            .inputs
            .iter()
            .filter(|input| input.ends_with(".o"))
            .count(),
        0,
        "the directory stands for its contents"
    );
    assert_eq!(
        prediction.inputs,
        [
            "${workspace}/src/lib.rs",
            "@native-directory:${target}/native",
        ]
    );
    let payload = canonical_json(&prediction).unwrap();
    assert!(
        payload.len() <= tuist_cargo_cache_core::MAX_ACTION_PREDICTION_PAYLOAD,
        "a recordable prediction must fit the protocol payload limit, got {} bytes",
        payload.len()
    );

    // Dropping the covered inputs may not change the key the prediction
    // replays to, which is the whole point of recording one.
    let mut discovered_context = context.clone();
    discovered
        .clone()
        .apply_to(&mut discovered_context)
        .unwrap();
    let mut predicted_context = context.clone();
    prediction
        .discover(
            &workspace,
            &mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap()
        .apply_to(&mut predicted_context)
        .unwrap();
    assert_eq!(
        invocation.action(predicted_context).unwrap().digest,
        invocation.action(discovered_context).unwrap().digest
    );
}

#[test]
fn prediction_v1_is_unsupported() {
    let prediction: RustcInputPrediction =
        serde_json::from_str(r#"{"environment":[],"inputs":[],"version":1}"#).unwrap();
    assert_eq!(
        prediction
            .discover(
                Path::new("/work/one"),
                &[],
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .unwrap_err()
            .kind(),
        "unsupported-prediction"
    );
}

#[test]
fn compact_prediction_keeps_large_source_lists_recordable() {
    let inputs = (0..4_000)
        .map(|index| {
            format!(
                "${{workspace}}/src/commands/very_long_module_name_{index:0>5}/implementation.rs"
            )
        })
        .collect::<Vec<_>>();
    let prediction = RustcInputPrediction {
        version: 4,
        inputs,
        environment: vec!["OUT_DIR".into()],
        compiler_duration_ns: 42,
        crate_name: "mise".into(),
    };

    let mut uncompressed = prediction.clone();
    uncompressed.version = 3;
    let uncompressed_payload = canonical_json(&uncompressed).unwrap();
    assert!(
        uncompressed_payload.len() > tuist_cargo_cache_core::MAX_ACTION_PREDICTION_PAYLOAD,
        "the fixture must reproduce the old payload rejection"
    );
    let payload = canonical_json(&prediction).unwrap();
    assert!(
        payload.len() <= tuist_cargo_cache_core::MAX_ACTION_PREDICTION_PAYLOAD,
        "a compact prediction must fit the protocol payload limit, got {} bytes",
        payload.len()
    );
    assert!(
        payload.len() * 2 < uncompressed_payload.len(),
        "front coding should materially reduce a source-heavy prediction"
    );
    assert_eq!(
        serde_json::from_slice::<RustcInputPrediction>(&payload).unwrap(),
        prediction
    );
}

#[test]
fn rejects_noncanonical_compact_prediction_prefixes() {
    for payload in [
        r#"{"version":4,"inputs":["1:path"],"environment":[]}"#,
        r#"{"version":4,"inputs":["0:path","01:other"],"environment":[]}"#,
    ] {
        assert!(serde_json::from_str::<RustcInputPrediction>(payload).is_err());
    }
}

#[test]
fn predicted_mapping_root_round_trips() {
    let workspace = workspace();
    assert_eq!(
        denormalize_path("${workspace}", &[PathMapping::new(&workspace, "workspace")]).unwrap(),
        workspace
    );
}

#[test]
fn absolute_environment_values_remain_literal_action_inputs() {
    let invocation = common_invocation();
    let mut first_context = context(&[
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ]);
    let first_out_dir = workspace().join("target/debug/build/widget/out");
    first_context
        .environment
        .insert("OUT_DIR".into(), Some(first_out_dir.display().to_string()));
    let first = invocation.action(first_context).unwrap();

    let mut second_context = context(&[
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ]);
    second_context.environment.insert(
        "OUT_DIR".into(),
        Some(absolute(&["other", "out"]).display().to_string()),
    );
    let second = invocation.action(second_context).unwrap();

    // The descriptor is canonical JSON, so the value appears the way JSON writes it --
    // on Windows that means escaped separators. Quote it with the same serializer instead
    // of hand-rolling the escaping; that also pins the surrounding quotes, so this only
    // matches a whole JSON string rather than any substring.
    let descriptor = String::from_utf8(first.bytes).unwrap();
    let expected =
        String::from_utf8(canonical_json(&first_out_dir.display().to_string()).unwrap()).unwrap();
    assert!(descriptor.contains(&expected), "{descriptor}");
    assert_ne!(first.digest, second.digest);
}

/// The counterpart to the test above. Naming `OUT_DIR` portable normalizes
/// its value like any other path, which is what lets two checkouts agree on
/// a compilation that reads it. The caller earns the claim by remapping the
/// value inside the compilation and reading the outputs; the key only
/// records that it was made.
#[test]
fn portable_environment_values_normalize_across_checkouts() {
    let other = absolute(&["other", "checkout"]);
    let output = other.join("target/debug/deps");
    let relocated = RustcInvocation::parse(&[
        "--crate-name=widget".into(),
        "--edition=2024".into(),
        "src/lib.rs".into(),
        "--crate-type=lib".into(),
        "--emit=dep-info,metadata,link".into(),
        "-Cembed-bitcode=no".into(),
        "-Cmetadata=abc123".into(),
        format!("--out-dir={}", output.display()).into(),
        format!("-Ldependency={}", output.display()).into(),
        format!("--extern=serde={}", output.join("libserde.rlib").display()).into(),
        format!("--sysroot={}", sysroot().display()).into(),
        "--cap-lints=allow".into(),
    ])
    .unwrap();

    let here = |portable: bool| {
        let mut context = context(&[
            ("src/lib.rs", "source"),
            ("target/debug/deps/libserde.rlib", "serde"),
        ]);
        context.environment.insert(
            "OUT_DIR".into(),
            Some(
                workspace()
                    .join("target/debug/build/widget/out")
                    .display()
                    .to_string(),
            ),
        );
        if portable {
            context.portable_environment.insert("OUT_DIR".into());
        }
        common_invocation().action(context).unwrap().digest
    };
    let there = |portable: bool| {
        let mut context = context(&[]);
        context.working_dir = other.clone();
        context.path_mappings[0].root = other.join("target");
        context.path_mappings[1].root = other.clone();
        context.inputs = vec![
            ActionInput {
                path: "src/lib.rs".into(),
                digest: digest("source"),
            },
            ActionInput {
                path: "target/debug/deps/libserde.rlib".into(),
                digest: digest("serde"),
            },
        ];
        context.environment.insert(
            "OUT_DIR".into(),
            Some(
                other
                    .join("target/debug/build/widget/out")
                    .display()
                    .to_string(),
            ),
        );
        if portable {
            context.portable_environment.insert("OUT_DIR".into());
        }
        relocated.action(context).unwrap().digest
    };

    assert_ne!(here(false), there(false));
    assert_eq!(here(true), there(true));
    // A different key, not a relabelled one: an artifact compiled without
    // the remapping must never be restored under the portable key.
    assert_ne!(here(false), here(true));
}

#[test]
fn content_and_environment_change_the_action_key() {
    let invocation = common_invocation();
    let first = invocation
        .action(context(&[
            ("src/lib.rs", "source"),
            ("target/debug/deps/libserde.rlib", "serde"),
        ]))
        .unwrap();
    let changed_source = invocation
        .action(context(&[
            ("src/lib.rs", "changed"),
            ("target/debug/deps/libserde.rlib", "serde"),
        ]))
        .unwrap();
    let mut changed_environment = context(&[
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ]);
    changed_environment
        .environment
        .insert("CARGO_PKG_VERSION".into(), Some("2.0.0".into()));
    let changed_environment = invocation.action(changed_environment).unwrap();
    assert_ne!(first.digest, changed_source.digest);
    assert_ne!(first.digest, changed_environment.digest);
}

#[test]
fn unknown_and_incremental_options_bypass() {
    for (arguments, expected) in [
        (
            vec!["--future-flag", "src/lib.rs"],
            BypassReason::UnknownFlag("--future-flag".into()),
        ),
        (
            vec!["-Cfuture-option=yes", "src/lib.rs"],
            BypassReason::UnknownCodegenOption("future-option".into()),
        ),
        (
            vec!["-Cincremental=target/incremental", "src/lib.rs"],
            BypassReason::Incremental,
        ),
    ] {
        assert_eq!(RustcInvocation::parse(&args(&arguments)), Err(expected));
    }
}

#[test]
fn models_parallel_frontend_options_in_the_action_key() {
    let invocation = |parallelism: &[&str]| {
        let mut arguments = vec![
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
        ];
        arguments.extend_from_slice(parallelism);
        arguments.push("src/lib.rs");
        RustcInvocation::parse(&args(&arguments)).unwrap()
    };
    let key = |invocation: RustcInvocation| {
        invocation
            .action(context(&[("src/lib.rs", "source")]))
            .unwrap()
            .digest
    };

    let attached = invocation(&["-Zthreads=16"]);
    let separate = invocation(&["-Z", "threads=16"]);
    assert_eq!(attached, separate);
    assert_ne!(key(attached), key(invocation(&["-Zthreads=8"])));

    let cranelift = invocation(&["-Zcodegen-backend=cranelift"]);
    assert_eq!(cranelift, invocation(&["-Z", "codegen-backend=cranelift"]));
    assert_ne!(key(cranelift), key(invocation(&["-Zcodegen-backend=llvm"])));
    assert_ne!(
        key(invocation(&["-Zcodegen-backend=llvm"])),
        key(invocation(&[]))
    );
    for path in [
        "codegen-backend=/opt/librustc_codegen_custom.so",
        "codegen-backend=librustc_codegen_custom.dylib",
        "codegen-backend=",
    ] {
        assert_eq!(
            RustcInvocation::parse(&args(&[
                "--crate-name=widget",
                "--crate-type=lib",
                "--emit=dep-info,metadata,link",
                "-Z",
                path,
                "src/lib.rs",
            ])),
            Err(BypassReason::UnknownFlag(format!("-Z{path}")))
        );
    }
    assert_eq!(
        RustcInvocation::parse(&args(&[
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "-Zcodegen-backend=llvm",
            "--sysroot=/opt/sysroot",
            "src/lib.rs",
        ])),
        Err(BypassReason::UnknownFlag("-Zcodegen-backend=llvm".into()))
    );

    let jobs_frontend = invocation(&["-Zunstable-options", "--jobs-frontend=16"]);
    assert_ne!(key(separate), key(jobs_frontend));
    assert_eq!(
        invocation(&["-Zunstable-options", "--jobs-frontend", "16"]),
        invocation(&["-Zunstable-options", "--jobs-frontend=16"])
    );

    let synchronous_unwind = invocation(&["-Zuse-sync-unwind=yes"]);
    assert_eq!(
        synchronous_unwind,
        invocation(&["-Z", "use-sync-unwind=yes"])
    );
    assert_ne!(
        key(synchronous_unwind),
        key(invocation(&["-Zuse-sync-unwind=no"]))
    );
    assert_eq!(
        RustcInvocation::parse(&args(&["-Zuse-sync-unwind=true", "src/lib.rs"])),
        Err(BypassReason::UnknownFlag("-Zuse-sync-unwind=true".into()))
    );
}

#[test]
fn models_embedded_metadata_selection_in_the_action_key() {
    let invocation = |selection: &[&str]| {
        let mut arguments = vec![
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
        ];
        arguments.extend_from_slice(selection);
        arguments.push("src/lib.rs");
        RustcInvocation::parse(&args(&arguments)).unwrap()
    };
    let key = |invocation: RustcInvocation| {
        invocation
            .action(context(&[("src/lib.rs", "source")]))
            .unwrap()
            .digest
    };

    let disabled = invocation(&["-Zembed-metadata=no"]);
    assert_eq!(disabled, invocation(&["-Z", "embed-metadata=no"]));
    assert_ne!(key(disabled), key(invocation(&["-Zembed-metadata=yes"])));

    // Only the two documented spellings are admitted. Any other value keeps
    // bypassing, so a selection this adapter cannot describe never reaches a
    // key that claims to describe it.
    for value in ["off", "true", ""] {
        let flag = format!("-Zembed-metadata={value}");
        assert_eq!(
            RustcInvocation::parse(&args(&[&flag, "src/lib.rs"])),
            Err(BypassReason::UnknownFlag(flag.clone())),
            "{flag} should bypass"
        );
    }
}

/// Cargo's `-Zbuild-std` compiles `core`, `alloc`, `std` and their siblings
/// with `-Zforce-unstable-if-unmarked` and `RUSTC_BOOTSTRAP=1`. Both are
/// cacheable, and both stay in the key rather than being discarded.
#[test]
fn models_standard_library_units_in_the_action_key() {
    let invocation = |extra: &[&str]| {
        let mut arguments = vec![
            "--crate-name=core",
            "--edition=2024",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "--codegen=opt-level=3",
        ];
        arguments.extend_from_slice(extra);
        arguments.push("src/lib.rs");
        RustcInvocation::parse(&args(&arguments)).unwrap()
    };
    let key = |invocation: &RustcInvocation, bootstrap: Option<&str>| {
        let mut context = context(&[("src/lib.rs", "source")]);
        if let Some(value) = bootstrap {
            context
                .environment
                .insert("RUSTC_BOOTSTRAP".into(), Some(value.into()));
        }
        invocation.action(context).unwrap().digest
    };

    let std_unit = invocation(&["-Zforce-unstable-if-unmarked"]);
    assert_eq!(std_unit, invocation(&["-Z", "force-unstable-if-unmarked"]));
    let plain = invocation(&[]);
    assert_ne!(key(&std_unit, Some("1")), key(&plain, Some("1")));
    assert_ne!(key(&std_unit, Some("1")), key(&std_unit, None));
}

#[test]
fn parallel_frontend_options_require_values() {
    for arguments in [
        vec!["-Zthreads", "src/lib.rs"],
        vec!["-Zthreads=", "src/lib.rs"],
        vec!["--jobs-frontend=", "src/lib.rs"],
    ] {
        assert!(matches!(
            RustcInvocation::parse(&args(&arguments)),
            Err(BypassReason::MissingValue(_))
        ));
    }
}

#[test]
fn linked_and_unmodeled_outputs_bypass() {
    for (arguments, expected) in [
        (
            vec!["--crate-type=bin", "--emit=link", "src/main.rs"],
            BypassReason::UnsupportedCrateType("bin".into()),
        ),
        (
            vec!["--crate-type=lib", "--emit=obj", "src/lib.rs"],
            BypassReason::UnsupportedEmit("obj".into()),
        ),
        (
            vec!["--crate-type=lib", "--emit=dep-info", "src/lib.rs"],
            BypassReason::NoCacheableOutput,
        ),
    ] {
        assert_eq!(RustcInvocation::parse(&args(&arguments)), Err(expected));
    }
}

#[test]
fn action_requires_every_direct_input() {
    let error = common_invocation()
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap_err();
    assert_eq!(
        error,
        BypassReason::MissingRequiredInput("${target}/debug/deps/libserde.rlib".into())
    );
}

#[test]
fn action_rejects_unmapped_absolute_paths() {
    let unmapped = absolute(&["tmp", "rustc-output"]);
    let invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=link".into(),
        "src/lib.rs".into(),
        format!("--out-dir={}", unmapped.display()).into(),
    ])
    .unwrap();
    let error = invocation
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap_err();
    assert_eq!(error, BypassReason::UnmappedAbsolutePath(unmapped));
}

#[test]
fn custom_targets_are_required_inputs() {
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-type=lib",
        "--emit=metadata",
        "--target=targets/custom.json",
        "src/lib.rs",
    ]))
    .unwrap();
    assert_eq!(invocation.target(), Some("targets/custom.json"));
    let error = invocation
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap_err();
    assert_eq!(
        error,
        BypassReason::MissingRequiredInput("${workspace}/targets/custom.json".into())
    );
}

#[test]
fn remap_destinations_are_stable_virtual_paths() {
    let invocation = RustcInvocation::parse(&[
        "--crate-type=lib".into(),
        "--emit=metadata".into(),
        format!("--remap-path-prefix={}=/src", workspace().display()).into(),
        "src/lib.rs".into(),
    ])
    .unwrap();
    let action = invocation
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap();
    assert!(
        String::from_utf8(action.bytes)
            .unwrap()
            .contains(r#"--remap-path-prefix=${workspace}=/src"#)
    );
}

/// A dependency that was rebuilt changes an action key without anybody having
/// touched this crate, so churn detection cannot watch the key. What it watches
/// is this: the crate's own sources, and nothing it merely links against.
#[test]
fn a_rebuilt_dependency_does_not_move_the_source_fingerprint() {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path();
    let deps = working_dir.join("target/debug/deps");
    std::fs::create_dir_all(&deps).unwrap();
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    let rlib = deps.join("libserde.rlib");
    std::fs::write(&rlib, "serde").unwrap();
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &format!("--extern=serde={}", rlib.display()),
        "src.rs",
    ]))
    .unwrap();
    let dep_info = RustcDepInfo::parse("target/debug/deps/widget.d: src.rs\n").unwrap();
    let fingerprint = || {
        let discovered = invocation.discover_inputs(&dep_info, working_dir).unwrap();
        invocation.source_fingerprint(&discovered)
    };
    let before = fingerprint();

    // The linked artifact changed; this crate did not.
    std::fs::write(&rlib, "serde rebuilt").unwrap();
    assert_eq!(fingerprint(), before);

    // The crate itself changed.
    std::fs::write(working_dir.join("src.rs"), "pub fn value() -> u32 { 1 }\n").unwrap();
    assert_ne!(fingerprint(), before);
}

/// A native search directory is part of a shared key, and a directory the cache
/// cannot describe never gets one. Neither says anything about whether the
/// crate was edited, so the churn fingerprint must come out the same whether
/// discovery scanned the directory, refused it, or never looked.
#[cfg(unix)]
#[test]
fn native_search_directories_do_not_move_the_source_fingerprint() {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path().join("work");
    let native = directory.path().join("native");
    let elsewhere = directory.path().join("elsewhere");
    for path in [&working_dir, &native, &elsewhere] {
        std::fs::create_dir_all(path).unwrap();
    }
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    std::fs::write(native.join("generated.rs"), "// listed by dep-info\n").unwrap();
    std::fs::write(native.join("libfixture.a"), "first").unwrap();
    let argument = format!("-Lnative={}", native.display());
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &argument,
        "src.rs",
    ]))
    .unwrap();
    let dep_info = RustcDepInfo::parse(&format!(
        "target/debug/deps/widget.d: src.rs {}\n",
        native.join("generated.rs").display()
    ))
    .unwrap();
    let mappings = [PathMapping::new(&native, "native")];
    let scanned = || {
        invocation
            .discover_inputs_with_mappings(
                &dep_info,
                &working_dir,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .map(|discovered| invocation.source_fingerprint(&discovered))
    };
    let refused = || {
        invocation
            .discover_inputs_with_mappings(
                &dep_info,
                &working_dir,
                &[],
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .map(|discovered| invocation.source_fingerprint(&discovered))
    };
    let sources_only = || {
        invocation
            .discover_source_inputs(
                &dep_info,
                &working_dir,
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .map(|discovered| invocation.source_fingerprint(&discovered))
            .unwrap()
    };
    let before = sources_only();
    assert_eq!(scanned().unwrap(), before);

    // The directory outside every admitted root is refused, and a dangling
    // link in an admitted one cannot be read; the fingerprint is still defined.
    assert!(matches!(
        refused(),
        Err(BypassReason::UnsupportedSearchPath(_))
    ));
    std::os::unix::fs::symlink(elsewhere.join("missing"), native.join("libdangling.so")).unwrap();
    assert!(matches!(scanned(), Err(BypassReason::InputRead { .. })));
    assert_eq!(sources_only(), before);

    // A library appearing or changing in the directory is not an edit.
    std::fs::write(native.join("libfixture.a"), "rebuilt").unwrap();
    std::fs::write(native.join("libextra.a"), "new").unwrap();
    assert_eq!(sources_only(), before);

    // A file dep-info names is a source, wherever it lives.
    std::fs::write(native.join("generated.rs"), "// changed\n").unwrap();
    assert_ne!(sources_only(), before);
    std::fs::remove_file(native.join("libdangling.so")).unwrap();
    assert_eq!(scanned().unwrap(), sources_only());
}

/// A prediction omits what a native directory scan will find again, but not a
/// file dep-info names there. Rediscovery from it has to agree with discovery
/// from dep-info about which files are the crate's own sources.
#[test]
fn a_predicted_discovery_keeps_named_sources_beneath_a_native_directory() {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path().join("work");
    let native = directory.path().join("target/native");
    std::fs::create_dir_all(&working_dir).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    std::fs::write(native.join("generated.rs"), "// named by dep-info\n").unwrap();
    std::fs::write(native.join("libfixture.a"), "first").unwrap();
    let argument = format!("-Lnative={}", native.display());
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &argument,
        "src.rs",
    ]))
    .unwrap();
    let dep_info = RustcDepInfo::parse(&format!(
        "target/debug/deps/widget.d: src.rs {}\n",
        native.join("generated.rs").display()
    ))
    .unwrap();
    let mappings = vec![
        PathMapping::new(&working_dir, "workspace"),
        PathMapping::new(directory.path().join("target"), "target"),
    ];
    let discovered = invocation
        .discover_inputs_with_mappings(
            &dep_info,
            &working_dir,
            &mappings,
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
        .unwrap();
    let action_context = ActionContext {
        working_dir: working_dir.clone(),
        path_mappings: mappings.clone(),
        inputs: discovered.inputs.clone(),
        ..context(&[])
    };
    let prediction = invocation.prediction(&action_context, &discovered).unwrap();
    let predicted = || {
        let predicted = prediction
            .discover(
                &working_dir,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .unwrap();
        invocation.source_fingerprint(&predicted)
    };
    let before = invocation.source_fingerprint(&discovered);
    assert_eq!(predicted(), before);

    // A library appearing in the directory is not an edit; the named file is.
    std::fs::write(native.join("libextra.a"), "new").unwrap();
    assert_eq!(predicted(), before);
    std::fs::write(native.join("generated.rs"), "// changed\n").unwrap();
    assert_ne!(predicted(), before);
}

/// The crate root is a required input whether or not dep-info lists it. Having a
/// native search directory must not turn it, or anything else outside that
/// directory, into something an edit can go unnoticed in.
#[test]
fn a_required_source_outside_a_native_directory_still_moves_the_source_fingerprint() {
    let directory = tempfile::tempdir().unwrap();
    let working_dir = directory.path().join("work");
    let native = directory.path().join("target/native");
    std::fs::create_dir_all(&working_dir).unwrap();
    std::fs::create_dir_all(&native).unwrap();
    std::fs::write(working_dir.join("src.rs"), "pub fn value() {}\n").unwrap();
    std::fs::write(native.join("libfixture.a"), "archive").unwrap();
    let argument = format!("-Lnative={}", native.display());
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &argument,
        "src.rs",
    ]))
    .unwrap();
    // dep-info that leaves the root out: it still counts.
    std::fs::write(working_dir.join("other.rs"), "// listed\n").unwrap();
    let dep_info = RustcDepInfo::parse("target/debug/deps/widget.d: other.rs\n").unwrap();
    let mappings = vec![
        PathMapping::new(&working_dir, "workspace"),
        PathMapping::new(directory.path().join("target"), "target"),
    ];
    let discover = || {
        invocation
            .discover_inputs_with_mappings(
                &dep_info,
                &working_dir,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            )
            .unwrap()
    };
    let scanned = || invocation.source_fingerprint(&discover());
    let sources_only = || {
        invocation.source_fingerprint(
            &invocation
                .discover_source_inputs(
                    &dep_info,
                    &working_dir,
                    &tuist_cargo_cache_core::NoFileDigestCache,
                )
                .unwrap(),
        )
    };
    let discovered = discover();
    let action_context = ActionContext {
        working_dir: working_dir.clone(),
        path_mappings: mappings.clone(),
        inputs: discovered.inputs.clone(),
        ..context(&[])
    };
    let prediction = invocation.prediction(&action_context, &discovered).unwrap();
    let predicted = || {
        invocation.source_fingerprint(
            &prediction
                .discover(
                    &working_dir,
                    &mappings,
                    &tuist_cargo_cache_core::NoFileDigestCache,
                )
                .unwrap(),
        )
    };
    let before = scanned();
    assert_eq!(sources_only(), before);
    assert_eq!(predicted(), before);

    std::fs::write(native.join("libfixture.a"), "rebuilt").unwrap();
    assert_eq!(scanned(), before);
    assert_eq!(predicted(), before);

    std::fs::write(working_dir.join("src.rs"), "pub fn value() -> u32 { 1 }\n").unwrap();
    assert_ne!(scanned(), before);
    assert_ne!(sources_only(), before);
    assert_ne!(predicted(), before);
}

fn native_links() -> ParseOptions {
    ParseOptions::caching_native_links(true)
}

/// Off, a native link stays outside the cacheable tier exactly as before: the
/// option is what admits it, never the invocation alone.
#[test]
fn native_links_are_admitted_only_when_the_caller_models_them() {
    let test_binary = args(&["--test", "--emit=dep-info,link", "src/lib.rs"]);
    assert_eq!(
        RustcInvocation::parse(&test_binary),
        Err(BypassReason::UnsupportedCrateType("test".into()))
    );
    assert!(RustcInvocation::parse_with(&test_binary, native_links()).is_ok());

    let binary = args(&["--crate-type=bin", "--emit=dep-info,link", "src/main.rs"]);
    assert_eq!(
        RustcInvocation::parse(&binary),
        Err(BypassReason::UnsupportedCrateType("bin".into()))
    );
    assert!(RustcInvocation::parse_with(&binary, native_links()).is_ok());
}

/// A linked program has the host executable extension, and its executable bit
/// is part of what the cache promises to restore.
#[test]
fn a_native_program_uses_the_host_executable_name() {
    let working_dir = workspace();
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--test",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            "-Cextra-filename=-abc123",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();
    let name = if std::env::consts::EXE_EXTENSION.is_empty() {
        "widget-abc123".into()
    } else {
        format!("widget-abc123.{}", std::env::consts::EXE_EXTENSION)
    };
    let linked = working_dir.join("target/debug/deps").join(name);

    let outputs = invocation.outputs(&working_dir).unwrap();

    assert_eq!(outputs.files, vec![linked.clone()]);
    assert!(outputs.is_executable(&linked));
    assert!(invocation.links_natively());
}

#[cfg(windows)]
#[test]
fn a_debug_native_program_caches_its_pdb() {
    let working_dir = workspace();
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--test",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            "-Cdebuginfo=2",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();

    let outputs = invocation.outputs(&working_dir).unwrap();
    assert!(
        outputs
            .files
            .iter()
            .any(|path| path.extension().is_some_and(|ext| ext == "exe"))
    );
    assert!(
        outputs
            .files
            .iter()
            .any(|path| path.extension().is_some_and(|ext| ext == "pdb"))
    );
}

/// rustc without `--target` links for the host by construction, which is the
/// only linker this adapter can identify. Naming the host triple explicitly is
/// not the same statement, so it is not assumed to be one.
#[test]
fn an_explicit_target_is_never_a_native_link() {
    let arguments = args(&[
        "--test",
        "--emit=dep-info,link",
        "--target=x86_64-unknown-linux-gnu",
        "src/lib.rs",
    ]);

    assert_eq!(
        RustcInvocation::parse_with(&arguments, native_links()),
        Err(BypassReason::UnsupportedCrateType("test".into()))
    );
}

/// Everything here would either embed a path this checkout owns, depend on a
/// linker the key does not describe, or leave a file beside the binary that
/// tuist_cargo_cache does not store.
#[test]
fn unportable_native_links_still_bypass() {
    for (flag, expected) in [
        (
            "-Csplit-debuginfo=packed",
            BypassReason::UnportableNativeLink("split-debuginfo=packed".into()),
        ),
        (
            "-Crpath=yes",
            BypassReason::UnportableNativeLink("rpath=yes".into()),
        ),
        (
            "-Cprefer-dynamic=yes",
            BypassReason::UnportableNativeLink("prefer-dynamic=yes".into()),
        ),
        (
            "-Clink-self-contained=yes",
            BypassReason::UnportableNativeLink("link-self-contained=yes".into()),
        ),
        // Valueless is how cargo actually spells these, and rustc reads the
        // flag itself as the request.
        (
            "-Crpath",
            BypassReason::UnportableNativeLink("rpath".into()),
        ),
        (
            "-Cprefer-dynamic",
            BypassReason::UnportableNativeLink("prefer-dynamic".into()),
        ),
        (
            "-Clink-self-contained",
            BypassReason::UnportableNativeLink("link-self-contained".into()),
        ),
    ] {
        let arguments = args(&["--test", "--emit=dep-info,link", flag, "src/lib.rs"]);
        assert_eq!(
            RustcInvocation::parse_with(&arguments, native_links()),
            Err(expected),
            "{flag} should not be cacheable"
        );
    }

    let linker = args(&[
        "--test",
        "--emit=dep-info,link",
        "-Clinker=/usr/bin/false",
        "src/lib.rs",
    ]);
    assert!(RustcInvocation::parse_with(&linker, native_links()).is_ok());

    // Absent or affirmatively off is the default the compiler identity pins.
    for flag in ["-Csplit-debuginfo=off", "-Crpath=no", "-Cprefer-dynamic=no"] {
        let arguments = args(&["--test", "--emit=dep-info,link", flag, "src/lib.rs"]);
        assert!(
            RustcInvocation::parse_with(&arguments, native_links()).is_ok(),
            "{flag} should still be cacheable"
        );
    }
}

/// ld64 writes absolute object paths and their timestamps into the binary's
/// debug map, so the same source links to different bytes in another checkout.
#[cfg(target_os = "macos")]
#[test]
fn macos_debug_info_makes_a_native_link_unportable() {
    let arguments = args(&[
        "--test",
        "--emit=dep-info,link",
        "-Cdebuginfo=2",
        "src/lib.rs",
    ]);

    assert_eq!(
        RustcInvocation::parse_with(&arguments, native_links()),
        Err(BypassReason::UnportableNativeLink("debuginfo=2".into()))
    );

    // `-g` is the same request under another name.
    let shorthand = args(&["--test", "--emit=dep-info,link", "-g", "src/lib.rs"]);
    assert_eq!(
        RustcInvocation::parse_with(&shorthand, native_links()),
        Err(BypassReason::UnportableNativeLink("debuginfo=2".into()))
    );

    let none = args(&[
        "--test",
        "--emit=dep-info,link",
        "-Cdebuginfo=0",
        "src/lib.rs",
    ]);
    assert!(RustcInvocation::parse_with(&none, native_links()).is_ok());
}

/// A linked program hands its native libraries to the linker, whose search
/// is not modeled, so a `-l` of any kind still bypasses it -- even when the
/// archive itself would have resolved.
#[test]
fn native_libraries_bypass_admitted_native_links() {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join("libfixture.a"), "archive").unwrap();
    let search = format!("-Lnative={}", directory.path().display());
    for library in ["static=fixture", "dylib=z", "m"] {
        let arguments = args(&[
            "--test",
            "--emit=dep-info,link",
            &search,
            "-l",
            library,
            "src/lib.rs",
        ]);
        assert_eq!(
            RustcInvocation::parse_with(&arguments, native_links()),
            Err(BypassReason::NativeLibrary(library.into())),
            "{library}"
        );
    }
    assert_eq!(
        BypassReason::NativeLibrary("m".into()).kind(),
        "native-library"
    );
    assert_eq!(
        BypassReason::MissingNativeLibrary("static=fixture".into()).kind(),
        "missing-native-library"
    );
}

/// The linker field must be absent, not null, for everything that does not link
/// natively -- otherwise adding it would invalidate every key already in every
/// store, for a property those compilations never depended on.
#[test]
fn modeling_the_linker_leaves_existing_keys_untouched() {
    let invocation = common_invocation();
    let inputs = &[
        ("src/lib.rs", "source"),
        ("target/debug/deps/libserde.rlib", "serde"),
    ];

    let action = invocation.action(context(inputs)).unwrap();

    let json = String::from_utf8(action.bytes).unwrap();
    assert!(!json.contains("linker"), "{json}");
    // The digest this same invocation has on the branch this one came from.
    // What it guards is that modeling a linker did not move it; a change on
    // `main` moves it legitimately, and updating this line is then the point
    // at which someone confirms whose change it was.
    assert_eq!(
        action.digest.key(),
        "blake3/943ce7a1474e7e3aeb11e54fd513bfe7ef44fd5367f3a5486197b730c6f1e0d3/865"
    );
}

/// A native link keyed without one would claim the host does not matter.
#[test]
fn a_native_link_without_a_linker_identity_is_refused() {
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--test",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();

    assert_eq!(
        invocation.action(context(&[("src/lib.rs", "source")])),
        Err(BypassReason::UnportableNativeLink(
            "linker identity is unknown".into()
        ))
    );

    let action = invocation
        .action_linked_by(context(&[("src/lib.rs", "source")]), Some(test_linker()))
        .unwrap();
    let json = String::from_utf8(action.bytes).unwrap();
    assert!(json.contains(r#""linker":{"#), "{json}");
}

fn test_linker() -> LinkerIdentity {
    LinkerIdentity {
        driver: "/usr/bin/cc".into(),
        driver_version: "Apple clang version 17.0.0".into(),
        linker_version: "ld64-1200".into(),
        crt_objects: BTreeMap::new(),
        sdk: Some("MacOSX15.0.sdk (24A335)".into()),
        deployment_target: None,
    }
}

/// Two hosts whose linkers differ must key differently rather than share.
#[test]
fn the_linker_identity_changes_the_action_key() {
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--test",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();
    let keyed = |linker| {
        invocation
            .action_linked_by(context(&[("src/lib.rs", "source")]), Some(linker))
            .unwrap()
            .digest
    };

    assert_ne!(
        keyed(test_linker()),
        keyed(LinkerIdentity {
            driver_version: "Apple clang version 18.0.0".into(),
            ..test_linker()
        })
    );
}

/// Executability is read back off an output's name, so a program answering to
/// a library's name would come back without the permission that runs it.
#[test]
fn a_program_named_like_a_library_is_not_cacheable() {
    let arguments = args(&[
        "--crate-name=widget",
        "--test",
        "--emit=dep-info,link",
        "--out-dir=target/debug/deps",
        "-Cextra-filename=.rlib",
        "src/lib.rs",
    ]);
    let invocation = RustcInvocation::parse_with(&arguments, native_links()).unwrap();
    let mut ambiguous = workspace().join("target/debug/deps/widget.rlib");
    if !std::env::consts::EXE_EXTENSION.is_empty() {
        ambiguous.set_extension(format!("rlib.{}", std::env::consts::EXE_EXTENSION));
    }

    assert_eq!(
        invocation.outputs(&workspace()),
        Err(BypassReason::AmbiguousOutputName(ambiguous))
    );

    // A library by that name is exactly what it claims to be.
    let library = args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,link",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]);
    assert!(
        RustcInvocation::parse_with(&library, native_links())
            .unwrap()
            .outputs(&workspace())
            .is_ok()
    );
}

/// `cargo check --tests` asks for metadata and never links. Reading that as a
/// native link would send it looking for a linker identity and refusing flags
/// no linker ever saw.
#[test]
fn a_compilation_that_never_links_is_not_a_link() {
    let checked = args(&[
        "--crate-name=widget",
        "--test",
        "--emit=dep-info,metadata",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]);

    // Whatever this is, it is not something a linker has an opinion about, so
    // the answer is the one it gets with the option off.
    assert_eq!(
        RustcInvocation::parse_with(&checked, native_links()),
        RustcInvocation::parse(&checked)
    );

    // And a flag that would make a *link* unportable says nothing here.
    let with_debug = args(&[
        "--crate-name=widget",
        "--test",
        "--emit=dep-info,metadata",
        "--out-dir=target/debug/deps",
        "-Cdebuginfo=2",
        "src/lib.rs",
    ]);
    assert!(
        RustcInvocation::parse_with(&with_debug, native_links()).is_ok(),
        "a debug-info flag no linker reads must not bypass a check compilation"
    );
    assert!(RustcInvocation::parse(&with_debug).is_ok());
}

/// `cargo check` and clippy compile every binary target this way. rustc names
/// the metadata `lib<name>.rmeta` whatever the crate type, so there is nothing
/// here an rlib's metadata emit does not already do.
#[test]
fn a_binary_that_only_emits_metadata_is_cached_like_a_library() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--crate-type=bin",
        "--emit=dep-info,metadata",
        "--out-dir=target/debug/deps",
        "-Cextra-filename=-abc123",
        "src/main.rs",
    ]))
    .unwrap();

    assert!(!invocation.links_natively());
    let outputs = invocation.outputs(&working_dir).unwrap();
    assert_eq!(
        outputs.files,
        vec![working_dir.join("target/debug/deps/libwidget-abc123.rmeta")]
    );
    assert_eq!(
        outputs.dep_info,
        working_dir.join("target/debug/deps/widget-abc123.d")
    );
}

/// A test target carries `--test` and no crate type at all, and cargo omits
/// the extra filename for a unit that needs no disambiguating.
#[test]
fn a_test_target_that_only_emits_metadata_is_cached_like_a_library() {
    let working_dir = absolute(&["workspace"]);
    let invocation = RustcInvocation::parse(&args(&[
        "--crate-name=widget",
        "--test",
        "--emit=dep-info,metadata",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]))
    .unwrap();

    assert!(!invocation.links_natively());
    let outputs = invocation.outputs(&working_dir).unwrap();
    assert_eq!(
        outputs.files,
        vec![working_dir.join("target/debug/deps/libwidget.rmeta")]
    );
}

/// The crate type describes what a *link* would produce, and nothing links
/// here, so none of them is a reason to refuse.
#[test]
fn every_crate_type_is_cached_when_nothing_links() {
    for crate_type in ["bin", "cdylib", "dylib", "staticlib", "proc-macro", "lib"] {
        let parsed = RustcInvocation::parse(&args(&[
            "--crate-name=widget",
            &format!("--crate-type={crate_type}"),
            "--emit=dep-info,metadata",
            "--out-dir=target/debug/deps",
            "src/lib.rs",
        ]));
        assert!(parsed.is_ok(), "{crate_type} was refused: {parsed:?}");
    }
}

/// The widening is about what links, not about what is named: an artifact that
/// really is linked stays outside the tier exactly as it was.
#[test]
fn linked_artifacts_still_bypass_when_nothing_admits_them() {
    assert_eq!(
        RustcInvocation::parse(&args(&[
            "--crate-name=widget",
            "--crate-type=bin",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            "src/main.rs",
        ])),
        Err(BypassReason::UnsupportedCrateType("bin".into()))
    );
}

#[test]
fn linked_proc_macro_uses_the_native_link_tier() {
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--crate-type=proc-macro",
            "--emit=dep-info,metadata,link",
            "--out-dir=target/debug/deps",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();

    assert!(invocation.links_natively());
    assert_eq!(
        invocation.outputs(&absolute(&["workspace"])).unwrap().files,
        [
            absolute(&[
                "workspace",
                "target",
                "debug",
                "deps",
                &format!(
                    "{}widget{}",
                    std::env::consts::DLL_PREFIX,
                    std::env::consts::DLL_SUFFIX
                ),
            ]),
            absolute(&["workspace", "target", "debug", "deps", "libwidget.rmeta"]),
        ]
        .into_iter()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
    );
}

/// An ELF shared object records neither its own path nor a second file beside
/// it, so a host `cdylib` on Linux caches like a proc macro. A Mach-O dylib
/// names its output path as its install name and a Windows DLL leaves an
/// import library behind, so elsewhere it still bypasses.
#[test]
fn linked_cdylib_uses_the_native_link_tier_on_linux() {
    let arguments = args(&[
        "--crate-name=widget",
        "--crate-type=cdylib",
        "--emit=dep-info,link",
        "--out-dir=target/debug/deps",
        "src/lib.rs",
    ]);
    let parsed = RustcInvocation::parse_with(&arguments, native_links());
    if !cfg!(target_os = "linux") {
        assert_eq!(
            parsed,
            Err(BypassReason::UnsupportedCrateType("cdylib".into()))
        );
        return;
    }
    let invocation = parsed.unwrap();
    assert!(invocation.links_natively());
    assert_eq!(
        invocation.outputs(&absolute(&["workspace"])).unwrap().files,
        [absolute(&[
            "workspace",
            "target",
            "debug",
            "deps",
            "libwidget.so"
        ])]
    );
    // A cross-compiled cdylib is linked by a toolchain the linker identity
    // does not describe.
    let mut cross = arguments.clone();
    cross.insert(0, "--target=aarch64-unknown-linux-gnu".into());
    assert_eq!(
        RustcInvocation::parse_with(&cross, native_links()),
        Err(BypassReason::UnsupportedCrateType("cdylib".into()))
    );
    // Only when the caller can describe the linker.
    assert_eq!(
        RustcInvocation::parse(&arguments),
        Err(BypassReason::UnsupportedCrateType("cdylib".into()))
    );
}

#[test]
fn proc_macro_prefer_dynamic_is_pinned_by_the_compiler_identity() {
    let invocation = RustcInvocation::parse_with(
        &args(&[
            "--crate-name=widget",
            "--crate-type=proc-macro",
            "--emit=dep-info,metadata,link",
            "--codegen=prefer-dynamic",
            "--out-dir=target/debug/deps",
            "src/lib.rs",
        ]),
        native_links(),
    )
    .unwrap();

    assert!(invocation.links_natively());
}

/// A check compilation of a test target links nothing, so its native
/// libraries are inputs rather than linker arguments: the static archive is
/// hashed, and a missing one bypasses rather than being guessed at.
#[test]
fn a_check_compilation_hashes_its_static_library() {
    let directory = tempfile::tempdir().unwrap();
    let native = directory.path().join("out");
    std::fs::create_dir_all(&native).unwrap();
    let search = format!("-Lnative={}", native.display());
    let check = args(&[
        "--crate-name=widget",
        "--test",
        "--emit=dep-info,metadata",
        "--out-dir=target/debug/deps",
        &search,
        "-lstatic=fixture",
        "src/lib.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&check),
        Err(BypassReason::MissingNativeLibrary("static=fixture".into()))
    );
    std::fs::write(native.join("libfixture.a"), "archive").unwrap();
    let invocation = RustcInvocation::parse(&check).unwrap();
    assert!(
        invocation
            .required_inputs_in(directory.path())
            .contains(&native.join("libfixture.a"))
    );
}

/// A `rustflags` entry in `.cargo/config.toml` reaches every compilation the
/// target has, and nearly all of them build an rlib or an rmeta. Refusing the
/// option outright is what left mise's Windows CI bypassing 1092 of its 1109
/// compilations over a stack size only the linker would ever read.
#[test]
fn a_library_keeps_compiling_with_a_link_argument_it_never_uses() {
    let library = |flag: &str| {
        args(&[
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "--out-dir=target/debug/deps",
            flag,
            "src/lib.rs",
        ])
    };
    let RustcAction { digest, bytes } =
        RustcInvocation::parse(&library("-Clink-arg=/STACK:8000000"))
            .unwrap()
            .action(context(&[("src/lib.rs", "source")]))
            .unwrap();
    let json = String::from_utf8(bytes).unwrap();
    assert!(
        json.contains(r#""--codegen=link-arg=/STACK:8000000""#),
        "the link argument belongs in the key: {json}"
    );

    // Inert here, but still keyed: the descriptor says what the command line
    // said, and an argument dropped from it would have to be one this adapter
    // can prove no output ever depends on.
    let smaller_stack = RustcInvocation::parse(&library("-Clink-arg=/STACK:4000000"))
        .unwrap()
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap();
    assert_ne!(digest, smaller_stack.digest);

    // The plural spelling and a separated value are the same option.
    for arguments in [
        library("-Clink-args=-Wl,-z,now"),
        args(&[
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata",
            "--out-dir=target/debug/deps",
            "-C",
            "link-arg=/STACK:8000000",
            "src/lib.rs",
        ]),
    ] {
        assert!(
            RustcInvocation::parse(&arguments).is_ok(),
            "{arguments:?} should be cacheable"
        );
    }
}

/// Nothing in a link argument says whether it names a file, and the key never
/// hashes one. `-Tlink.x` is a linker script found off the search path,
/// `-fuse-ld=lld` replaces the linker the key describes, and both look exactly
/// like the stack size that is safe to key.
#[test]
fn link_arguments_bypass_whatever_actually_links() {
    for flag in ["-Clink-arg=--import-memory", "-Clink-args=-Tlink.x"] {
        let wasm = args(&[
            "--crate-type=bin",
            "--emit=dep-info,link",
            "--target=wasm32-unknown-unknown",
            flag,
            "src/main.rs",
        ]);
        assert_eq!(
            RustcInvocation::parse(&wasm),
            Err(BypassReason::UnmodeledLinkArgument(
                flag.strip_prefix("-C").unwrap().into()
            )),
            "{flag} should not be cacheable on a wasm link"
        );
    }

    // A native link refuses what it cannot tell from a file name. A stack
    // size is the exception on MSVC; see the test for it below.
    let flag = "-Clink-arg=/DEF:exports.def";
    let native = args(&["--test", "--emit=dep-info,link", flag, "src/lib.rs"]);
    assert_eq!(
        RustcInvocation::parse_with(&native, native_links()),
        Err(BypassReason::UnmodeledLinkArgument(
            flag.strip_prefix("-C").unwrap().into()
        )),
        "{flag} should not be cacheable on a native link"
    );
}

/// A `rustflags` entry of `-C link-arg=/STACK:8000000` reaches every proc
/// macro, build script, and binary a Windows workspace builds. Treated as
/// unmodeled it bypassed all of them, and since a MSVC link stamps the PE
/// header and PDB with a time and a GUID, every rebuilt proc-macro DLL hashed
/// differently from the last one and every crate compiled against it missed
/// as well: about 175 of mise's 1100 compilations never became hits.
#[test]
fn msvc_stack_and_reproducibility_options_are_keyed_on_a_native_link() {
    let link = |crate_type: &str, flag: &str| {
        args(&[
            "--crate-name=widget",
            crate_type,
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            flag,
            "src/lib.rs",
        ])
    };
    for flag in [
        "-Clink-arg=/STACK:8000000",
        "-Clink-arg=/Brepro",
        "-Clink-args=/STACK:8000000 /Brepro",
    ] {
        let parsed =
            RustcInvocation::parse_with(&link("--crate-type=proc-macro", flag), native_links());
        if !cfg!(target_env = "msvc") {
            // Another host hands this to a linker that reads it as a file.
            assert_eq!(
                parsed,
                Err(BypassReason::UnmodeledLinkArgument(
                    flag.strip_prefix("-C").unwrap().into()
                )),
                "{flag} must still bypass off MSVC"
            );
            continue;
        }
        assert!(
            parsed.unwrap().links_natively(),
            "{flag} should be cacheable"
        );
    }

    // Nothing else an MSVC linker accepts is modeled, whatever the output
    // linked.
    let msvc = cfg!(target_env = "msvc");
    for flag in [
        "-Clink-arg=/DEF:exports.def",
        "-Clink-arg=/STACK:8000000,x",
        "-Clink-arg=/LIBPATH:C:\\libs",
        "-Clink-arg=/Brepro:yes",
        "-Clink-args=/STACK:8000000 /DEF:exports.def",
        "-Clink-args=",
        "-Clink-arg=exports.def",
    ] {
        let parsed = RustcInvocation::parse_with(&link("--crate-type=bin", flag), native_links());
        assert!(
            matches!(parsed, Err(BypassReason::UnmodeledLinkArgument(_))),
            "{flag} should bypass (msvc: {msvc})"
        );
    }
}

/// The grammar behind that: a number after `/STACK:` and `/Brepro`, with the
/// case and the `-` spelling the linker itself accepts.
#[test]
fn msvc_link_option_grammar_is_closed() {
    for modeled in [
        "/STACK:8000000",
        "/stack:8000000,4096",
        "-STACK:0x800000",
        "/Brepro",
        "/BREPRO",
        "-brepro",
    ] {
        assert!(msvc_option_reads_no_file(modeled), "{modeled}");
    }
    for refused in [
        "",
        "/",
        "STACK:8000000",
        "/STACK",
        "/STACK:",
        "/STACK:,",
        "/STACK:1,2,3",
        "/STACK:0x",
        "/STACK:12ab",
        "/STACK:8000000 /Brepro",
        "/STACK:C:\\file",
        "/Brepro:NO",
        "/DEBUG",
        "/OUT:foo.exe",
        "@response.rsp",
    ] {
        assert!(!msvc_option_reads_no_file(refused), "{refused}");
    }
}

/// `-z` keywords that only set a flag in the ELF output read no file, so a
/// native Linux link keeps them in its key as text. Any other spelling, or a
/// keyword outside the list, still bypasses.
#[test]
fn elf_keywords_are_keyed_on_a_native_linux_link() {
    let link = |flag: &str| {
        args(&[
            "--crate-name=widget",
            "--crate-type=cdylib",
            "--emit=dep-info,link",
            "--out-dir=target/debug/deps",
            flag,
            "src/lib.rs",
        ])
    };
    let parsed = RustcInvocation::parse_with(&link("-Clink-arg=-Wl,-z,nodelete"), native_links());
    if !cfg!(target_os = "linux") {
        assert!(parsed.is_err());
        return;
    }
    let invocation = parsed.unwrap();
    assert!(invocation.links_natively());
    for flag in [
        "-Clink-arg=-Wl,-z,muldefs",
        "-Clink-arg=-Wl,-z,nodelete,-T,link.x",
        "-Clink-args=-Wl,-z,nodelete",
        "-Clink-arg=-znodelete",
    ] {
        assert_eq!(
            RustcInvocation::parse_with(&link(flag), native_links()),
            Err(BypassReason::UnmodeledLinkArgument(
                flag.strip_prefix("-C").unwrap().into()
            )),
            "{flag} should not be cacheable"
        );
    }
    // A cross-compiled link is not native, so the keyword is not modeled.
    let mut cross = link("-Clink-arg=-Wl,-z,nodelete");
    cross.insert(0, "--target=wasm32-unknown-unknown".into());
    assert_eq!(
        RustcInvocation::parse_with(&cross, native_links()),
        Err(BypassReason::UnmodeledLinkArgument(
            "link-arg=-Wl,-z,nodelete".into()
        ))
    );
}

/// `-fuse-ld=<name>` is the one link argument beyond `-oso_prefix` the
/// adapter models: on a native link the linker identity probe resolves and
/// pins the selected linker, so the link caches. On any other link output the
/// selection has no identity describing it, so it bypasses like every other
/// link argument. A conflicting second selection names no single linker and
/// bypasses too.
#[test]
fn fuse_ld_is_modeled_for_native_links_only() {
    let native = args(&[
        "--test",
        "--emit=dep-info,link",
        "-Clink-arg=-fuse-ld=mold",
        "src/lib.rs",
    ]);
    let invocation = RustcInvocation::parse_with(&native, native_links())
        .expect("a `-fuse-ld` selection on a native link is cacheable");
    assert_eq!(invocation.fuse_ld(), Some("mold"));

    let wasm = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "-Clink-arg=-fuse-ld=mold",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&wasm),
        Err(BypassReason::UnmodeledLinkArgument(
            "link-arg=-fuse-ld=mold".into()
        )),
        "a `-fuse-ld` selection should not be cacheable on a wasm link"
    );

    let conflicting = args(&[
        "--test",
        "--emit=dep-info,link",
        "-Clink-arg=-fuse-ld=mold",
        "-Clink-arg=-fuse-ld=lld",
        "src/lib.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse_with(&conflicting, native_links()),
        Err(BypassReason::UnmodeledLinkArgument(
            "link-arg=-fuse-ld=lld".into()
        )),
        "conflicting `-fuse-ld` selections name no single linker"
    );

    let library = args(&[
        "--crate-type=rlib",
        "--emit=dep-info,metadata",
        "-Clink-arg=-fuse-ld=mold",
        "src/lib.rs",
    ]);
    let invocation = RustcInvocation::parse(&library)
        .expect("a `-fuse-ld` selection is inert where nothing links");
    assert_eq!(invocation.fuse_ld(), Some("mold"));
}

/// The first link argument the adapter modeled: ld64's `-oso_prefix` names a
/// checkout-specific path, so its value normalizes like every other path in
/// the key instead of pinning the key to one checkout's spelling.
#[test]
fn an_oso_prefix_normalizes_into_the_key() {
    let workspace_prefix = format!(
        "-Clink-arg=-Wl,-oso_prefix,{}/",
        workspace().to_str().unwrap()
    );
    let library = args(&[
        "--crate-name=widget",
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "--out-dir=target/debug/deps",
        &workspace_prefix,
        "src/lib.rs",
    ]);
    let RustcAction { bytes, .. } = RustcInvocation::parse(&library)
        .unwrap()
        .action(context(&[("src/lib.rs", "source")]))
        .unwrap();
    let json = String::from_utf8(bytes).unwrap();
    assert!(
        json.contains(r#""--codegen=link-arg=-Wl,-oso_prefix,${workspace}/""#),
        "the prefix must enter the key by its placeholder: {json}"
    );
}

/// ld64 is the only linker that reads `-oso_prefix`, so anywhere but a native
/// link the option stays what every other link argument is: unmodeled.
#[test]
fn an_oso_prefix_is_unmodeled_where_ld64_never_links() {
    let wasm = args(&[
        "--crate-type=bin",
        "--emit=dep-info,link",
        "--target=wasm32-unknown-unknown",
        "-Clink-arg=-Wl,-oso_prefix,/work/project/",
        "src/main.rs",
    ]);
    assert_eq!(
        RustcInvocation::parse(&wasm),
        Err(BypassReason::UnmodeledLinkArgument(
            "link-arg=-Wl,-oso_prefix".into()
        )),
    );
}

/// On macOS the debug map is what makes a debug-info link unportable, and a
/// prefix covering the output directory is what strips the debug map back to
/// spellings every checkout shares.
#[cfg(target_os = "macos")]
#[test]
fn a_covering_oso_prefix_makes_a_debug_link_portable() {
    let binary = |extra: &[&str]| {
        let mut all = vec![
            "--crate-name=widget",
            "--crate-type=bin",
            "--emit=dep-info,link",
            "-Cdebuginfo=2",
        ];
        all.extend_from_slice(extra);
        all.extend_from_slice(&["src/main.rs"]);
        args(&all)
    };
    let out_dir = format!(
        "--out-dir={}",
        workspace().join("target/debug/deps").display()
    );
    let covering = format!(
        "-Clink-arg=-Wl,-oso_prefix,{}/",
        workspace().to_str().unwrap()
    );
    let elsewhere = "-Clink-arg=-Wl,-oso_prefix,/somewhere/else/";

    // Without a prefix the debug map pins the checkout, as before.
    assert_eq!(
        RustcInvocation::parse_with(&binary(&[&out_dir]), native_links()),
        Err(BypassReason::UnportableNativeLink("debuginfo=2".into())),
    );
    // A prefix covering the output directory lifts exactly that.
    assert!(RustcInvocation::parse_with(&binary(&[&out_dir, &covering]), native_links()).is_ok());
    // One covering something else does not.
    assert_eq!(
        RustcInvocation::parse_with(&binary(&[&out_dir, elsewhere]), native_links()),
        Err(BypassReason::UnportableNativeLink("debuginfo=2".into())),
    );
    // And a relative output directory pins nothing a prefix could cover.
    assert_eq!(
        RustcInvocation::parse_with(
            &binary(&["--out-dir=target/debug/deps", &covering]),
            native_links()
        ),
        Err(BypassReason::UnportableNativeLink("debuginfo=2".into())),
    );
}

/// Cargo passes `-C linker-plugin-lto` to every dependency of a build whose
/// profile turns LTO on, so bypassing it left such builds without a cache for
/// anything but the workspace. The switch is keyed; a plugin path is a host
/// file the key does not describe and still bypasses.
#[test]
fn linker_plugin_lto_is_keyed_and_a_plugin_path_bypasses() {
    let plain = RustcInvocation::parse(&args(&[
        "--crate-type=lib",
        "--emit=dep-info,metadata,link",
        "-Cembed-bitcode=yes",
        "src/lib.rs",
    ]))
    .unwrap();
    for flag in ["-Clinker-plugin-lto", "-Clinker-plugin-lto=yes"] {
        let with_lto = RustcInvocation::parse(&args(&[
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "-Cembed-bitcode=yes",
            flag,
            "src/lib.rs",
        ]))
        .unwrap();
        assert_ne!(
            with_lto.arguments, plain.arguments,
            "{flag} is part of the key"
        );
        assert!(
            with_lto
                .arguments
                .contains(&Argument::Plain(format!("--codegen={}", &flag[2..]))),
            "{flag} is keyed as text"
        );
    }

    assert_eq!(
        RustcInvocation::parse(&args(&[
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "-Clinker-plugin-lto=/usr/lib/LLVMgold.so",
            "src/lib.rs",
        ])),
        Err(BypassReason::UnknownCodegenOption(
            "linker-plugin-lto=/usr/lib/LLVMgold.so".into()
        ))
    );
}

#[test]
fn install_names_are_only_modeled_for_macos_proc_macros() {
    for kind in ["bin", "rlib", "proc-macro"] {
        let parsed = RustcInvocation::parse_with(
            &args(&[
                "--crate-name=widget",
                &format!("--crate-type={kind}"),
                "--emit=dep-info,link",
                "--out-dir=target/debug/deps",
                "-Clink-arg=-Wl,-install_name,@rpath/libwidget.dylib",
                "src/lib.rs",
            ]),
            ParseOptions::caching_native_links(true),
        );
        assert_eq!(
            parsed.is_ok(),
            cfg!(target_os = "macos") && kind == "proc-macro"
        );
    }
}

#[cfg(target_os = "macos")]
#[test]
fn portable_proc_macro_install_name_is_keyed_and_preserves_explicit_names() {
    let mut arguments = args(&[
        "--crate-name=widget",
        "--crate-type=proc-macro",
        "--emit=dep-info,link",
        "--out-dir=target/debug/deps",
        "-Cextra-filename=-abc123",
        "src/lib.rs",
    ]);
    let options = ParseOptions::caching_native_links(true);
    let original = RustcInvocation::parse_with(&arguments, options).unwrap();
    let context = context(&[("src/lib.rs", "source")]);
    let outputs = original.outputs(&context.working_dir).unwrap();
    let flag = original.portable_install_name(&outputs).unwrap();
    assert_eq!(
        flag,
        "-Clink-arg=-Wl,-install_name,@rpath/libwidget-abc123.dylib"
    );
    arguments.push(flag.into());
    let portable = RustcInvocation::parse_with(&arguments, options).unwrap();
    assert_ne!(
        original.invocation_digest(&context).unwrap(),
        portable.invocation_digest(&context).unwrap()
    );
    assert_eq!(portable.portable_install_name(&outputs), None);
    arguments.pop();
    arguments.push("-Clink-arg=-Wl,-install_name,@rpath/custom.dylib".into());
    let explicit = RustcInvocation::parse_with(&arguments, options).unwrap();
    assert_eq!(explicit.portable_install_name(&outputs), None);
    let command = explicit.dep_info_command(&outputs.dep_info).unwrap();
    assert!(command.arguments().contains(&OsString::from(
        "--codegen=link-arg=-Wl,-install_name,@rpath/custom.dylib"
    )));
    for value in [
        "/absolute/custom.dylib",
        "@rpath/libwidget.dylib,-dead_strip",
        "@rpath/../custom.dylib",
    ] {
        arguments.pop();
        arguments.push(format!("-Clink-arg=-Wl,-install_name,{value}").into());
        assert!(RustcInvocation::parse_with(&arguments, options).is_err());
    }
}

#[test]
fn a_build_script_is_recognized_by_its_crate_name() {
    let outputs = |name: &str| RustcOutputs {
        directory: PathBuf::from("/t/debug/build/pkg-1"),
        files: vec![PathBuf::from("/t/debug/build/pkg-1").join(name)],
        dep_info: PathBuf::from("/t/debug/build/pkg-1").join(format!("{name}.d")),
    };

    assert!(
        outputs("build_script_build-1")
            .build_script_executable("build_script_build")
            .is_some()
    );
    assert!(
        outputs("build_script_main-1")
            .build_script_executable("build_script_main")
            .is_some()
    );
    assert!(
        outputs("mylib-1")
            .build_script_executable("mylib")
            .is_none()
    );
    assert!(!is_build_script_crate_name("build_script_"));
}
