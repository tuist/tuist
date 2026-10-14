//! Identity of the toolchain that links a native program.
//!
//! rustc hands a native link to a driver -- `cc` on the platforms this tier
//! admits -- which chooses the real linker, the startup objects, and on macOS
//! the SDK. None of that appears in rustc dep-info, so a link is only
//! cacheable once it does appear in the key.
//!
//! What enters the key is identity rather than content wherever a compiler's
//! own identity is: `cc --version` names a toolchain as precisely as
//! `rustc -vV` names rustc, and far more cheaply than hashing the binary. The
//! startup objects are hashed instead, because nothing else pins the libc a
//! link resolves against.

use crate::session;
use eyre::{Context, Result, bail};
use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::path::{Path, PathBuf};
use std::process::Command;
use tuist_cargo_cache_core::{
    AgentRequest, AgentResponse, CacheDigest, PinnedFile, canonical_json,
};
use tuist_cargo_cache_rustc::LinkerIdentity;

/// Environment that selects what the probes below report.
///
/// The search paths are here because they decide which `ld` a driver names,
/// and the identity is kept across sessions: one recorded under a shell that
/// found one linker must not answer for a shell that would find another.
const IDENTITY_ENVIRONMENT: &[&str] = &[
    "COMPILER_PATH",
    "GCC_EXEC_PREFIX",
    "LIBRARY_PATH",
    "PATH",
    "SDKROOT",
    "MACOSX_DEPLOYMENT_TARGET",
    "LIB",
    "UCRTVersion",
    "UniversalCRTSdkDir",
    "VCToolsInstallDir",
    "VCToolsVersion",
    "WindowsSdkDir",
    "WindowsSDKVersion",
];

/// What the driver is asked to place, and which of it a key cannot do without.
///
/// The names are platform knowledge; the rule about them is not, so the two are
/// separated and only the names are chosen by `cfg`. A host this build cannot
/// run on is still a host whose logic can be tested here.
#[derive(Clone, Copy)]
struct FileProbes {
    /// The object that starts a program. One of these must resolve, or nothing
    /// pins what the link began with.
    startup: &'static [&'static str],
    /// Names a libc goes by, across the C libraries and linkage modes this
    /// tier admits. One must resolve too: libc is the input a statically
    /// linked program carries inside it, so a key that does not pin it lets
    /// one distribution's binary restore onto another's.
    libc: &'static [&'static str],
    /// Everything else a link pulls in. Individually optional -- a toolchain
    /// that does not use one is not thereby unidentifiable.
    rest: &'static [&'static str],
}

/// GNU-style hosts link against loose objects the driver can place.
const GNU_PROBES: FileProbes = FileProbes {
    startup: &["Scrt1.o", "crt1.o"],
    libc: &["libc.so.6", "libc.so", "libc.a", "libc.musl-x86_64.so.1"],
    // Both spellings of the constructor objects: GNU drivers place the `S`
    // variants for shared and position-independent links and the plain or `T`
    // ones for static and non-PIE links. Naming only the first pair would
    // leave a static link's own CRT out of the key, so changing it would not
    // change the key.
    rest: &[
        "crti.o",
        "crtn.o",
        "crtbegin.o",
        "crtbeginS.o",
        "crtbeginT.o",
        "crtend.o",
        "crtendS.o",
    ],
};

/// macOS links against the SDK rather than loose objects, and the SDK identity
/// below covers what those would have pinned.
const NO_PROBES: FileProbes = FileProbes {
    startup: &[],
    libc: &[],
    rest: &[],
};

/// What this platform asks the driver to place.
///
/// Chosen with `cfg!` rather than `#[cfg]` so that both tables are compiled
/// wherever this builds. A table only one platform compiles is a table only
/// that platform's CI can find a mistake in.
fn file_probes() -> FileProbes {
    if cfg!(target_os = "linux") {
        GNU_PROBES
    } else {
        NO_PROBES
    }
}

/// Describe the linker rustc will use for a native link on this host.
///
/// Memoized through the agent for the life of the build, since the answer is
/// the same for every link in it and the probes are several processes.
/// Describe the default linker, a Clang driver selecting a named Unix linker,
/// or a recognized Windows linker override.
///
/// `fuse_ld` is a `-fuse-ld=<name>` selection the adapter modeled for a
/// native link: the driver stays `cc`, but the linker it invokes becomes
/// `ld.<name>`, which is resolved and pinned in place of the default `ld`.
/// The resolved linker path joins the memoization key, never the raw
/// selector: which `ld.<name>` a driver invokes depends on its own search
/// path, COMPILER_PATH, and PATH, so a key holding only `mold` could stand
/// for two different linkers.
pub(crate) fn identity_for(
    override_linker: Option<&Path>,
    fuse_ld: Option<&str>,
) -> Result<LinkerIdentity> {
    if fuse_ld.is_some() && cfg!(windows) {
        bail!(
            "a `-fuse-ld` selection with a Windows linker is not one tuist_cargo_cache can identify"
        );
    }
    let driver = if let Some(linker) = override_linker {
        let name = linker
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default()
            .to_ascii_lowercase();
        let recognized = if cfg!(windows) {
            matches!(
                name.as_str(),
                "link" | "link.exe" | "lld-link" | "lld-link.exe"
            )
        } else {
            matches!(name.as_str(), "clang" | "clang++")
        };
        if !recognized {
            bail!("the selected linker is not one tuist_cargo_cache can identify");
        }
        which::which(linker)
            .wrap_err_with(|| format!("failed to find linker `{}`", linker.display()))?
    } else if cfg!(windows) {
        msvc_tool("link.exe").wrap_err("failed to find the linker `link.exe`")?
    } else {
        which::which("cc").wrap_err("failed to find the linker driver `cc`")?
    };
    let mut environment = IDENTITY_ENVIRONMENT
        .iter()
        .map(|name| ((*name).into(), std::env::var(name).ok()))
        .collect::<BTreeMap<_, _>>();
    // A search that looks in the working directory finds different files in
    // different checkouts, so an identity recorded in one must not answer for
    // another. Told from the variables rather than by asking the driver, for
    // the same reason the search map below is asked for lazily.
    if search_depends_on_working_directory(|name| std::env::var_os(name))
        && let Ok(directory) = std::env::current_dir()
    {
        environment.insert(
            "TUIST_CARGO_CACHE_WORKING_DIRECTORY".into(),
            Some(working_directory_key(&directory)),
        );
    }
    // The map of where the driver looks, which is what the pins have to
    // cover. Asked once, and only on the way to a probe: a memoized identity
    // must not cost a process to find.
    let search_dirs_once = std::cell::OnceCell::new();
    let search = || {
        search_dirs_once
            .get_or_init(|| {
                if cfg!(windows) {
                    None
                } else {
                    search_dirs(&driver)
                }
            })
            .as_ref()
    };
    let fuse_ld = fuse_ld
        .map(|selection| resolve_fuse_ld(&driver, selection, search()))
        .transpose()?;
    if let Some(located) = &fuse_ld {
        environment.insert(
            "TUIST_CARGO_CACHE_FUSE_LD".into(),
            Some(located.path.display().to_string()),
        );
    }
    if let Some(cached) = find_recorded(&driver, &environment)? {
        return Ok(cached);
    }
    let (identity, pins) = probe(&driver, fuse_ld.as_ref(), search())?;
    record(&driver, &environment, &identity, pins)?;
    Ok(identity)
}

/// Whether the driver's search for programs and objects reaches into the
/// working directory.
///
/// GCC searches every element of `COMPILER_PATH` and `LIBRARY_PATH` as
/// given, and an empty element as `.`, so an element without a root names a
/// directory that moves with the process; a `GCC_EXEC_PREFIX` without a root
/// moves the same way. The environment is the whole answer: the driver is
/// not asked, because this decides whether a recorded identity can be looked
/// up at all. The variables are read as the driver receives them, bytes and
/// all, so a value that is not UTF-8 is still searched for a rootless element.
fn search_depends_on_working_directory(
    variable: impl Fn(&str) -> Option<std::ffi::OsString>,
) -> bool {
    ["COMPILER_PATH", "LIBRARY_PATH"].iter().any(|name| {
        variable(name).is_some_and(|value| {
            std::env::split_paths(&value).any(|directory| !directory.has_root())
        })
    }) || variable("GCC_EXEC_PREFIX").is_some_and(|prefix| !Path::new(&prefix).has_root())
}

/// The working directory as an identity key: the path itself when it is
/// UTF-8, and otherwise its bytes spelled out, so two directories that differ
/// only where a lossy conversion would replace a byte still key apart. No
/// absolute path begins with the marker, so the two spellings cannot meet.
fn working_directory_key(directory: &Path) -> String {
    match directory.to_str() {
        Some(directory) => directory.to_owned(),
        None => format!(
            "hex:{}",
            hex::encode(directory.as_os_str().as_encoded_bytes())
        ),
    }
}

/// Where the driver looks for programs and for startup objects, in the
/// order it looks, as `-print-search-dirs` reports them.
///
/// This is the map the pins have to cover. A linker or a CRT object the
/// driver names today was found in one of these directories, or in none of
/// them; a same-named file appearing in an earlier one would be found first
/// tomorrow, under an unchanged `COMPILER_PATH` or `LIBRARY_PATH`, with the
/// file the probe pinned still exactly as it was. So every candidate the
/// search rejected on its way is pinned too, absent as it is. A driver that
/// cannot report its search directories leaves the identity unpinned.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct SearchDirs {
    programs: Vec<PathBuf>,
    libraries: Vec<PathBuf>,
}

fn search_dirs(driver: &Path) -> Option<SearchDirs> {
    // The field names are translated strings in GCC, so the question is
    // asked in the C locale, and an answer without both lists is no map:
    // a driver that accepts the flag but prints something else would
    // otherwise pass for one that searched nowhere.
    let output = Command::new(driver)
        .arg("-print-search-dirs")
        .env("LC_ALL", "C")
        .env("LANGUAGE", "C")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    parse_search_dirs(&String::from_utf8_lossy(&output.stdout))
}

/// A directory without a root comes back under the working directory. GCC
/// searches an empty element of `LIBRARY_PATH` or `COMPILER_PATH` as the
/// current directory and reports it as `./`, and WSL sets
/// `LIBRARY_PATH=/usr/lib/wsl/lib:` with exactly that trailing empty element
/// on every shell. The driver ran with this process's working directory, so
/// that is the directory it searched; a pin has to say so, because pins are
/// checked later from other working directories, where `./crt1.o` would name
/// a different file in every checkout. A working directory that cannot be
/// read leaves no map at all rather than a relative pin: the identity is then
/// probed again next session, which is the safe side.
fn parse_search_dirs(text: &str) -> Option<SearchDirs> {
    let list = |field: &str| {
        text.lines()
            .find_map(|line| line.strip_prefix(field))
            .map(|value| value.trim().trim_start_matches('='))
            .and_then(|value| {
                std::env::split_paths(value)
                    .filter(|directory| !directory.as_os_str().is_empty())
                    .map(|directory| {
                        if directory.has_root() {
                            Ok(directory)
                        } else {
                            std::path::absolute(&directory)
                        }
                    })
                    .collect::<std::io::Result<Vec<_>>>()
                    .ok()
            })
            .filter(|directories| !directories.is_empty())
    };
    Some(SearchDirs {
        programs: list("programs:")?,
        libraries: list("libraries:")?,
    })
}

/// Whether `candidate` is the file the driver printed as `found`.
///
/// The driver prints the directory it searched joined to the name, so the
/// two usually compare equal as written; a directory listed under one
/// spelling and printed under another is settled on disk.
fn same_file(candidate: &Path, found: &Path) -> bool {
    candidate == found
        || matches!(
            (std::fs::canonicalize(candidate), std::fs::canonicalize(found)),
            (Ok(left), Ok(right)) if left == right
        )
}

/// Pin `found`, which a search for `name` through `directories` in order
/// produced, together with every candidate that search rejected first.
///
/// A file the search never reached is not pinned: it could not shadow the
/// one found. A `found` that is under none of the directories, which a
/// `-B` prefix can produce, pins every candidate and itself.
fn pin_search(pins: &mut Pins, name: &OsStr, found: &Path, directories: &[PathBuf]) {
    for directory in directories {
        let candidate = directory.join(name);
        pins.add(&candidate);
        if same_file(&candidate, found) {
            return;
        }
    }
    pins.add(found);
}

/// A program the probe resolved, and where a search for it looked first.
///
/// A name found on PATH is pinned with every place the search passed over
/// on the way: a linker appearing in one of those would be the one found
/// next time, under the same PATH string, and the identity must notice.
#[derive(Debug)]
struct Located {
    path: PathBuf,
    pins: Pins,
}

impl Located {
    /// A program named outright, pinned by itself.
    fn named(path: PathBuf) -> Self {
        let mut pins = Pins::default();
        pins.add(&path);
        Self { path, pins }
    }

    /// A program the driver was asked for by `name`, given what it printed:
    /// an absolute path it found in one of its own program directories, or
    /// the bare name, meaning it would leave the search to PATH when it
    /// runs. Either way the directories the driver searched first are
    /// pinned, and so are the ones on PATH before the program when PATH is
    /// where it was found.
    fn program(name: &OsStr, printed: &Path, search: Option<&SearchDirs>) -> Result<Self> {
        let programs = search.map(|search| search.programs.as_slice());
        if printed.is_absolute() {
            let mut pins = Pins::default();
            match programs {
                Some(programs) => pin_search(&mut pins, name, printed, programs),
                None => pins.0 = None,
            }
            return Ok(Self {
                path: printed.to_path_buf(),
                pins,
            });
        }
        let mut pins = Pins::default();
        match programs {
            Some(programs) => {
                for directory in programs {
                    pins.add(&directory.join(name));
                }
            }
            None => pins.0 = None,
        }
        let searched = Located::searched(name)?;
        pins.extend(searched.pins);
        Ok(Self {
            path: searched.path,
            pins,
        })
    }

    /// A program found by searching PATH for `name`, pinned by itself and by
    /// every candidate the search rejected before it.
    fn searched(name: &OsStr) -> Result<Self> {
        let path = which::which(name)
            .wrap_err_with(|| format!("failed to find `{}`", name.to_string_lossy()))?;
        let mut pins = Pins::default();
        if let Some(search) = std::env::var_os("PATH") {
            for directory in std::env::split_paths(&search) {
                if Some(directory.as_path()) == path.parent() {
                    break;
                }
                pins.add(&directory.join(name));
            }
        }
        pins.add(&path);
        Ok(Self { path, pins })
    }
}

/// The files a probe has read, or nothing once one of them could not be
/// described.
///
/// The probe itself is unaffected: a file the filesystem will not describe
/// is still run or hashed as before, and the identity it contributes to is
/// as valid as ever. It is only not one a later session can trust without
/// probing again, so it is kept for this session alone.
#[derive(Debug, Clone)]
struct Pins(Option<Vec<PinnedFile>>);

impl Default for Pins {
    fn default() -> Self {
        Self(Some(Vec::new()))
    }
}

impl Pins {
    fn add(&mut self, path: &Path) {
        match (&mut self.0, PinnedFile::describe(path)) {
            (Some(pins), Some(pin)) => pins.push(pin),
            _ => self.0 = None,
        }
    }

    fn extend(&mut self, more: Pins) {
        match (&mut self.0, more.0) {
            (Some(pins), Some(more)) => pins.extend(more),
            _ => self.0 = None,
        }
    }

    fn into_vec(self) -> Vec<PinnedFile> {
        self.0.unwrap_or_default()
    }
}

fn find_recorded(
    driver: &Path,
    environment: &BTreeMap<String, Option<String>>,
) -> Result<Option<LinkerIdentity>> {
    let responses = session::request_agent(&[AgentRequest::FindExecutableIdentity {
        executable: driver.to_path_buf(),
        environment: environment.clone(),
    }])?;
    let Some(AgentResponse::ExecutableIdentity { stdout }) = responses.into_iter().next() else {
        bail!("cache agent did not return the linker identity");
    };
    stdout
        .map(|stdout| serde_json::from_slice(&stdout).wrap_err("invalid recorded linker identity"))
        .transpose()
}

fn record(
    driver: &Path,
    environment: &BTreeMap<String, Option<String>>,
    identity: &LinkerIdentity,
    pins: Vec<PinnedFile>,
) -> Result<()> {
    let responses = session::request_agent(&[AgentRequest::StoreExecutableIdentity {
        executable: driver.to_path_buf(),
        environment: environment.clone(),
        stdout: canonical_json(identity)?,
        pins,
    }])?;
    match responses.into_iter().next() {
        Some(AgentResponse::ExecutableIdentity { .. }) => Ok(()),
        Some(AgentResponse::Error { message }) => bail!(message),
        _ => bail!("cache agent returned an unexpected linker identity response"),
    }
}

/// Describe the linker, and name the files the description was read from.
///
/// Those files pin the identity across sessions: the driver, the linker it
/// names, and the objects it places, each described as the probe reads it.
/// A platform whose identity comes from tools rather than files -- a Windows
/// toolset, a macOS SDK -- pins nothing and is probed every session.
fn probe(
    driver: &Path,
    fuse_ld: Option<&Located>,
    search: Option<&SearchDirs>,
) -> Result<(LinkerIdentity, Vec<PinnedFile>)> {
    if cfg!(windows) {
        return Ok((probe_windows(driver)?, Vec::new()));
    }
    let mut pins = Pins::default();
    pins.add(driver);
    let (linker_version, linker) = linker_version(driver, fuse_ld, search)?;
    pins.extend(linker);
    let (crt_objects, objects) = crt_objects(driver, search)?;
    pins.extend(objects);
    let sdk = sdk_identity()?;
    let pins = if sdk.is_some() {
        Vec::new()
    } else {
        pins.into_vec()
    };
    let identity = LinkerIdentity {
        driver: driver
            .to_str()
            .ok_or_else(|| eyre::eyre!("the linker driver path is not valid UTF-8"))?
            .to_owned(),
        driver_version: run(driver, &["--version"])?,
        linker_version,
        crt_objects,
        sdk,
        deployment_target: std::env::var("MACOSX_DEPLOYMENT_TARGET").ok(),
    };
    Ok((identity, pins))
}

/// Bind a Windows link to the MSVC/LLVM linker, toolset, SDK, and CRT import
/// libraries selected by the developer environment.
fn probe_windows(linker: &Path) -> Result<LinkerIdentity> {
    let is_lld = linker
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.to_ascii_lowercase().starts_with("lld-link"));
    let linker_report = run_allowing_status(linker, if is_lld { &["--version"] } else { &["/?"] })?;
    if !is_lld && !linker_report.contains("Microsoft (R) Incremental Linker") {
        bail!(
            "{} is not the MSVC linker, so the link cannot be identified",
            linker.display()
        );
    }
    let linker_version = linker_report
        .lines()
        .find(|line| !line.trim().is_empty())
        .unwrap_or_default()
        .trim()
        .to_owned();
    let cl =
        msvc_tool("cl.exe").wrap_err("failed to find `cl.exe` for the MSVC toolchain identity")?;
    let compiler_version = run_allowing_status(&cl, &["/Bv"])?;
    let crt_objects = windows_crt_objects()?;
    let sdk = windows_sdk_identity()?;
    Ok(LinkerIdentity {
        driver: linker
            .to_str()
            .ok_or_else(|| eyre::eyre!("the linker path is not valid UTF-8"))?
            .to_owned(),
        driver_version: compiler_version,
        linker_version,
        crt_objects,
        sdk: Some(sdk),
        deployment_target: None,
    })
}

/// Locate one MSVC tool in the developer environment rustc itself uses.
///
/// GitHub's Windows runners do not consistently put `cl.exe` on the Git Bash
/// `PATH`, and that path may contain an unrelated GNU `link.exe`. Visual
/// Studio's environment variables name the selected toolset unambiguously.
fn msvc_tool(name: &str) -> Result<PathBuf> {
    let tools = std::env::var_os("VCToolsInstallDir")
        .map(PathBuf::from)
        .or_else(visual_studio_tools_dir);
    if let Some(root) = tools {
        let host = std::env::var("VSCMD_ARG_HOST_ARCH")
            .ok()
            .filter(|value| !value.is_empty())
            .unwrap_or_else(native_msvc_arch);
        let target = selected_msvc_arch();
        let candidate = root
            .join("bin")
            .join(format!("Host{host}"))
            .join(target)
            .join(name);
        if candidate.is_file() {
            return Ok(candidate);
        }
    }
    Ok(which::which(name)?)
}

fn selected_msvc_arch() -> String {
    std::env::var("VSCMD_ARG_TGT_ARCH")
        .ok()
        .filter(|value| !value.is_empty())
        .unwrap_or_else(native_msvc_arch)
}

/// Ask Visual Studio Installer which MSVC toolset rustc will use when no
/// developer-shell environment has been exported.
fn visual_studio_tools_dir() -> Option<PathBuf> {
    if !cfg!(windows) {
        return None;
    }
    let program_files =
        std::env::var_os("ProgramFiles(x86)").or_else(|| std::env::var_os("ProgramFiles"))?;
    let vswhere = PathBuf::from(program_files)
        .join("Microsoft Visual Studio")
        .join("Installer")
        .join("vswhere.exe");
    let output = Command::new(vswhere)
        .args([
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-property",
            "installationPath",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let installation = String::from_utf8(output.stdout).ok()?;
    let installation = PathBuf::from(installation.trim());
    let version = std::fs::read_to_string(
        installation.join("VC/Auxiliary/Build/Microsoft.VCToolsVersion.default.txt"),
    )
    .ok()?;
    Some(installation.join("VC/Tools/MSVC").join(version.trim()))
}

fn native_msvc_arch() -> String {
    match std::env::consts::ARCH {
        "x86_64" => "x64",
        "x86" => "x86",
        "aarch64" => "arm64",
        other => other,
    }
    .to_owned()
}

fn run_allowing_status(program: &Path, arguments: &[&str]) -> Result<String> {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .wrap_err_with(|| format!("failed to run {}", program.display()))?;
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    let reported = text.trim();
    if reported.is_empty() {
        bail!("{} {arguments:?} reported nothing", program.display());
    }
    Ok(reported.to_owned())
}

fn windows_sdk_identity() -> Result<String> {
    let mut values = ["VCToolsVersion", "WindowsSDKVersion", "UCRTVersion"]
        .into_iter()
        .filter_map(|name| {
            std::env::var(name)
                .ok()
                .filter(|value| !value.is_empty())
                .map(|value| format!("{name}={value}"))
        })
        .collect::<Vec<_>>();
    if !values
        .iter()
        .any(|value| value.starts_with("VCToolsVersion="))
        && let Some(version) = std::env::var_os("VCToolsInstallDir")
            .map(PathBuf::from)
            .or_else(visual_studio_tools_dir)
            .and_then(|path| path.file_name().map(|name| name.to_owned()))
    {
        values.push(format!("VCToolsVersion={}", version.to_string_lossy()));
    }
    if !values
        .iter()
        .any(|value| value.starts_with("WindowsSDKVersion="))
        && let Some((_, version)) = windows_sdk_root_and_version()
    {
        values.push(format!("WindowsSDKVersion={version}"));
    }
    if values.len() < 2 {
        bail!("the MSVC toolset and Windows SDK versions could not be identified");
    }
    Ok(values.join("; "))
}

#[cfg(test)]
fn windows_sdk_identity_for(lookup: impl Fn(&str) -> Option<String>) -> Result<String> {
    let values = ["VCToolsVersion", "WindowsSDKVersion", "UCRTVersion"]
        .into_iter()
        .filter_map(|name| {
            lookup(name)
                .filter(|value| !value.is_empty())
                .map(|value| format!("{name}={value}"))
        })
        .collect::<Vec<_>>();
    if values.len() < 2 {
        bail!("the MSVC toolset and Windows SDK versions could not be identified");
    }
    Ok(values.join("; "))
}

fn windows_crt_objects() -> Result<BTreeMap<String, CacheDigest>> {
    let mut directories = std::env::var_os("LIB")
        .map(|value| std::env::split_paths(&value).collect::<Vec<_>>())
        .unwrap_or_default();
    let arch = selected_msvc_arch();
    if let Some(tools) = std::env::var_os("VCToolsInstallDir")
        .map(PathBuf::from)
        .or_else(visual_studio_tools_dir)
    {
        directories.push(tools.join("lib").join(&arch));
    }
    if let Some((sdk, version)) = windows_sdk_root_and_version() {
        directories.push(sdk.join("Lib").join(version).join("ucrt").join(&arch));
    }
    windows_crt_objects_in(&directories)
}

fn windows_sdk_root_and_version() -> Option<(PathBuf, String)> {
    let root = std::env::var_os("WindowsSdkDir")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("ProgramFiles(x86)")
                .or_else(|| std::env::var_os("ProgramFiles"))
                .map(PathBuf::from)
                .map(|path| path.join("Windows Kits/10"))
        })?;
    let version = std::env::var("WindowsSDKVersion")
        .ok()
        .map(|version| version.trim_matches(['/', '\\']).to_owned())
        .filter(|version| !version.is_empty())
        .or_else(|| {
            let mut versions = std::fs::read_dir(root.join("Lib"))
                .ok()?
                .filter_map(Result::ok)
                .filter(|entry| entry.path().join("ucrt").is_dir())
                .filter_map(|entry| entry.file_name().into_string().ok())
                .collect::<Vec<_>>();
            versions.sort();
            versions.pop()
        })?;
    Some((root, version))
}

fn windows_crt_objects_in(directories: &[PathBuf]) -> Result<BTreeMap<String, CacheDigest>> {
    let names = [
        "libcmt.lib",
        "libcmtd.lib",
        "msvcrt.lib",
        "msvcrtd.lib",
        "vcruntime.lib",
        "vcruntimed.lib",
        "ucrt.lib",
        "ucrtd.lib",
    ];
    let mut resolved = BTreeMap::<String, CacheDigest>::new();
    for name in names {
        if let Some(path) = directories
            .iter()
            .map(|dir| dir.join(name))
            .find(|path| path.is_file())
        {
            let digest = CacheDigest::blake3_file(&path)
                .wrap_err_with(|| format!("failed to hash CRT library {}", path.display()))?;
            resolved.insert(name.into(), digest);
        }
    }
    if !resolved.keys().any(|name| name.starts_with("vcruntime"))
        || !resolved.keys().any(|name| name.starts_with("ucrt"))
    {
        bail!("the MSVC and Universal CRT libraries could not both be identified");
    }
    Ok(resolved)
}

/// Resolve a `-fuse-ld=<name>` selection to the linker binary the driver
/// will invoke. The driver answers from its own search path first, which
/// covers COMPILER_PATH and toolchain-internal linkers; a name it does not
/// know falls back to PATH. An absolute selection names the linker directly.
fn resolve_fuse_ld(driver: &Path, selection: &str, search: Option<&SearchDirs>) -> Result<Located> {
    if Path::new(selection).is_absolute() {
        return Ok(Located::named(PathBuf::from(selection)));
    }
    let name = format!("ld.{selection}");
    let argument = format!("-print-prog-name={name}");
    let printed = run(driver, &[argument.as_str()])
        .wrap_err_with(|| format!("the linker driver named nothing for `{name}`"))?;
    let candidate = PathBuf::from(&printed);
    let printed = if candidate.is_absolute() && candidate.exists() {
        candidate
    } else {
        PathBuf::from(&name)
    };
    Located::program(OsStr::new(&name), &printed, search).wrap_err_with(|| {
        format!(
            "`-fuse-ld={selection}` selects `{name}`, which neither the driver nor PATH provides"
        )
    })
}

/// Version of the linker the driver selects, as opposed to the driver itself,
/// and the pins that say which linker that was.
///
/// ld reports through stderr on some platforms and stdout on others, so both
/// are read; only the first line is kept, since later ones list supported
/// emulations that say nothing about the version.
fn linker_version(
    driver: &Path,
    fuse_ld: Option<&Located>,
    search: Option<&SearchDirs>,
) -> Result<(String, Pins)> {
    if let Some(located) = fuse_ld {
        let program = located.path.as_path();
        // Already resolved to the binary the driver invokes; pin both its
        // path and its version line: on content-addressed toolchains the
        // path alone identifies the build, and elsewhere the version line
        // names what a path cannot.
        let output = Command::new(program)
            .arg("-v")
            .output()
            .wrap_err_with(|| format!("failed to query the linker {}", program.display()))?;
        let combined = if output.stdout.is_empty() {
            output.stderr
        } else {
            output.stdout
        };
        let text = String::from_utf8_lossy(&combined);
        let version = text.lines().next().unwrap_or_default().trim();
        if version.is_empty() {
            bail!("{} reported no version", program.display());
        }
        return Ok((
            format!("{}: {version}", program.display()),
            located.pins.clone(),
        ));
    }
    // Asked of the driver rather than resolved from PATH: the `ld` a shell
    // would find is not necessarily the one this driver invokes, and a key
    // naming the wrong linker is worse than no key at all. A driver that
    // answers with a bare name is saying it would search PATH itself, so
    // the same search here names the file it would run.
    let named = PathBuf::from(
        run(driver, &["-print-prog-name=ld"]).wrap_err("the linker driver named no linker")?,
    );
    let located = Located::program(OsStr::new("ld"), &named, search)
        .wrap_err_with(|| format!("failed to find the linker `{}`", named.display()))?;
    let linker = located.path.as_path();
    let output = Command::new(linker)
        .arg("-v")
        .output()
        .wrap_err_with(|| format!("failed to query the linker {}", linker.display()))?;
    let combined = if output.stdout.is_empty() {
        output.stderr
    } else {
        output.stdout
    };
    let text = String::from_utf8_lossy(&combined);
    let version = text.lines().next().unwrap_or_default().trim();
    if version.is_empty() {
        bail!("{} reported no version", linker.display());
    }
    Ok((version.to_owned(), located.pins))
}

/// Hash the startup objects and libc the driver resolves.
///
/// A probe that does not resolve is left out of the map, so a host that
/// resolves a different set keys differently. That alone is not enough: two
/// hosts failing the *same* probe would agree on a key without ever pinning
/// what that probe stood for. So the inputs a link cannot be described without
/// -- a startup object and a libc -- have to resolve, and a host where neither
/// does gets no identity and no cached link.
fn crt_objects(
    driver: &Path,
    search: Option<&SearchDirs>,
) -> Result<(BTreeMap<String, CacheDigest>, Pins)> {
    let placed = std::cell::RefCell::new(Pins::default());
    let objects = probe_files(&file_probes(), |name| {
        let resolved = run(driver, &[&format!("-print-file-name={name}")]).ok()?;
        let path = PathBuf::from(resolved.trim());
        // The driver echoes the name back when it cannot place it.
        if !path.is_absolute() {
            return None;
        }
        // Described before it is hashed, so the pin says what was hashed,
        // along with every library directory the driver looked in first.
        let mut placed = placed.borrow_mut();
        match search {
            Some(search) => pin_search(&mut placed, OsStr::new(name), &path, &search.libraries),
            None => placed.0 = None,
        }
        Some(path)
    })?;
    Ok((objects, placed.into_inner()))
}

/// Resolve each probe, hash what came back, and insist on the ones a key
/// cannot describe a link without.
fn probe_files(
    probes: &FileProbes,
    place: impl Fn(&str) -> Option<PathBuf>,
) -> Result<BTreeMap<String, CacheDigest>> {
    let resolved = probes
        .startup
        .iter()
        .chain(probes.libc)
        .chain(probes.rest)
        .filter_map(|name| {
            let digest = CacheDigest::blake3_file(&place(name)?).ok()?;
            Some(((*name).to_owned(), digest))
        })
        .collect::<BTreeMap<_, _>>();
    for (required, what) in [(probes.startup, "startup object"), (probes.libc, "libc")] {
        if !required.is_empty() && !required.iter().any(|name| resolved.contains_key(*name)) {
            bail!("the linker driver resolved no {what}, so its links cannot be identified");
        }
    }
    Ok(resolved)
}

/// Identity of the SDK a link builds against, where the platform has one.
///
/// The build version is what changes when Apple ships new libraries under an
/// unchanged SDK version, so it is the half that matters most here. A host that
/// cannot report it gets no identity rather than one that omits the SDK: two
/// such hosts would otherwise agree on a key while linking against different
/// system libraries.
/// Written for every platform and gated with `cfg!` rather than `#[cfg]`, for
/// the same reason as the probe tables: code only one platform compiles is
/// code only that platform's CI can find a mistake in.
fn sdk_identity() -> Result<Option<String>> {
    sdk_identity_for(std::env::var("SDKROOT").ok())
}

/// Split from the environment it usually reads so that a test can ask about an
/// SDK without setting a variable every other test in the process would see.
fn sdk_identity_for(root: Option<String>) -> Result<Option<String>> {
    if !cfg!(target_os = "macos") {
        return Ok(None);
    }
    let describe = || {
        // Every question is asked of the SDK the link will actually use, which
        // `SDKROOT` names when it is set. Asking for `macosx` regardless would
        // report the default SDK's version beside another SDK's path, so the
        // key would describe an SDK no link was made against.
        let sdk = root.as_deref().unwrap_or("macosx");
        let version = xcrun(&["--sdk", sdk, "--show-sdk-version"])?;
        let build = xcrun(&["--sdk", sdk, "--show-sdk-build-version"])?;
        let path = match &root {
            Some(root) => root.clone(),
            None => xcrun(&["--sdk", sdk, "--show-sdk-path"])?,
        };
        Some(format!("{path} {version} ({build})"))
    };
    describe().map(Some).ok_or_else(|| {
        eyre::eyre!("the macOS SDK could not be identified, so its links cannot be either")
    })
}

fn xcrun(arguments: &[&str]) -> Option<String> {
    let output = Command::new("xcrun").args(arguments).output().ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn run(program: &Path, arguments: &[&str]) -> Result<String> {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .wrap_err_with(|| format!("failed to run {}", program.display()))?;
    if !output.status.success() {
        bail!(
            "{} {arguments:?} failed: {}",
            program.display(),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let reported = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    // A probe that answers with nothing describes nothing. Letting it through
    // would put an empty string in the key, which every host that failed the
    // same way would agree on.
    if reported.is_empty() {
        bail!("{} {arguments:?} reported nothing", program.display());
    }
    Ok(reported)
}

#[cfg(test)]
#[path = "linker_tests.rs"]
mod tests;
