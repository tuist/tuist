use super::*;

/// Bypass kinds are the grouping keys in build statistics, `tuist_cargo_cache explain`, and
/// the bypass log. Renaming one silently reclassifies historical output, so the
/// strings are pinned here and the payloads deliberately vary.
#[test]
fn bypass_kinds_are_stable_and_field_independent() {
    let cases: Vec<(CcBypassReason, &str)> = vec![
        (
            CcBypassReason::NonUtf8Argument { index: 3 },
            "non-utf8-argument",
        ),
        (CcBypassReason::ResponseFile("args".into()), "response-file"),
        (
            CcBypassReason::UnknownFlag("-fmagic".into()),
            "unknown-flag",
        ),
        (CcBypassReason::MissingValue("-o".into()), "missing-value"),
        (CcBypassReason::CompilerQuery, "compiler-query"),
        (CcBypassReason::NotACompile, "not-a-compile"),
        (
            CcBypassReason::NonObjectOutput("-E".into()),
            "non-object-output",
        ),
        (CcBypassReason::StandardInput, "standard-input"),
        (CcBypassReason::MissingInput, "missing-input"),
        (CcBypassReason::MultipleInputs, "multiple-inputs"),
        (CcBypassReason::MissingOutput, "missing-output"),
        (
            CcBypassReason::UnsupportedLanguage("a.S".into()),
            "unsupported-language",
        ),
        (
            CcBypassReason::CallerDependencyFlags("-MMD".into()),
            "caller-dependency-flags",
        ),
        (
            CcBypassReason::PrecompiledHeader("-include-pch".into()),
            "precompiled-header",
        ),
        (
            CcBypassReason::CoverageInstrumentation("--coverage".into()),
            "coverage-instrumentation",
        ),
        (
            CcBypassReason::SplitDebugOutput("-gsplit-dwarf".into()),
            "split-debug-output",
        ),
        (
            CcBypassReason::SaveTemps("-save-temps".into()),
            "save-temps",
        ),
        (
            CcBypassReason::ToolPassthrough("-Xclang".into()),
            "tool-passthrough",
        ),
        (CcBypassReason::Plugin("-fplugin=x".into()), "plugin"),
        (
            CcBypassReason::SearchPathModifiedDuringCompilation("/w/inc".into()),
            "search-path-modified-during-compilation",
        ),
        (
            CcBypassReason::LocalCpuTarget("-march=native".into()),
            "local-cpu-target",
        ),
        (
            CcBypassReason::UnsupportedCompilerDriver("cl.exe".into()),
            "unsupported-compiler-driver",
        ),
        (
            CcBypassReason::CompilerIdentityUnavailable("probe failed".into()),
            "compiler-identity-unavailable",
        ),
        (
            CcBypassReason::UnsupportedEnvironment("CPATH".into()),
            "unsupported-environment",
        ),
        (
            CcBypassReason::RealCompilerUnpinned,
            "real-compiler-unpinned",
        ),
        (
            CcBypassReason::EmbeddedTimestampMacro("/w/a.c".into()),
            "embedded-timestamp-macro",
        ),
        (
            CcBypassReason::AssemblerInputDirective("/w/a.S".into()),
            "assembler-input-directive",
        ),
        (
            CcBypassReason::MalformedDepfile("no rule".into()),
            "malformed-depfile",
        ),
        (
            CcBypassReason::DepfileRead {
                path: "/w/a.d".into(),
                message: "gone".into(),
            },
            "depfile-read",
        ),
        (CcBypassReason::TooManyInputs, "too-many-inputs"),
        (
            CcBypassReason::UnmappedAbsolutePath("/opt/x".into()),
            "unmapped-absolute-path",
        ),
        (CcBypassReason::NonUtf8Path("/w/a".into()), "non-utf8-path"),
        (
            CcBypassReason::RelativeWorkingDirectory("w".into()),
            "relative-working-directory",
        ),
        (
            CcBypassReason::RelativePathMapping("w".into()),
            "relative-path-mapping",
        ),
        (
            CcBypassReason::InvalidPathPlaceholder("bad name".into()),
            "invalid-path-placeholder",
        ),
        (
            CcBypassReason::MissingRequiredInput("${workspace}/a.c".into()),
            "missing-required-input",
        ),
        (
            CcBypassReason::InvalidInputDigest("/w/a.c".into()),
            "invalid-input-digest",
        ),
        (
            CcBypassReason::ConflictingInput("${workspace}/a.c".into()),
            "conflicting-input",
        ),
        (
            CcBypassReason::InputRead {
                path: "/w/a.c".into(),
                message: "gone".into(),
            },
            "input-read",
        ),
        (
            CcBypassReason::InputChanged("/w/a.c".into()),
            "input-changed",
        ),
        (
            CcBypassReason::InputModifiedDuringCompilation("/w/a.c".into()),
            "input-modified-during-compilation",
        ),
        (
            CcBypassReason::DiscoveryWorkingDirectory,
            "discovery-working-directory",
        ),
        (
            CcBypassReason::UnsupportedPrediction,
            "unsupported-prediction",
        ),
        (
            CcBypassReason::InvalidPredictedInput("../x".into()),
            "invalid-predicted-input",
        ),
        (
            CcBypassReason::Serialization("bad json".into()),
            "serialization",
        ),
    ];
    for (reason, kind) in cases {
        assert_eq!(reason.kind(), kind, "kind changed for {reason:?}");
    }
}

#[test]
fn actionable_bypasses_carry_remediation() {
    let remediation = CcBypassReason::UnsupportedEnvironment("CPATH".into())
        .remediation()
        .unwrap();
    assert!(remediation.contains("Unset"));
    let remediation = CcBypassReason::ToolPassthrough("-Wa,--reads-input".into())
        .remediation()
        .unwrap();
    assert!(remediation.contains("If you control the build script"));
    assert!(CcBypassReason::CompilerQuery.remediation().is_none());
}

fn argv(values: &[&str]) -> Vec<OsString> {
    values.iter().map(OsString::from).collect()
}

/// Build an absolute path that is absolute on this platform, since a key that
/// rejects relative roots would otherwise reject every fixture on Windows.
fn absolute(segments: &[&str]) -> PathBuf {
    let mut path = if cfg!(windows) {
        PathBuf::from(r"C:\")
    } else {
        PathBuf::from("/")
    };
    path.extend(segments);
    path
}

fn text(path: &Path) -> String {
    path.to_str().expect("fixture paths are UTF-8").to_string()
}

fn typical() -> Vec<OsString> {
    argv(&[
        "-O2",
        "-ffunction-sections",
        "-fdata-sections",
        "-fPIC",
        "-gdwarf-4",
        "-I",
        "/work/target/debug/build/zstd-sys-1234/out",
        "-Ilib/zstd",
        "-DZSTD_MULTITHREAD=1",
        "-Wall",
        "-Wextra",
        "-std=c11",
        "-o",
        "/work/target/debug/build/zstd-sys-1234/out/entropy.o",
        "-c",
        "lib/zstd/entropy.c",
    ])
}

#[test]
fn parses_a_typical_cc_crate_invocation() {
    let invocation = CcInvocation::parse(&typical()).expect("invocation should be admitted");
    assert_eq!(invocation.source(), Path::new("lib/zstd/entropy.c"));
    assert_eq!(
        invocation.output(),
        Path::new("/work/target/debug/build/zstd-sys-1234/out/entropy.o")
    );
    assert_eq!(invocation.language(), CcLanguage::C);
    assert_eq!(
        invocation.include_dirs(),
        [
            PathBuf::from("/work/target/debug/build/zstd-sys-1234/out"),
            PathBuf::from("lib/zstd"),
        ]
    );
    assert_eq!(
        invocation.required_inputs(),
        [PathBuf::from("lib/zstd/entropy.c")]
    );
}

#[test]
fn linking_without_dash_c_is_not_a_compile() {
    let arguments = argv(&["-o", "app", "main.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "not-a-compile"
    );
}

#[test]
fn assembly_modes_bypass_as_non_object_output() {
    let arguments = argv(&["-S", "-o", "out", "main.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "non-object-output"
    );
}

/// `-M` and `-MM` stop after preprocessing, `-MG` changes what a missing
/// header means, and a list modifier with no `-MD` or `-MMD` to modify is not
/// a shape any build produces: all of those still bypass.
#[test]
fn dependency_flags_that_are_not_a_compile_with_a_list_bypass() {
    for arguments in [
        vec!["-M", "-c", "-o", "a.o", "a.c"],
        vec!["-MM", "-c", "-o", "a.o", "a.c"],
        vec!["-MD", "-MG", "-c", "-o", "a.o", "a.c"],
        vec!["-MP", "-c", "-o", "a.o", "a.c"],
        vec!["-MF", "a.d", "-c", "-o", "a.o", "a.c"],
        vec!["-MT", "a.o", "-c", "-o", "a.o", "a.c"],
    ] {
        assert_eq!(
            CcInvocation::parse(&argv(&arguments)).unwrap_err().kind(),
            "caller-dependency-flags",
            "{arguments:?} should bypass"
        );
    }
}

/// A caller asking for a dependency list beside the object -- OpenSSL's
/// makefiles, CMake -- gets one from the shim. The flags shape that list and
/// nothing else, so they are neither key material nor passed to the driver,
/// which honors only one `-MF` and owes the shim its own.
#[test]
fn caller_dependency_lists_are_taken_from_the_flags_and_kept_out_of_the_key() {
    let plain = CcInvocation::parse(&argv(&["-O2", "-c", "-o", "out/a.o", "a.c"])).unwrap();
    assert_eq!(plain.caller_depfile(), None);

    let arguments = argv(&[
        "-O2",
        "-MMD",
        "-MF",
        "out/a.o.d",
        "-MT",
        "a.o",
        "-MQ",
        "$(OBJ)",
        "-MP",
        "-c",
        "-o",
        "out/a.o",
        "a.c",
    ]);
    let listed = CcInvocation::parse(&arguments).unwrap();
    let caller = listed.caller_depfile().expect("a list was asked for");
    assert_eq!(caller.path, PathBuf::from("out/a.o.d"));
    assert_eq!(
        caller.targets,
        vec![
            DepfileTarget {
                name: "a.o".into(),
                quoted: false
            },
            DepfileTarget {
                name: "$(OBJ)".into(),
                quoted: true
            },
        ]
    );
    assert!(caller.user_headers_only);
    assert!(caller.phony_targets);
    assert_eq!(
        listed.arguments, plain.arguments,
        "the list flags are not key material"
    );
    assert_eq!(
        listed.compiler_arguments(&arguments),
        argv(&["-O2", "-c", "-o", "out/a.o", "a.c"]),
        "the driver runs without the list flags"
    );

    // `-MD` alone: the driver would write `<object>.d` naming the object.
    let defaulted = CcInvocation::parse(&argv(&["-MD", "-c", "-o", "out/a.o", "a.c"])).unwrap();
    let caller = defaulted.caller_depfile().unwrap();
    assert_eq!(caller.path, PathBuf::from("out/a.d"));
    assert_eq!(
        caller.targets,
        vec![DepfileTarget {
            name: "out/a.o".into(),
            quoted: true
        }]
    );
    assert!(!caller.user_headers_only);
    assert!(!caller.phony_targets);

    // Attached spellings, as CMake writes them.
    let attached = CcInvocation::parse(&argv(&[
        "-MMD",
        "-MFout/b.d",
        "-MTb.o",
        "-c",
        "-o",
        "b.o",
        "a.c",
    ]))
    .unwrap();
    let caller = attached.caller_depfile().unwrap();
    assert_eq!(caller.path, PathBuf::from("out/b.d"));
    assert_eq!(caller.targets[0].name, "b.o");
}

#[test]
fn repeated_output_flags_follow_the_driver_and_the_last_one_wins() {
    let arguments = argv(&["-c", "-o", "first.o", "-o", "second.o", "a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("invocation should be admitted");
    assert_eq!(invocation.output(), Path::new("second.o"));
    let keyed = invocation
        .arguments
        .iter()
        .filter(|argument| matches!(argument, Argument::Path { flag, .. } if flag == "-o"))
        .count();
    assert_eq!(keyed, 2, "both outputs must enter the key");
}

#[test]
fn unlisted_f_and_m_flags_bypass_with_the_flag_text() {
    for flag in ["-fmagic", "-mmagic"] {
        let arguments = argv(&[flag, "-c", "-o", "a.o", "a.c"]);
        let reason = CcInvocation::parse(&arguments).unwrap_err();
        assert_eq!(reason.kind(), "unknown-flag");
        assert!(reason.to_string().contains(flag), "{reason}");
    }
}

#[test]
fn tool_passthrough_flags_bypass_even_with_admitted_prefixes() {
    for flag in [
        "-Wl,-z,now",
        "-Wa,--defsym,version=1",
        "-Wp,-D_FORTIFY_SOURCE=2",
    ] {
        let arguments = argv(&[flag, "-c", "-o", "a.o", "a.c"]);
        assert_eq!(
            CcInvocation::parse(&arguments).unwrap_err().kind(),
            "tool-passthrough",
            "{flag} should bypass"
        );
    }
    let arguments = argv(&["-Xclang", "-ffake", "-c", "-o", "a.o", "a.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "tool-passthrough"
    );
    let arguments = argv(&["-mllvm", "-inline-threshold=0", "-c", "-o", "a.o", "a.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "tool-passthrough"
    );
}

#[test]
fn no_input_assembler_options_stay_admitted_key_material() {
    let flag = "-Wa,--noexecstack";
    let arguments = argv(&[flag, "-c", "-o", "a.o", "a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("option should be admitted");
    assert!(invocation.arguments.contains(&Argument::Plain(flag.into())));
}

#[test]
fn plain_warning_flags_stay_admitted_key_material() {
    let arguments = argv(&["-Wall", "-Werror", "-Wno-unused", "-c", "-o", "a.o", "a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("warnings should be admitted");
    assert!(
        invocation
            .arguments
            .contains(&Argument::Plain("-Werror".into()))
    );
}

#[test]
fn plain_assembly_and_objective_c_sources_bypass_as_unsupported_languages() {
    for source in ["a.s", "a.m", "a.mm", "a.C", "a.rs"] {
        let arguments = argv(&["-c", "-o", "a.o", source]);
        assert_eq!(
            CcInvocation::parse(&arguments).unwrap_err().kind(),
            "unsupported-language",
            "{source} should bypass"
        );
    }
}

#[test]
fn dash_x_overrides_source_extension_detection() {
    let arguments = argv(&["-x", "c++", "-c", "-o", "a.o", "a.inl"]);
    let invocation = CcInvocation::parse(&arguments).expect("explicit language should be admitted");
    assert_eq!(invocation.language(), CcLanguage::Cxx);

    let arguments = argv(&["-x", "assembler", "-c", "-o", "a.o", "a.s"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "unsupported-language"
    );
}

#[test]
fn response_file_arguments_bypass_with_the_stable_reason_kind() {
    let arguments = argv(&["@args.rsp"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "response-file"
    );
}

#[test]
fn apple_arch_flags_are_admitted_key_material() {
    let arguments = argv(&[
        "-arch", "arm64", "-arch", "x86_64", "-c", "-o", "a.o", "a.c",
    ]);
    let invocation = CcInvocation::parse(&arguments).expect("arch flags should be admitted");
    assert!(
        invocation
            .arguments
            .contains(&Argument::Plain("-arch=arm64".into()))
    );
    assert!(
        invocation
            .arguments
            .contains(&Argument::Plain("-arch=x86_64".into()))
    );
}

#[test]
fn multiple_sources_and_missing_pieces_bypass() {
    let arguments = argv(&["-c", "-o", "a.o", "a.c", "b.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "multiple-inputs"
    );
    let arguments = argv(&["-c", "-o", "a.o"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "missing-input"
    );
    let arguments = argv(&["-c", "a.c"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "missing-output"
    );
    let arguments = argv(&["-c", "-o", "a.o", "-"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "standard-input"
    );
}

#[test]
fn driver_queries_bypass_rather_than_compiling() {
    for flag in ["-v", "--version", "-dumpmachine", "-print-search-dirs"] {
        let arguments = argv(&[flag]);
        assert_eq!(
            CcInvocation::parse(&arguments).unwrap_err().kind(),
            "compiler-query",
            "{flag} should bypass"
        );
    }
}

fn identity() -> CcCompilerIdentity {
    CcCompilerIdentity {
        family: CcCompilerFamily::Clang,
        version_text: "clang version 17.0.6\nTarget: aarch64-apple-darwin\n".into(),
        target: "aarch64-apple-darwin".into(),
        assembler: String::new(),
    }
}

fn context(workspace: &Path, target: &Path) -> CcActionContext {
    CcActionContext {
        compiler: identity(),
        working_dir: workspace.to_path_buf(),
        path_mappings: vec![
            PathMapping::new(target, "target"),
            PathMapping::new(workspace, "workspace"),
        ],
        environment: BTreeMap::new(),
        inputs: Vec::new(),
    }
}

/// A checkout and the target directory inside it.
fn checkout(name: &str) -> (PathBuf, PathBuf) {
    let workspace = absolute(&["work", name]);
    let target = workspace.join("target");
    (workspace, target)
}

fn digest_of(value: &str) -> CacheDigest {
    CacheDigest::blake3(value.as_bytes())
}

#[test]
fn equivalent_worktrees_produce_the_same_portable_action_key() {
    let build = |name: &str| {
        let (workspace, target) = checkout(name);
        let arguments = argv(&["-O2", "-c", "-o", "out.o", "src/a.c"]);
        let invocation = CcInvocation::parse(&arguments).expect("admitted");
        let mut context = context(&workspace, &target);
        context.inputs = vec![
            CcActionInput {
                path: workspace.join("src/a.c"),
                digest: digest_of("source"),
            },
            CcActionInput {
                path: workspace.join("src/a.h"),
                digest: digest_of("header"),
            },
        ];
        invocation.action(context).expect("action").digest
    };
    assert_eq!(build("one"), build("two"));
}

#[test]
fn path_specific_actions_bind_checkout_target_and_source_spelling() {
    let build = |checkout_name: &str, target_name: &str, source: &str, bound: bool| {
        let (workspace, _) = checkout(checkout_name);
        let invocation = CcInvocation::parse(&argv(&["-c", "-o", "out.o", source])).unwrap();
        let mut context = context(&workspace, &workspace.join(target_name));
        context.inputs.push(CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        });
        invocation
            .action_with_path_binding(context, bound)
            .unwrap()
            .digest
    };
    let portable = build("one", "target", "src/a.c", false);
    assert_eq!(portable, build("two", "other-target", "./src/a.c", false));
    let bound = build("one", "target", "src/a.c", true);
    assert_ne!(bound, portable);
    assert_eq!(bound, build("one", "target", "src/a.c", true));
    assert_ne!(bound, build("two", "target", "src/a.c", true));
    assert_ne!(bound, build("one", "other-target", "src/a.c", true));
    assert_ne!(bound, build("one", "target", "./src/a.c", true));
}

#[cfg(unix)]
#[test]
fn action_path_aliases_are_equivalent_and_refreshed_between_actions() {
    let directory = tempfile::tempdir().unwrap();
    let root = std::fs::canonicalize(directory.path()).unwrap();
    for name in ["one", "two"] {
        std::fs::create_dir_all(root.join(name).join("src")).unwrap();
        std::fs::write(root.join(name).join("src/a.c"), "int a;").unwrap();
    }
    let alias = root.join("alias");
    std::os::unix::fs::symlink(root.join("one"), &alias).unwrap();
    let build = |source: &str| {
        let invocation = CcInvocation::parse(&argv(&["-c", "-o", "out.o", source])).unwrap();
        let mut context = context(&root, &root.join("target"));
        context.inputs.push(CcActionInput {
            path: root.join(source),
            digest: digest_of("int a;"),
        });
        invocation.action(context).unwrap().digest
    };
    let first = build("alias/src/a.c");
    assert_eq!(first, build("one/src/a.c"));
    std::fs::remove_file(&alias).unwrap();
    std::os::unix::fs::symlink(root.join("two"), &alias).unwrap();
    let second = build("alias/src/a.c");
    assert_eq!(second, build("two/src/a.c"));
    assert_ne!(first, second);
}

#[test]
fn registry_sources_normalize_under_the_cargo_home_placeholder() {
    // Cargo runs a registry crate's build script with its cwd inside the
    // registry checkout, which is nowhere near the user's workspace.
    let (workspace, target) = checkout("one");
    let cargo_home = absolute(&["home", "u", ".cargo"]);
    let package = cargo_home.join("registry/src/index/zstd-sys-2.0");
    let arguments = argv(&["-c", "-o", "out.o", "zstd.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    let mut context = context(&workspace, &target);
    context.working_dir = package.clone();
    context
        .path_mappings
        .push(PathMapping::new(cargo_home, "cargo_home"));
    context.inputs = vec![CcActionInput {
        path: package.join("zstd.c"),
        digest: digest_of("source"),
    }];
    let action = invocation.action(context).expect("action");
    let descriptor = String::from_utf8(action.bytes).expect("utf-8");
    assert!(
        descriptor.contains("${cargo_home}/registry/src/index/zstd-sys-2.0/zstd.c"),
        "{descriptor}"
    );
}

/// The system roots are POSIX paths, and the shims are only installed on unix.
#[cfg(unix)]
#[test]
fn system_headers_are_keyed_verbatim_under_admitted_roots() {
    let (workspace, target) = checkout("one");
    let arguments = argv(&["-c", "-o", "out.o", "src/a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    let mut context = context(&workspace, &target);
    context.inputs = vec![
        CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        },
        CcActionInput {
            path: PathBuf::from("/usr/include/stdio.h"),
            digest: digest_of("stdio"),
        },
    ];
    let action = invocation.action(context).expect("action");
    let descriptor = String::from_utf8(action.bytes).expect("utf-8");
    assert!(descriptor.contains("/usr/include/stdio.h"), "{descriptor}");
}

#[cfg(unix)]
#[test]
fn unmapped_absolute_include_paths_bypass() {
    let (workspace, target) = checkout("one");
    let arguments = argv(&["-I/opt/homebrew/include", "-c", "-o", "out.o", "src/a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    let mut context = context(&workspace, &target);
    context.inputs = vec![CcActionInput {
        path: workspace.join("src/a.c"),
        digest: digest_of("source"),
    }];
    assert_eq!(
        invocation.action(context).unwrap_err().kind(),
        "unmapped-absolute-path"
    );
}

#[test]
fn a_missing_required_input_is_not_publishable() {
    let (workspace, target) = checkout("one");
    let arguments = argv(&["-c", "-o", "out.o", "src/a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    let context = context(&workspace, &target);
    assert_eq!(
        invocation.action(context).unwrap_err().kind(),
        "missing-required-input"
    );
}

#[test]
fn include_path_environment_variables_bypass_when_set() {
    for name in BYPASS_ENVIRONMENT {
        let reason = environment_inputs(
            |candidate| (candidate == *name).then(|| "/opt/include".to_string()),
            None,
        )
        .unwrap_err();
        assert_eq!(reason.kind(), "unsupported-environment");
        assert!(reason.to_string().contains(name), "{reason}");
    }
}

#[test]
fn deployment_target_and_sdkroot_enter_the_key_verbatim() {
    let environment = environment_inputs(
        |name| match name {
            "MACOSX_DEPLOYMENT_TARGET" => Some("11.0".into()),
            "SDKROOT" => Some("/sdk".into()),
            _ => None,
        },
        None,
    )
    .expect("environment should be admitted");
    assert_eq!(
        environment.get("MACOSX_DEPLOYMENT_TARGET"),
        Some(&Some("11.0".to_string()))
    );
    assert_eq!(environment.get("SDKROOT"), Some(&Some("/sdk".to_string())));
    // Unset variables are still recorded, so setting one later is a miss
    // rather than an unnoticed change.
    assert_eq!(environment.get("SOURCE_DATE_EPOCH"), Some(&None));
}

#[test]
fn an_explicit_sysroot_argument_replaces_the_sdkroot_variable_in_the_key() {
    let environment = environment_inputs(
        |name| (name == "SDKROOT").then(|| "/sdk".into()),
        Some(Path::new("/other")),
    )
    .expect("environment should be admitted");
    assert!(!environment.contains_key("SDKROOT"));
}

#[test]
fn compiler_families_classify_from_probe_text() {
    assert_eq!(
        CcCompilerFamily::classify("Apple clang version 15.0.0 (clang-1500.3.9.4)").unwrap(),
        CcCompilerFamily::AppleClang
    );
    assert_eq!(
        CcCompilerFamily::classify("clang version 17.0.6").unwrap(),
        CcCompilerFamily::Clang
    );
    assert_eq!(
        CcCompilerFamily::classify("gcc version 13.2.0 (Debian 13.2.0-1)").unwrap(),
        CcCompilerFamily::Gcc
    );
}

#[cfg(windows)]
#[test]
fn msvc_style_probe_output_selects_the_msvc_adapter() {
    let probe = "Microsoft (R) C/C++ Optimizing Compiler Version 19.38\n";
    assert_eq!(
        CcCompilerFamily::classify(probe).unwrap(),
        CcCompilerFamily::Msvc
    );
}

#[test]
fn only_gcc_carries_an_external_assembler_in_its_identity() {
    assert!(CcCompilerFamily::Gcc.uses_external_assembler());
    assert!(!CcCompilerFamily::Clang.uses_external_assembler());
    assert!(!CcCompilerFamily::AppleClang.uses_external_assembler());
    #[cfg(windows)]
    assert!(!CcCompilerFamily::Msvc.uses_external_assembler());
}

#[test]
fn parses_a_typical_msvc_cc_crate_invocation() {
    let arguments = argv(&[
        "/nologo",
        "/MD",
        "/Z7",
        "/Brepro",
        "/Iinclude",
        "/D",
        "FEATURE=1",
        "/Foout\\widget.obj",
        "/c",
        "src\\widget.c",
    ]);
    let invocation =
        CcInvocation::parse_msvc(&arguments).expect("MSVC invocation should be admitted");
    assert_eq!(invocation.source(), Path::new("src\\widget.c"));
    assert_eq!(invocation.output(), Path::new("out\\widget.obj"));
    assert_eq!(invocation.include_dirs(), [PathBuf::from("include")]);
    assert_eq!(invocation.language(), CcLanguage::C);
    assert_eq!(
        invocation.msvc_dependency_arguments(Path::new("deps.json")),
        argv(&["/sourceDependencies", "deps.json"])
    );
}

#[test]
fn msvc_processor_and_floating_point_flags_are_admitted() {
    for flag in ["/favor:AMD64", "/fp:precise", "/fp:fast"] {
        let arguments = argv(&[flag, "/Foout.obj", "/c", "a.c"]);
        CcInvocation::parse_msvc(&arguments)
            .unwrap_or_else(|reason| panic!("{flag} should be admitted: {reason}"));
    }
}

#[test]
fn msvc_unmodeled_outputs_and_dependency_flags_bypass() {
    for flag in [
        "/showIncludes",
        "/sourceDependencies",
        "/Faassembly.asm",
        "/Fpheader.pch",
        "/Zi",
        "/Fdcompile.pdb",
    ] {
        let arguments = argv(&[flag, "/Foout.obj", "/c", "a.c"]);
        assert!(
            CcInvocation::parse_msvc(&arguments).is_err(),
            "{flag} should bypass"
        );
    }
}

#[test]
fn the_assembler_identity_changes_the_action_key() {
    let build = |assembler: &str| {
        let (workspace, target) = checkout("one");
        let arguments = argv(&["-c", "-o", "out.o", "src/a.c"]);
        let invocation = CcInvocation::parse(&arguments).expect("admitted");
        let mut context = context(&workspace, &target);
        context.compiler.family = CcCompilerFamily::Gcc;
        context.compiler.assembler = assembler.into();
        context.inputs = vec![CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        }];
        invocation.action(context).expect("action").digest
    };
    assert_ne!(
        build("/usr/bin/as; GNU assembler 2.40"),
        build("/usr/bin/as; GNU assembler 2.42"),
    );
}

#[test]
fn predictions_round_trip_through_normalized_names() {
    let (workspace, target) = checkout("one");
    let arguments = argv(&["-c", "-o", "out.o", "src/a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    let mut context = context(&workspace, &target);
    context.inputs = vec![
        CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        },
        CcActionInput {
            path: PathBuf::from(format!(
                "{INCLUDE_MANIFEST_PREFIX}{}",
                text(&workspace.join("src"))
            )),
            digest: digest_of("manifest"),
        },
    ];
    let prediction = invocation.prediction(&context, 42).expect("prediction");
    assert_eq!(prediction.version, 1);
    assert_eq!(prediction.compiler_duration_ns, 42);
    assert_eq!(prediction.source_name, "a.c");
    assert!(
        prediction
            .inputs
            .contains(&"${workspace}/src/a.c".to_string())
    );
    assert!(
        prediction
            .inputs
            .contains(&format!("{INCLUDE_MANIFEST_PREFIX}${{workspace}}/src"))
    );
}

#[cfg(unix)]
#[test]
fn predicted_system_paths_only_denormalize_under_admitted_roots() {
    let mappings = PathMapping::ordered(&[PathMapping::new("/work/one", "workspace")]);
    assert_eq!(
        denormalize_path("${workspace}/src/a.c", &mappings).unwrap(),
        PathBuf::from("/work/one/src/a.c")
    );
    assert_eq!(
        denormalize_path("/usr/include/stdio.h", &mappings).unwrap(),
        PathBuf::from("/usr/include/stdio.h")
    );
    for hostile in ["/etc/passwd", "${workspace}/../escape", "relative/path"] {
        assert_eq!(
            denormalize_path(hostile, &mappings).unwrap_err().kind(),
            "invalid-predicted-input",
            "{hostile} should not resolve"
        );
    }
}

#[test]
fn a_prediction_from_a_future_schema_bypasses() {
    let prediction = CcInputPrediction {
        path_specific: false,
        version: 2,
        inputs: Vec::new(),
        environment: Vec::new(),
        compiler_duration_ns: 0,
        source_name: String::new(),
    };
    assert_eq!(
        prediction
            .discover(
                Path::new("/work/one"),
                &[],
                &tuist_cargo_cache_core::NoFileDigestCache
            )
            .unwrap_err()
            .kind(),
        "unsupported-prediction"
    );
}

/// Flags observed on real sys-crate builds, which the first cut of the
/// allowlist rejected. Each one is deterministic key material.
#[test]
fn flags_real_sys_crates_pass_are_admitted() {
    let cases = [
        "--include=/registry/aws-lc-sys-0.44.0/generated-include/prefix.h",
        "-mno-omit-leaf-frame-pointer",
        "-fmerge-all-constants",
        "--param=ssp-buffer-size=4",
    ];
    for flag in cases {
        let arguments = argv(&[flag, "-c", "-o", "a.o", "a.c"]);
        assert!(
            CcInvocation::parse(&arguments).is_ok(),
            "{flag} should be admitted"
        );
    }
}

/// The `cc` crate probes drivers with `-?` to tell MSVC from gcc. That is a
/// question, not a compilation, and must not read as an unmodeled flag.
#[test]
fn the_msvc_probe_flag_reads_as_a_compiler_query() {
    let arguments = argv(&["-?"]);
    assert_eq!(
        CcInvocation::parse(&arguments).unwrap_err().kind(),
        "compiler-query"
    );
}

/// A prefix map rewrites paths inside the object. Normalizing its left side is
/// what lets two checkouts agree on the key, since the path being rewritten is
/// itself checkout-specific.
#[test]
fn prefix_map_sources_normalize_while_replacements_stay_verbatim() {
    let build = |name: &str| {
        let (workspace, target) = checkout(name);
        let flag = format!("-ffile-prefix-map={}=", text(&workspace));
        let arguments = argv(&[&flag, "-c", "-o", "out.o", "src/a.c"]);
        let invocation = CcInvocation::parse(&arguments).expect("admitted");
        let mut context = context(&workspace, &target);
        context.inputs = vec![CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        }];
        invocation.action(context).expect("action")
    };
    let one = build("one");
    let two = build("two");
    assert_eq!(one.digest, two.digest);
    let descriptor = String::from_utf8(one.bytes).expect("utf-8");
    assert!(
        descriptor.contains("-ffile-prefix-map=${workspace}="),
        "{descriptor}"
    );
}

/// A separate `--param` consumes its value rather than leaving it to be
/// mistaken for the source file.
#[test]
fn a_separate_param_value_is_not_mistaken_for_a_source() {
    let arguments = argv(&["--param", "ssp-buffer-size=4", "-c", "-o", "a.o", "a.c"]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");
    assert_eq!(invocation.source(), Path::new("a.c"));
}

/// `-I` is the glued include flag, and the lowercase `-i…` family is a
/// different set of flags entirely. Prefix-stripping the first must not
/// swallow the second, so each one still reaches the handler that knows
/// whether it names a search directory, a forced include, or a sysroot.
#[test]
fn lowercase_include_flags_are_not_swallowed_by_the_include_path_prefix() {
    let (workspace, target) = checkout("one");
    let sysroot = text(&workspace.join("sdk"));
    let arguments = argv(&[
        "-isystem",
        "vendor/include",
        "-iquote",
        "quoted",
        "-idirafter",
        "after",
        "-isysroot",
        &sysroot,
        "-include",
        "forced.h",
        "-imacros",
        "macros.h",
        "-c",
        "-o",
        "out.o",
        "src/a.c",
    ]);
    let invocation = CcInvocation::parse(&arguments).expect("admitted");

    // The source is still the source: a swallowed flag would have consumed it.
    assert_eq!(invocation.source(), Path::new("src/a.c"));
    assert_eq!(invocation.sysroot(), Some(workspace.join("sdk").as_path()));
    assert_eq!(
        invocation.include_dirs(),
        [
            PathBuf::from("vendor/include"),
            PathBuf::from("quoted"),
            PathBuf::from("after"),
        ]
    );
    // Forced includes are keyed but not required to exist beside the working
    // directory; the include chain decides where they come from.
    assert_eq!(invocation.required_inputs(), [PathBuf::from("src/a.c")]);

    // Each one is keyed under its own flag rather than as an include path.
    let mut context = context(&workspace, &target);
    context.inputs = vec![CcActionInput {
        path: workspace.join("src/a.c"),
        digest: digest_of("source"),
    }];
    let action = invocation.action(context).expect("action");
    let descriptor = String::from_utf8(action.bytes).expect("utf-8");
    for flag in [
        "-isystem=",
        "-iquote=",
        "-idirafter=",
        "-include=",
        "-imacros=",
    ] {
        assert!(
            descriptor.contains(flag),
            "{flag} missing from {descriptor}"
        );
    }
}

/// A flag that resolves against the machine's own CPU makes the object depend
/// on something the key cannot name, so another machine must not restore it.
#[test]
fn tuning_for_the_local_cpu_bypasses() {
    for flag in [
        "-march=native",
        "-mcpu=native",
        "-mtune=native",
        "-march=host",
    ] {
        let arguments = argv(&[flag, "-c", "-o", "a.o", "a.c"]);
        assert_eq!(
            CcInvocation::parse(&arguments).unwrap_err().kind(),
            "local-cpu-target",
            "{flag} should bypass"
        );
    }
    // A named architecture is ordinary key material.
    let arguments = argv(&["-march=armv8-a", "-mtune=generic", "-c", "-o", "a.o", "a.c"]);
    assert!(CcInvocation::parse(&arguments).is_ok());
}

/// A forced include is resolved through the include chain, not against the
/// working directory, so it must not be asserted as a required input: the
/// dependency list names it at whatever path it was actually found at.
#[test]
fn forced_includes_are_not_required_to_sit_beside_the_working_directory() {
    for flag in [
        &["-Iinc", "-include", "prefix.h"][..],
        &["-Iinc", "-imacros", "prefix.h"][..],
        &["-Iinc", "--include=prefix.h"][..],
    ] {
        let mut values = flag.to_vec();
        values.extend(["-c", "-o", "out.o", "src/a.c"]);
        let invocation = CcInvocation::parse(&argv(&values)).expect("admitted");
        assert_eq!(
            invocation.required_inputs(),
            [PathBuf::from("src/a.c")],
            "only the source is a required input for {flag:?}"
        );
    }
}

/// The forced header still enters the key, so two compilations that force
/// different headers cannot share an entry.
#[test]
fn forced_includes_still_enter_the_key() {
    let build = |header: &str| {
        let (workspace, target) = checkout("one");
        let invocation =
            CcInvocation::parse(&argv(&["-include", header, "-c", "-o", "out.o", "src/a.c"]))
                .expect("admitted");
        let mut context = context(&workspace, &target);
        context.inputs = vec![CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        }];
        invocation.action(context).expect("action").digest
    };
    assert_ne!(build("one.h"), build("two.h"));
}

/// Instruction-set selections and code-generation switches change the object
/// as a pure function of their text, so they are key material: a `-sys` crate
/// that compiles its SIMD kernels with `-mavx512f`, or turns off LTO for one
/// file, still caches. Selections that resolve against this machine's CPU are
/// a different case and keep bypassing.
#[test]
fn isa_and_codegen_switches_are_admitted_key_material() {
    for flag in [
        "-mavx512f",
        "-mavx512vl",
        "-mbmi2",
        "-mssse3",
        "-mpclmul",
        "-mvpclmulqdq",
        "-mxsave",
        "-fno-lto",
        "-fno-semantic-interposition",
        "-ftls-model=initial-exec",
        "-fsanitize-undefined-strip-path-components=-1",
    ] {
        let invocation = CcInvocation::parse(&argv(&[flag, "-c", "-o", "a.o", "a.c"]))
            .unwrap_or_else(|reason| panic!("{flag} should be admitted: {reason}"));
        assert!(
            invocation.arguments.contains(&Argument::Plain(flag.into())),
            "{flag} must enter the key"
        );
    }
    assert_eq!(
        CcInvocation::parse(&argv(&["-march=native", "-c", "-o", "a.o", "a.c"]))
            .unwrap_err()
            .kind(),
        "local-cpu-target"
    );
}

/// `-o` is often relative to the compiler's working directory -- OpenSSL's
/// makefiles name every object that way -- and a path handed to the cache
/// agent has to mean the same file from the agent's own directory.
#[test]
fn the_object_is_addressed_absolutely_from_the_working_directory() {
    let relative = CcInvocation::parse(&argv(&[
        "-c",
        "-o",
        "ssl/./lib/../ssl_lib.o",
        "ssl/ssl_lib.c",
    ]))
    .unwrap();
    assert_eq!(
        relative.output_in(Path::new("/build/openssl")),
        PathBuf::from("/build/openssl/ssl/ssl_lib.o")
    );
    assert_eq!(
        relative.output(),
        Path::new("ssl/./lib/../ssl_lib.o"),
        "the spelling the key sees is the caller's"
    );

    let absolute = CcInvocation::parse(&argv(&["-c", "-o", "/out/a.o", "a.c"])).unwrap();
    assert_eq!(
        absolute.output_in(Path::new("/elsewhere")),
        PathBuf::from("/out/a.o")
    );
}

/// Preprocessed assembly compiles like C: the preprocessor reports the
/// includes it read, and the assembler is already part of the identity. Plain
/// assembly is not preprocessed, reports nothing, and stays out.
#[test]
fn preprocessed_assembly_is_admitted_and_plain_assembly_is_not() {
    let by_extension = CcInvocation::parse(&argv(&["-c", "-o", "a.o", "curve25519.S"])).unwrap();
    assert_eq!(by_extension.language(), CcLanguage::C);

    let explicit = CcInvocation::parse(&argv(&[
        "-x",
        "assembler-with-cpp",
        "-c",
        "-o",
        "a.o",
        "a.S",
    ]))
    .unwrap();
    assert_eq!(explicit.language(), CcLanguage::C);
    assert!(
        explicit
            .arguments
            .contains(&Argument::Plain("-xassembler-with-cpp".into())),
        "the explicit language enters the key"
    );

    for arguments in [
        vec!["-c", "-o", "a.o", "a.s"],
        vec!["-x", "assembler", "-c", "-o", "a.o", "a.S"],
    ] {
        assert_eq!(
            CcInvocation::parse(&argv(&arguments)).unwrap_err().kind(),
            "unsupported-language"
        );
    }
}

#[test]
fn assembler_input_directives_bypass_only_preprocessed_assembly() {
    let directory = tempfile::tempdir().unwrap();
    let source = directory.path().join("a.S");
    let assembly = CcInvocation::parse(&argv(&["-c", "-o", "a.o", "a.S"])).unwrap();
    for directive in [".include", ".INCBIN", ".SInclude"] {
        std::fs::write(&source, format!("{directive} \"constants.inc\"\n")).unwrap();
        assert_eq!(
            assembly
                .validate_discovered_inputs([source.as_path()])
                .unwrap_err()
                .kind(),
            "assembler-input-directive",
            "{directive} must bypass"
        );
    }

    let c = CcInvocation::parse(&argv(&["-c", "-o", "a.o", "a.c"])).unwrap();
    c.validate_discovered_inputs([source.as_path()])
        .expect("assembler syntax in C text is irrelevant");
}

#[test]
fn debug_dialects_and_levels_have_distinct_action_keys() {
    let mut keys = BTreeSet::new();
    for flag in [
        "-g0", "-gfull", "-ggdb", "-ggdb0", "-ggdb1", "-ggdb2", "-ggdb3",
    ] {
        let (workspace, target) = checkout("debug");
        let invocation = CcInvocation::parse(&argv(&[flag, "-c", "-o", "out.o", "src/a.c"]))
            .expect("object-only debug option should be admitted");
        let mut context = context(&workspace, &target);
        context.inputs.push(CcActionInput {
            path: workspace.join("src/a.c"),
            digest: digest_of("source"),
        });
        let action = invocation.action(context).unwrap();
        assert!(
            keys.insert(action.digest.hash),
            "{flag} must remain in the key"
        );
    }
    for flag in ["-ggdb4", "-gfull-extra", "-gmodules", "-gsplit-dwarf"] {
        assert!(CcInvocation::parse(&argv(&[flag, "-c", "-o", "out.o", "src/a.c"])).is_err());
    }
}

#[test]
fn preprocessing_requires_a_named_output_and_unambiguous_dependencies() {
    for flags in [
        vec!["-E", "main.c"],
        vec!["-E", "main.c", "-o", "-"],
        vec!["-E", "main.c", "-o", "main.i", "-MD"],
        vec!["-E", "main.c", "-o", "main.i", "-MMD"],
        vec!["-E", "main.c", "-o", "main.i", "-MD", "-MF", "-"],
        vec!["-E", "-x", "c", "/", "-o", "main.i", "-MD", "-MF", "main.d"],
    ] {
        assert!(CcInvocation::parse(&argv(&flags)).is_err(), "{flags:?}");
    }
    let invocation = CcInvocation::parse(&argv(&[
        "-E", "main.c", "-o", "main.i", "-MD", "-MF", "main.d",
    ]))
    .unwrap();
    assert!(invocation.is_preprocessing());
    assert_eq!(invocation.output(), Path::new("main.i"));
    assert_eq!(
        invocation.caller_depfile().unwrap().path,
        Path::new("main.d")
    );
}

#[test]
fn preprocessor_keys_retain_checkout_and_argument_spellings() {
    let (first, first_target) = checkout("first");
    let (second, second_target) = checkout("second");
    let invocation = CcInvocation::parse(&argv(&["-E", "main.c", "-o", "main.i"])).unwrap();
    let digest = invocation
        .invocation_digest(&context(&first, &first_target))
        .unwrap();
    assert_ne!(
        digest,
        invocation
            .invocation_digest(&context(&second, &second_target))
            .unwrap()
    );
    let spelled = CcInvocation::parse(&argv(&["-E", "./main.c", "-o", "main.i"])).unwrap();
    assert_ne!(
        digest,
        spelled
            .invocation_digest(&context(&first, &first_target))
            .unwrap()
    );
    let compiled = CcInvocation::parse(&argv(&["-c", "main.c", "-o", "main.i"])).unwrap();
    assert_ne!(
        digest,
        compiled
            .invocation_digest(&context(&first, &first_target))
            .unwrap()
    );
}

#[test]
fn preprocessing_dependency_targets_follow_the_driver_family() {
    let arguments = argv(&[
        "-E",
        "src/main.c",
        "-o",
        "result.i",
        "-MD",
        "-MF",
        "result.d",
    ]);
    for (family, expected) in [
        (CcCompilerFamily::Gcc, "main.o"),
        (CcCompilerFamily::Clang, "result.i"),
    ] {
        let invocation = CcInvocation::parse_for(&arguments, family).unwrap();
        assert_eq!(
            invocation.caller_depfile().unwrap().targets[0].name,
            expected
        );
        let mut explicit = arguments.clone();
        explicit.extend(argv(&["-MT", "custom"]));
        let invocation = CcInvocation::parse_for(&explicit, family).unwrap();
        assert_eq!(
            invocation.caller_depfile().unwrap().targets[0].name,
            "custom"
        );
    }
}

#[cfg(unix)]
#[test]
fn active_developer_roots_cover_beta_and_renamed_xcode() {
    for selected in [
        "/Applications/Xcode-beta.app",
        "/Applications/Xcode-beta.app/Contents/Developer",
        "/opt/toolchains/Xcode-custom.app",
    ] {
        let roots = developer_directory_roots(PathBuf::from(selected));
        let root = if selected.ends_with(".app") {
            PathBuf::from(selected).join("Contents/Developer")
        } else {
            PathBuf::from(selected)
        };
        let sdk = root.join("Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/SDKSettings.json");
        assert!(roots.iter().any(|root| sdk.starts_with(root)));
        assert!(
            !roots
                .iter()
                .any(|root| Path::new("/Applications/Other.app/private.h").starts_with(root))
        );
    }
    assert!(developer_directory_roots(PathBuf::from("relative")).is_empty());
    assert!(developer_directory_roots(PathBuf::from("/")).is_empty());
}

#[cfg(unix)]
#[test]
fn active_developer_roots_include_resolved_symlinks() {
    let directory = tempfile::tempdir().unwrap();
    let real = directory.path().join("developer");
    std::fs::create_dir(&real).unwrap();
    let alias = directory.path().join("selected");
    std::os::unix::fs::symlink(&real, &alias).unwrap();
    let roots = developer_directory_roots(alias.clone());
    assert!(roots.contains(&alias));
    assert!(roots.contains(&std::fs::canonicalize(real).unwrap()));
}
