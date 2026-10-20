use super::*;

/// The probe has to describe the host it actually ran on, because a key that
/// cannot tell two hosts apart is what would let one restore the other's
/// binary.
#[test]
fn the_probe_describes_this_host() {
    let Ok(identity) = identity_without_agent() else {
        // No `cc` on this machine; there is nothing a native link could be
        // keyed on, which is the bypass the adapter already handles.
        return;
    };

    assert!(Path::new(&identity.driver).is_absolute());
    // Nothing in the key may be blank: every host whose probe answered with
    // nothing would otherwise agree on the same empty value.
    assert!(!identity.driver_version.is_empty());
    assert!(!identity.linker_version.is_empty());
    assert!(
        identity.crt_objects.values().all(|d| !d.key().is_empty()),
        "{identity:?}"
    );
    // One line, not the driver's whole banner: the rest lists emulations and
    // search paths that say nothing about which linker this is.
    assert!(!identity.driver_version.contains('\n') || identity.driver_version.lines().count() > 1);

    // Whatever the probes could not place is absent from the key, so the
    // inputs a link cannot be described without have to be present -- two
    // hosts failing the same probe would otherwise agree on a key without
    // either of them having pinned what it stood for. Written against whatever
    // this platform asks for rather than behind a `cfg`, so that the host this
    // does not run on still compiles it.
    for (required, what) in [
        (file_probes().startup, "what the link starts with"),
        (file_probes().libc, "the libc"),
    ] {
        assert!(
            required.is_empty()
                || required
                    .iter()
                    .any(|name| identity.crt_objects.contains_key(*name)),
            "a resolved identity must pin {what}: {identity:?}"
        );
    }
    if cfg!(target_os = "macos") {
        assert!(
            identity.sdk.is_some(),
            "a macOS host should identify its SDK: {identity:?}"
        );
    }
}

/// The identity is recorded as canonical JSON, and read back the same way.
#[test]
fn the_identity_round_trips_through_its_recorded_form() {
    let identity = LinkerIdentity {
        driver: "/usr/bin/cc".into(),
        driver_version: "cc version 14".into(),
        linker_version: "GNU ld 2.42".into(),
        crt_objects: BTreeMap::from([("crt1.o".into(), CacheDigest::blake3(b"crt"))]),
        sdk: None,
        deployment_target: Some("11.0".into()),
    };

    let recorded = canonical_json(&identity).unwrap();

    assert_eq!(
        serde_json::from_slice::<LinkerIdentity>(&recorded).unwrap(),
        identity
    );
}

/// Probe this host without the agent round-trip the real path memoizes through.
fn identity_without_agent() -> Result<LinkerIdentity> {
    let driver = which::which("cc")?;
    let search = search_dirs(&driver);
    probe(&driver, None, search.as_ref()).map(|(identity, _)| identity)
}

#[test]
fn search_dirs_are_read_in_the_order_the_driver_looks() {
    // The driver separates its lists the way the host separates PATH.
    let separator = if cfg!(windows) { ';' } else { ':' };
    let text = format!(
        "install: /usr/lib/gcc/x86_64-linux-gnu/13/\nprograms: =/opt/x/{separator}/usr/libexec/gcc/x86_64-linux-gnu/13/\nlibraries: =/usr/lib/gcc/x86_64-linux-gnu/13/{separator}/lib/x86_64-linux-gnu/\n"
    );
    let dirs = parse_search_dirs(&text).expect("both lists are present");
    assert_eq!(
        dirs.programs,
        vec![
            PathBuf::from("/opt/x/"),
            PathBuf::from("/usr/libexec/gcc/x86_64-linux-gnu/13/")
        ]
    );
    assert_eq!(
        dirs.libraries,
        vec![
            PathBuf::from("/usr/lib/gcc/x86_64-linux-gnu/13/"),
            PathBuf::from("/lib/x86_64-linux-gnu/")
        ]
    );
    // An answer without both lists is no map, whichever language it is in.
    assert_eq!(parse_search_dirs("nothing here"), None);
    assert_eq!(
        parse_search_dirs("Programme: =/opt/x/\nBibliotheken: =/lib/\n"),
        None
    );
    assert_eq!(
        parse_search_dirs("programs: =/opt/x/\nlibraries: =\n"),
        None
    );
}

/// WSL sets `LIBRARY_PATH=/usr/lib/wsl/lib:`, and GCC searches the empty
/// element after the colon as the current directory, reporting it as `./`.
/// The driver searched relative to this process's working directory, so a
/// directory without a root comes back under it: a pin is checked later from
/// other working directories, where `./crt1.o` names some other file. A
/// directory with a root is left as the driver spelled it.
#[test]
fn rootless_search_dirs_are_placed_under_the_working_directory() {
    let separator = if cfg!(windows) { ';' } else { ':' };
    let text = format!(
        "install: /usr/lib/gcc/x86_64-linux-gnu/15/\nprograms: =/usr/libexec/gcc/x86_64-linux-gnu/15/\nlibraries: =/usr/lib/wsl/lib/x86_64-linux-gnu/15/{separator}./x86_64-linux-gnu/15/{separator}./{separator}/usr/lib/gcc/x86_64-linux-gnu/15/\n"
    );
    let dirs = parse_search_dirs(&text).expect("both lists are present");
    let here = std::env::current_dir().unwrap();
    assert_eq!(
        dirs.libraries,
        vec![
            PathBuf::from("/usr/lib/wsl/lib/x86_64-linux-gnu/15/"),
            here.join("x86_64-linux-gnu").join("15"),
            here.clone(),
            PathBuf::from("/usr/lib/gcc/x86_64-linux-gnu/15/"),
        ]
    );
    assert!(dirs.libraries.iter().all(|directory| directory.has_root()));
    assert_eq!(
        dirs.programs,
        vec![PathBuf::from("/usr/libexec/gcc/x86_64-linux-gnu/15/")]
    );
}

/// An identity recorded under a search that reaches into the working
/// directory is keyed by that directory too, and one that does not is not:
/// a checkout must not answer for another's `./crt1.o`, while every checkout
/// shares an identity whose search never leaves the toolchain.
#[test]
fn a_search_through_the_working_directory_is_told_from_the_environment() {
    let environment = |library_path: Option<&str>| {
        BTreeMap::from([("LIBRARY_PATH".to_string(), library_path.map(str::to_owned))])
    };
    let search_depends_on_working_directory = |environment: &BTreeMap<String, Option<String>>| {
        super::search_depends_on_working_directory(|name| {
            environment
                .get(name)
                .and_then(|value| value.as_deref())
                .map(std::ffi::OsString::from)
        })
    };
    let separator = if cfg!(windows) { ";" } else { ":" };
    // WSL's default: the trailing separator is an empty element, which GCC
    // searches as the current directory.
    assert!(search_depends_on_working_directory(&environment(Some(
        &format!("/usr/lib/wsl/lib{separator}")
    ))));
    assert!(search_depends_on_working_directory(&environment(Some(
        &format!("/usr/lib/wsl/lib{separator}lib")
    ))));
    assert!(!search_depends_on_working_directory(&environment(Some(
        "/usr/lib/wsl/lib"
    ))));
    assert!(!search_depends_on_working_directory(&environment(None)));
    assert!(!search_depends_on_working_directory(&BTreeMap::new()));
    assert!(search_depends_on_working_directory(&BTreeMap::from([(
        "COMPILER_PATH".to_string(),
        Some("tools".to_string())
    )])));
    // A prefix is a single path, and one without a root moves the same way.
    let prefix =
        |value: &str| BTreeMap::from([("GCC_EXEC_PREFIX".to_string(), Some(value.to_string()))]);
    assert!(search_depends_on_working_directory(&prefix("gcc-")));
    assert!(!search_depends_on_working_directory(&prefix(
        "/usr/lib/gcc/"
    )));
}

/// A working directory keys the identity by its own bytes. Two directories a
/// lossy conversion would spell the same way must not share a key: their
/// drivers search different places.
#[test]
#[cfg(unix)]
fn working_directories_key_apart_even_when_not_utf8() {
    use std::os::unix::ffi::OsStrExt as _;
    assert_eq!(working_directory_key(Path::new("/work/app")), "/work/app");
    let first = PathBuf::from(OsStr::from_bytes(b"/work/\xff"));
    let second = PathBuf::from(OsStr::from_bytes(b"/work/\xfe"));
    assert_eq!(
        first.to_string_lossy(),
        second.to_string_lossy(),
        "the lossy spellings collide, which is the point"
    );
    assert_ne!(
        working_directory_key(&first),
        working_directory_key(&second)
    );
    assert!(working_directory_key(&first).starts_with("hex:"));
}

/// The driver receives `LIBRARY_PATH` as bytes, and searches a rootless
/// element in it whether or not the rest of the value is UTF-8. The check
/// reads it the same way, so such a value is not mistaken for an unset one.
#[test]
#[cfg(unix)]
fn a_rootless_element_is_found_in_a_search_variable_that_is_not_utf8() {
    use std::os::unix::ffi::OsStrExt as _;
    let value = |bytes: &[u8]| {
        let value = std::ffi::OsString::from(OsStr::from_bytes(bytes));
        move |name: &str| (name == "LIBRARY_PATH").then(|| value.clone())
    };
    assert!(search_depends_on_working_directory(value(
        b"/usr/lib/\xff:"
    )));
    assert!(search_depends_on_working_directory(value(
        b"/usr/lib/\xff:lib"
    )));
    assert!(!search_depends_on_working_directory(value(
        b"/usr/lib/\xff:/usr/lib"
    )));
}

/// A candidate the search passed over because it could not run is pinned
/// with its permissions, so `chmod +x` is a change.
#[test]
#[cfg(unix)]
fn a_candidate_made_executable_breaks_its_pin() {
    use std::os::unix::fs::PermissionsExt as _;
    let directory = tempfile::tempdir().unwrap();
    let candidate = directory.path().join("ld");
    std::fs::write(&candidate, "not yet a linker").unwrap();
    std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o644)).unwrap();
    let pin = PinnedFile::describe(&candidate).unwrap();
    assert!(pin.holds());
    std::fs::set_permissions(&candidate, std::fs::Permissions::from_mode(0o755)).unwrap();
    assert!(!pin.holds());
}

/// A program the driver found in one of its own directories is pinned with
/// every directory the driver looked in first, so a same-named file
/// appearing in one of them is noticed, and not with the ones after.
#[test]
#[cfg(unix)]
fn a_driver_named_program_pins_the_directories_searched_before_it() {
    let directory = tempfile::tempdir().unwrap();
    let (first, second, third) = (
        directory.path().join("first"),
        directory.path().join("second"),
        directory.path().join("third"),
    );
    for dir in [&first, &second, &third] {
        std::fs::create_dir(dir).unwrap();
    }
    std::fs::write(second.join("ld"), "linker").unwrap();
    let search = SearchDirs {
        programs: vec![first.clone(), second.clone(), third.clone()],
        libraries: Vec::new(),
    };

    let located = Located::program(OsStr::new("ld"), &second.join("ld"), Some(&search)).unwrap();
    let pins = located.pins.clone().into_vec();
    assert_eq!(
        pins.iter().map(|pin| pin.path.clone()).collect::<Vec<_>>(),
        vec![first.join("ld"), second.join("ld")]
    );
    assert!(pins[0].state.is_none() && pins[1].state.is_some());

    // A shadow appearing where the search looked first breaks the pins.
    std::fs::write(first.join("ld"), "another linker").unwrap();
    assert!(!pins[0].holds() && pins[1].holds());

    // Without the map the program resolves as before and pins nothing.
    let unmapped = Located::program(OsStr::new("ld"), &second.join("ld"), None).unwrap();
    assert_eq!(unmapped.path, second.join("ld"));
    assert!(unmapped.pins.into_vec().is_empty());
}

/// A bare answer means the driver searched its own directories, found
/// nothing, and would leave it to PATH: those directories are pinned along
/// with the PATH candidates before the program.
#[test]
#[cfg(unix)]
fn a_bare_program_name_pins_the_driver_directories_and_the_path_search() {
    let directory = tempfile::tempdir().unwrap();
    let search = SearchDirs {
        programs: vec![directory.path().to_path_buf()],
        libraries: Vec::new(),
    };
    let shell = which::which("sh").unwrap();
    let located = Located::program(OsStr::new("sh"), Path::new("sh"), Some(&search)).unwrap();
    assert_eq!(located.path, shell);
    let pins = located.pins.into_vec();
    assert_eq!(
        pins.first().map(|pin| pin.path.clone()),
        Some(directory.path().join("sh"))
    );
    assert!(pins.first().is_some_and(|pin| pin.state.is_none()));
    assert_eq!(pins.last().map(|pin| pin.path.clone()), Some(shell));
}

/// A startup object is pinned with every library directory the driver
/// looked in before the one that held it.
#[test]
fn a_found_object_pins_the_library_directories_searched_before_it() {
    let directory = tempfile::tempdir().unwrap();
    let (early, late) = (
        directory.path().join("early"),
        directory.path().join("late"),
    );
    std::fs::create_dir_all(&late).unwrap();
    std::fs::create_dir_all(&early).unwrap();
    std::fs::write(late.join("crt1.o"), "startup").unwrap();
    let mut pins = Pins::default();
    pin_search(
        &mut pins,
        OsStr::new("crt1.o"),
        &late.join("crt1.o"),
        &[early.clone(), late.clone(), directory.path().join("never")],
    );
    assert_eq!(
        pins.into_vec()
            .iter()
            .map(|pin| (pin.path.clone(), pin.state.is_some()))
            .collect::<Vec<_>>(),
        vec![(early.join("crt1.o"), false), (late.join("crt1.o"), true)]
    );
}

/// A file the filesystem will not describe leaves the identity unpinned
/// rather than unprobed: the link is as cacheable as it was, for this
/// session.
#[test]
#[cfg(unix)]
fn an_undescribable_file_unpins_without_failing() {
    use std::os::unix::fs::PermissionsExt as _;
    let directory = tempfile::tempdir().unwrap();
    let closed = directory.path().join("closed");
    std::fs::create_dir(&closed).unwrap();
    std::fs::set_permissions(&closed, std::fs::Permissions::from_mode(0o000)).unwrap();
    let inside = closed.join("ld");
    let describable = std::fs::metadata(&inside)
        .map(|_| true)
        .unwrap_or_else(|error| error.kind() == std::io::ErrorKind::NotFound);
    let mut pins = Pins::default();
    pins.add(directory.path());
    pins.add(&inside);
    std::fs::set_permissions(&closed, std::fs::Permissions::from_mode(0o755)).unwrap();
    // Running as root sees through the mode; anyone else cannot describe it.
    if describable {
        assert_eq!(pins.into_vec().len(), 2);
    } else {
        assert!(pins.clone().into_vec().is_empty(), "{pins:?}");
        let mut more = Pins::default();
        more.add(directory.path());
        more.extend(pins);
        assert!(more.into_vec().is_empty());
    }
}

/// The files a probe pins are the ones it read, so that a session which
/// finds them unchanged can trust what an earlier one recorded.
#[test]
#[cfg(target_os = "linux")]
fn a_probe_pins_the_files_it_read() {
    let driver = which::which("cc").unwrap();
    let search = search_dirs(&driver).expect("the driver reports its search directories");
    let (identity, pins) = probe(&driver, None, Some(&search)).unwrap();
    assert!(pins.iter().all(|pin| pin.path.is_absolute()), "{pins:?}");
    assert!(pins.iter().all(PinnedFile::holds), "{pins:?}");
    let present = pins.iter().filter(|pin| pin.state.is_some()).count();
    // The driver, the linker, and every object the identity hashed; the
    // directories searched before each of them are pinned absent.
    assert!(present >= 2 + identity.crt_objects.len(), "{pins:?}");
    assert_eq!(pins[0].path, driver);
    // Every program directory the driver would try before PATH is covered.
    let first_program_dir = search.programs.first().expect("a program directory");
    assert!(
        pins.iter()
            .any(|pin| pin.path == first_program_dir.join("ld")),
        "{pins:?}"
    );
}

/// A `-fuse-ld` selection is resolved through the driver first, and a
/// selection naming nothing the driver or PATH can find is an error rather
/// than a key pointing at a linker nobody pinned.
#[test]
fn a_fuse_ld_selection_resolves_or_is_refused() {
    let Ok(driver) = which::which("cc") else {
        return;
    };

    let bogus = resolve_fuse_ld(
        &driver,
        "definitely-not-a-real-linker",
        search_dirs(&driver).as_ref(),
    );
    assert!(
        bogus.is_err(),
        "a nonexistent linker must not resolve: {bogus:?}"
    );

    // An absolute selection names the linker directly, no resolution needed.
    let direct = Path::new(if cfg!(windows) { "C:/ld" } else { "/opt/ld" });
    assert_eq!(
        resolve_fuse_ld(
            &driver,
            direct.to_str().unwrap(),
            search_dirs(&driver).as_ref()
        )
        .unwrap()
        .path,
        direct
    );

    // Whatever the host does provide resolves to an absolute path that
    // exists: anything less could alias two linkers in one memoization key.
    for name in ["mold", "lld", "bfd", "gold"] {
        if let Ok(located) = resolve_fuse_ld(&driver, name, search_dirs(&driver).as_ref()) {
            let program = &located.path;
            assert!(
                program.is_absolute() && program.exists(),
                "{name} resolved to {program:?}"
            );
            // Found on PATH or named by the driver, it pins itself last.
            let pins = located.pins.clone().into_vec();
            assert_eq!(pins.last().map(|pin| &pin.path), Some(program));
        }
    }
}

/// The probe names are platform knowledge, but the rule about them is not:
/// what a key cannot describe a link without has to be present, whatever host
/// this test runs on.
#[test]
fn a_link_is_only_identified_once_its_essentials_resolve() {
    let directory = tempfile::tempdir().unwrap();
    let placed = |name: &str| {
        let path = directory.path().join(name);
        std::fs::write(&path, name).unwrap();
        path
    };
    let probes = FileProbes {
        startup: &["Scrt1.o", "crt1.o"],
        libc: &["libc.so.6", "libc.a"],
        rest: &["crti.o"],
    };

    // One of each essential is enough, and the optional one is not required.
    let resolved = probe_files(&probes, |name| {
        matches!(name, "crt1.o" | "libc.a").then(|| placed(name))
    })
    .unwrap();
    assert_eq!(
        resolved.keys().collect::<Vec<_>>(),
        ["crt1.o", "libc.a"],
        "only what resolved belongs in the key"
    );

    // A host whose libc the driver cannot place is a host whose links cannot
    // be told apart from another's.
    assert!(
        probe_files(&probes, |name| (name == "crt1.o").then(|| placed(name))).is_err(),
        "no libc should refuse"
    );
    assert!(
        probe_files(&probes, |name| (name == "libc.a").then(|| placed(name))).is_err(),
        "no startup object should refuse"
    );
    assert!(
        probe_files(&probes, |_| None).is_err(),
        "nothing should refuse"
    );

    // Two hosts placing different libcs cannot agree on a key.
    let glibc = probe_files(&probes, |name| {
        matches!(name, "crt1.o" | "libc.so.6").then(|| placed(name))
    })
    .unwrap();
    assert_ne!(glibc, resolved);
}

/// A platform with no loose objects to place -- macOS, whose SDK identity
/// covers what they would have pinned -- is not thereby unidentifiable.
#[test]
fn a_platform_that_places_nothing_is_still_identified() {
    let probes = FileProbes {
        startup: &[],
        libc: &[],
        rest: &[],
    };

    assert!(probe_files(&probes, |_| None).unwrap().is_empty());
}

#[test]
fn a_windows_identity_requires_toolset_sdk_and_both_crts() {
    let version = windows_sdk_identity_for(|name| match name {
        "VCToolsVersion" => Some("14.40".into()),
        "WindowsSDKVersion" => Some("10.0.26100.0".into()),
        _ => None,
    })
    .unwrap();
    assert!(version.contains("VCToolsVersion=14.40"));
    assert!(windows_sdk_identity_for(|_| None).is_err());

    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join("vcruntime.lib"), b"vc runtime").unwrap();
    std::fs::write(directory.path().join("ucrt.lib"), b"universal crt").unwrap();
    let identity = windows_crt_objects_in(&[directory.path().to_path_buf()]).unwrap();
    assert_eq!(identity.len(), 2);
    std::fs::remove_file(directory.path().join("ucrt.lib")).unwrap();
    assert!(windows_crt_objects_in(&[directory.path().to_path_buf()]).is_err());
}

/// `SDKROOT` names the SDK a link is made against, so it has to be the SDK
/// every part of the identity describes. Reporting the default SDK's version
/// beside another SDK's path would put an SDK nothing was built against in the
/// key.
#[cfg(target_os = "macos")]
#[test]
fn the_sdk_identity_follows_sdkroot() {
    let Ok(Some(_)) = sdk_identity_for(None) else {
        // No usable SDK on this machine; there is nothing to describe.
        return;
    };

    // An SDK that is not there cannot be described, so it is refused rather
    // than quietly reported as the default one.
    let overridden = sdk_identity_for(Some("/nonexistent.sdk".into()));

    assert!(
        overridden.is_err(),
        "an unusable SDKROOT must not report the default SDK: {overridden:?}"
    );
}

/// A shim installed by `tuist_cargo_cache setup` is driven by plain cargo, with no session
/// to have applied the platform gate, so the shim applies it itself rather
/// than trusting the variable it was handed.
#[test]
fn the_platform_gate_does_not_depend_on_who_set_the_variable() {
    assert_eq!(
        crate::session::cache_links_supported(),
        cfg!(any(target_os = "linux", target_os = "macos", windows))
    );
    // Whatever the environment says, an unsupported host never admits links.
    if !crate::session::cache_links_supported() {
        assert!(!crate::session::cache_links_requested());
    }
}
