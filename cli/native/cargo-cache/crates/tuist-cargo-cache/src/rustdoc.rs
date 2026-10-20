//! Cache adapter for Cargo's rustdoc invocations.

use crate::materialize::{
    find_blobs, read_canonical_blob, read_verified_blob, record_action_hit, resolve_executable,
};
use crate::session;
use crate::util::duration_ns;
use eyre::{Context as _, Result, bail};
use serde::Serialize;
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::fs::File;
use std::io::{Read as _, Write as _};
use std::path::{Component, Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::Instant;
use tuist_cargo_cache_core::{
    AgentRequest, AgentResponse, CacheDigest, CacheDirectory, CacheFileNode, RemoteActionResult,
    RustcMetadata, canonical_json,
};

const ARCHIVE_MAGIC: &[u8] = b"tuist_cargo_cache-rustdoc-v1\0";
const REMOVED_ENVIRONMENT: &[&str] = &[
    "CARGO_MAKEFLAGS",
    "TUIST_CARGO_CACHE_BUILD",
    "TUIST_CARGO_CACHE_CC_SHIM_COMPILERS",
    "TUIST_CARGO_CACHE_LEARNED_INCREMENTAL",
    "TUIST_CARGO_CACHE_REAL_CC",
    "TUIST_CARGO_CACHE_REAL_CXX",
    "TUIST_CARGO_CACHE_REAL_RUSTDOC",
    "TUIST_CARGO_CACHE_SCHED_DIR",
    "TUIST_CARGO_CACHE_SCHED_PRIORITY",
    "TUIST_CARGO_CACHE_SCHED_SLOT_BYTES",
    "TUIST_CARGO_CACHE_SCHED_SLOTS",
    "TUIST_CARGO_CACHE_SHARE_OUT_DIR",
    "TUIST_CARGO_CACHE_SOCKET",
    "TUIST_CARGO_CACHE_STAGING_DIR",
    "TUIST_CARGO_CACHE_VERIFY",
    "RUSTC_WRAPPER",
    "RUSTC_BOOTSTRAP",
    "RUSTDOC",
];
const HOST_ENVIRONMENT: &[&str] = &[
    "_",
    "CI",
    "CARGO_HOME",
    "CODEBUILD_BUILD_ID",
    "COMSPEC",
    "GITHUB_ACTIONS",
    "HOME",
    "HOSTNAME",
    "NUMBER_OF_PROCESSORS",
    "OLDPWD",
    "PATH",
    "PATHEXT",
    "PWD",
    "RUSTUP_HOME",
    "SHLVL",
    "SYSTEMROOT",
    "TEMP",
    "TMP",
    "TMPDIR",
    "USER",
    "USERDOMAIN",
    "USERNAME",
    "USERPROFILE",
];
const HOST_ENVIRONMENT_PREFIXES: &[&str] = &[
    "ACTIONS_",
    "BUILDKITE_",
    "CIRCLE_",
    "GITHUB_",
    "JENKINS_",
    "RUNNER_",
    "TEAMCITY_",
    "TF_BUILD",
];

#[derive(Serialize)]
struct ActionDescriptor {
    adapter: &'static str,
    version: u8,
    rustdoc: String,
    arguments: Vec<String>,
    environment: BTreeMap<String, String>,
    inputs: BTreeMap<String, CacheDigest>,
}

struct Invocation {
    crate_name: String,
    output: PathBuf,
    manifest: PathBuf,
    arguments: Vec<OsString>,
}

struct CachedDocs {
    archive: PathBuf,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

#[derive(Default)]
struct InstalledDocs {
    files: u64,
    bytes: u64,
}

pub(crate) fn document(rustdoc: &OsStr, arguments: &[OsString]) -> Result<ExitCode> {
    let invocation = Invocation::parse(arguments)?;
    let action_bytes = action_descriptor(rustdoc, &invocation)?;
    let action = CacheDigest::blake3(&action_bytes);
    if let Some(cached) = restore(&action, &action_bytes)? {
        let started = Instant::now();
        let installed = install_archive(&cached.archive, &invocation)?;
        finalize(rustdoc, &invocation)?;
        record_action_hit(
            &action,
            tuist_cargo_cache_core::RestoreStats {
                duration_ns: duration_ns(started.elapsed()),
                output_files: installed.files,
                output_bytes: installed.bytes,
                copied_output_files: installed.files,
                copied_output_bytes: installed.bytes,
                ..Default::default()
            },
            &invocation.crate_name,
        );
        std::io::stdout().write_all(&cached.stdout)?;
        std::io::stderr().write_all(&cached.stderr)?;
        return Ok(ExitCode::SUCCESS);
    }

    let generated = tempfile::tempdir()?;
    let doc = generated.path().join("doc");
    let parts = generated.path().join("parts");
    std::fs::create_dir_all(&doc)?;
    std::fs::create_dir_all(&parts)?;
    let rewritten = invocation.rewritten(&doc, &parts);
    let started = Instant::now();
    let mut command = Command::new(rustdoc);
    command.args(&rewritten);
    prepare_command(&mut command);
    let output = command.output().wrap_err("failed to run rustdoc")?;
    let duration = duration_ns(started.elapsed());
    session::check_low_disk_after_compile();
    std::io::stdout().write_all(&output.stdout)?;
    std::io::stderr().write_all(&output.stderr)?;
    // Recorded before the failure check: the lookup above happened either way,
    // so a documentation build that fails is still a compilation the cache was
    // asked about and could not answer. Returning first left it out of the
    // session's accounting entirely.
    session::record_compiler_invocation("miss", Some(&invocation.crate_name), duration);
    if !output.status.success() {
        return Ok(ExitCode::from(
            u8::try_from(output.status.code().unwrap_or(1)).unwrap_or(1),
        ));
    }

    let archive = generated.path().join("rustdoc.archive");
    write_archive(&archive, &[(&doc, "doc"), (&parts, "parts")])?;
    install_archive(&archive, &invocation)?;
    finalize(rustdoc, &invocation)?;
    publish(
        &action,
        &action_bytes,
        &archive,
        &output.stdout,
        &output.stderr,
    )?;
    Ok(ExitCode::SUCCESS)
}

impl Invocation {
    fn parse(arguments: &[OsString]) -> Result<Self> {
        let arguments_utf8 = arguments
            .iter()
            .map(|arg| {
                arg.to_str()
                    .map(str::to_owned)
                    .ok_or_else(|| eyre::eyre!("rustdoc argument is not UTF-8"))
            })
            .collect::<Result<Vec<_>>>()?;
        if arguments_utf8.iter().any(|arg| {
            arg == "--test"
                || arg == "--check"
                || arg.starts_with("--merge")
                || arg.starts_with("--parts-out-dir")
                || arg.starts_with("--include-parts-dir")
                || arg.starts_with("--emit")
                || arg.starts_with("--output-format")
                || arg == "-Zunstable-options"
        }) {
            bail!("rustdoc invocation owns its execution or merge mode");
        }
        let mut output = None;
        let mut index = 0;
        while index < arguments_utf8.len() {
            let arg = &arguments_utf8[index];
            if matches!(arg.as_str(), "-o" | "--out-dir" | "--output") {
                index += 1;
                output = arguments_utf8.get(index).map(PathBuf::from);
            } else if let Some(value) = arg
                .strip_prefix("--out-dir=")
                .or_else(|| arg.strip_prefix("--output="))
            {
                output = Some(PathBuf::from(value));
            }
            index += 1;
        }
        let output = output.ok_or_else(|| eyre::eyre!("rustdoc has no output directory"))?;
        let output = std::path::absolute(output)?;
        let crate_name = std::env::var("CARGO_CRATE_NAME")
            .or_else(|_| std::env::var("CARGO_PKG_NAME"))
            .wrap_err("rustdoc invocation has no Cargo crate name")?;
        let manifest = std::env::var_os("CARGO_MANIFEST_DIR")
            .map(PathBuf::from)
            .ok_or_else(|| eyre::eyre!("rustdoc invocation has no Cargo manifest directory"))?;
        Ok(Self {
            crate_name,
            output,
            manifest: std::path::absolute(manifest)?,
            arguments: arguments.to_vec(),
        })
    }

    fn rewritten(&self, output: &Path, parts: &Path) -> Vec<OsString> {
        let mut rewritten = Vec::new();
        let mut skip_output = false;
        for argument in &self.arguments {
            if skip_output {
                skip_output = false;
                continue;
            }
            let text = argument.to_string_lossy();
            if matches!(text.as_ref(), "-o" | "--out-dir" | "--output") {
                skip_output = true;
                continue;
            }
            if text.starts_with("--out-dir=") || text.starts_with("--output=") {
                continue;
            }
            rewritten.push(argument.clone());
        }
        rewritten.extend([
            "-o".into(),
            output.as_os_str().into(),
            "-Zunstable-options".into(),
            "--merge=none".into(),
            "--parts-out-dir".into(),
            parts.as_os_str().into(),
        ]);
        rewritten
    }

    fn parts_root(&self) -> Result<PathBuf> {
        Ok(self
            .output
            .parent()
            .ok_or_else(|| eyre::eyre!("rustdoc output has no parent"))?
            .join(".tuist_cargo_cache-rustdoc-parts"))
    }
}

fn action_descriptor(rustdoc: &OsStr, invocation: &Invocation) -> Result<Vec<u8>> {
    let rustdoc = resolve_executable(rustdoc)?;
    let identity = Command::new(&rustdoc).arg("-Vv").output()?;
    if !identity.status.success() {
        bail!("rustdoc identity query failed");
    }
    let mappings = path_mappings(invocation);
    let arguments = invocation
        .arguments
        .iter()
        .map(|arg| normalize(&arg.to_string_lossy(), &mappings))
        .collect();
    let environment = action_environment(std::env::vars(), &mappings);
    let mut inputs = BTreeMap::new();
    let target = std::env::var_os(session::TARGET_DIR_ENV).map(PathBuf::from);
    let workspace = std::env::var_os(session::WORKSPACE_ROOT_ENV).map(PathBuf::from);
    let (input_root, portable_root) = workspace
        .as_deref()
        .filter(|workspace| invocation.manifest.starts_with(workspace))
        .map_or((invocation.manifest.as_path(), "${package}"), |workspace| {
            (workspace, "${workspace}")
        });
    collect_tree(
        input_root,
        input_root,
        portable_root,
        target.as_deref(),
        &mut inputs,
    )?;
    collect_argument_inputs(&invocation.arguments, &mappings, &mut inputs)?;
    canonical_json(&ActionDescriptor {
        adapter: "rustdoc",
        version: 1,
        rustdoc: String::from_utf8(identity.stdout)?,
        arguments,
        environment,
        inputs,
    })
}

fn action_environment(
    environment: impl IntoIterator<Item = (String, String)>,
    mappings: &[(String, String)],
) -> BTreeMap<String, String> {
    environment
        .into_iter()
        .filter(|(name, _)| {
            !name.starts_with("TUIST_CARGO_CACHE_")
                && !REMOVED_ENVIRONMENT.contains(&name.as_str())
                && !HOST_ENVIRONMENT.contains(&name.as_str())
                && !HOST_ENVIRONMENT_PREFIXES
                    .iter()
                    .any(|prefix| name.starts_with(prefix))
        })
        .map(|(name, value)| (name, normalize(&value, mappings)))
        .collect()
}

fn path_mappings(invocation: &Invocation) -> Vec<(String, String)> {
    let mut roots = Vec::new();
    for (name, value) in [
        ("target", std::env::var_os(session::TARGET_DIR_ENV)),
        ("workspace", std::env::var_os(session::WORKSPACE_ROOT_ENV)),
    ] {
        if let Some(value) = value {
            roots.push((
                PathBuf::from(value).to_string_lossy().into_owned(),
                format!("${{{name}}}"),
            ));
        }
    }
    roots.push((
        invocation.manifest.to_string_lossy().into_owned(),
        "${package}".into(),
    ));
    roots.sort_by_key(|root| std::cmp::Reverse(root.0.len()));
    roots
}

fn normalize(value: &str, mappings: &[(String, String)]) -> String {
    mappings
        .iter()
        .fold(value.to_owned(), |value, (root, key)| {
            value.replace(root, key)
        })
}

fn collect_tree(
    root: &Path,
    directory: &Path,
    portable_root: &str,
    excluded: Option<&Path>,
    inputs: &mut BTreeMap<String, CacheDigest>,
) -> Result<()> {
    for entry in std::fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        let name = entry.file_name();
        let file_type = entry.file_type()?;
        // Managed target views are symlinks, so exclude generated output by
        // name and configured location before applying the conservative source
        // symlink check.
        if (name == "target" && (file_type.is_dir() || file_type.is_symlink()))
            || excluded.is_some_and(|excluded| path == excluded || path.starts_with(excluded))
        {
            continue;
        }
        if file_type.is_symlink() {
            bail!(
                "rustdoc input tree contains a symbolic link: {}",
                path.display()
            );
        }
        if path.is_dir() {
            if name != ".git" {
                collect_tree(root, &path, portable_root, excluded, inputs)?;
            }
        } else if path.is_file() {
            let relative = path.strip_prefix(root)?;
            inputs.insert(
                format!("{portable_root}/{}", relative.to_string_lossy()),
                CacheDigest::blake3_file(&path)?,
            );
        }
    }
    // `root` is used to establish the portable spelling above; keeping this
    // assertion here also refuses a symlink walk that escaped the package.
    if !directory.starts_with(root) {
        bail!("package input escaped its manifest directory");
    }
    Ok(())
}

fn collect_argument_inputs(
    arguments: &[OsString],
    mappings: &[(String, String)],
    inputs: &mut BTreeMap<String, CacheDigest>,
) -> Result<()> {
    const PATH_FLAGS: &[&str] = &[
        "--extend-css",
        "--index-page",
        "--markdown-css",
        "--html-in-header",
        "--html-before-content",
        "--html-after-content",
        "--theme",
        "--with-examples",
    ];
    let mut index = 0;
    while index < arguments.len() {
        let text = arguments[index].to_string_lossy();
        let path = if text == "--extern" {
            index += 1;
            let value = arguments
                .get(index)
                .and_then(|value| value.to_str())
                .ok_or_else(|| eyre::eyre!("rustdoc --extern has no UTF-8 value"))?;
            Some(
                value
                    .split_once('=')
                    .map(|(_, path)| path)
                    .ok_or_else(|| eyre::eyre!("rustdoc --extern has no artifact"))?,
            )
        } else if let Some(value) = text.strip_prefix("--extern=") {
            Some(
                value
                    .split_once('=')
                    .map(|(_, path)| path)
                    .ok_or_else(|| eyre::eyre!("rustdoc --extern has no artifact"))?,
            )
        } else if PATH_FLAGS.contains(&text.as_ref()) {
            index += 1;
            Some(
                arguments
                    .get(index)
                    .and_then(|value| value.to_str())
                    .ok_or_else(|| eyre::eyre!("rustdoc path flag has no UTF-8 value"))?,
            )
        } else {
            PATH_FLAGS
                .iter()
                .find_map(|flag| text.strip_prefix(&format!("{flag}=")))
        };
        if let Some(path) = path {
            let path = Path::new(path);
            if !path.is_file() {
                bail!("rustdoc input is not a file: {}", path.display());
            }
            inputs.insert(
                normalize(&std::path::absolute(path)?.to_string_lossy(), mappings),
                CacheDigest::blake3_file(path)?,
            );
        }
        index += 1;
    }
    Ok(())
}

fn restore(action: &CacheDigest, action_bytes: &[u8]) -> Result<Option<CachedDocs>> {
    let response = session::request_agent(&[AgentRequest::FindActionResult {
        action: action.clone(),
    }])?
    .into_iter()
    .next();
    let Some(AgentResponse::ActionResult {
        result: Some(result),
    }) = response
    else {
        return Ok(None);
    };
    if result.version != 1 || result.action != *action {
        bail!("cached rustdoc result has an invalid identity");
    }
    let metadata = result
        .metadata
        .ok_or_else(|| eyre::eyre!("rustdoc metadata is missing"))?;
    let directory = result
        .output_root
        .ok_or_else(|| eyre::eyre!("rustdoc output is missing"))?;
    let roots = find_blobs(&[action.clone(), metadata.clone(), directory.clone()])?;
    if read_verified_blob(&roots[0], action, "rustdoc action")? != action_bytes {
        bail!("cached rustdoc action descriptor does not match");
    }
    let metadata: RustcMetadata = read_canonical_blob(&roots[1], &metadata, "rustdoc metadata")?;
    if metadata.version != 1 || metadata.kind != "rustc" {
        bail!("cached rustdoc metadata is unsupported");
    }
    let directory: CacheDirectory = read_canonical_blob(&roots[2], &directory, "rustdoc output")?;
    if directory.version != 1
        || !directory.directories.is_empty()
        || !directory.symlinks.is_empty()
        || directory.files.len() != 1
        || directory.files[0].name != "rustdoc.archive"
    {
        bail!("cached rustdoc output directory is invalid");
    }
    let node = &directory.files[0];
    let blobs = find_blobs(&[
        node.digest.clone(),
        metadata.stdout.clone(),
        metadata.stderr.clone(),
    ])?;
    let stdout = read_verified_blob(&blobs[1], &metadata.stdout, "rustdoc stdout")?;
    let stderr = read_verified_blob(&blobs[2], &metadata.stderr, "rustdoc stderr")?;
    Ok(Some(CachedDocs {
        archive: blobs[0].clone(),
        stdout,
        stderr,
    }))
}

fn publish(
    action: &CacheDigest,
    action_bytes: &[u8],
    archive: &Path,
    stdout: &[u8],
    stderr: &[u8],
) -> Result<()> {
    let staging = tempfile::tempdir()?;
    let stage = |name: &str, bytes: &[u8]| -> Result<(CacheDigest, PathBuf)> {
        let path = staging.path().join(name);
        std::fs::write(&path, bytes)?;
        Ok((CacheDigest::blake3(bytes), path))
    };
    let action_blob = stage("action", action_bytes)?;
    let stdout = stage("stdout", stdout)?;
    let stderr = stage("stderr", stderr)?;
    let archive_digest = CacheDigest::blake3_file(archive)?;
    let metadata_bytes = canonical_json(&RustcMetadata {
        version: 1,
        // This is the common compiler-output metadata envelope. Keeping its
        // protocol kind lets existing agents and collectors follow the two
        // diagnostic blobs without teaching the wire format a second
        // structurally identical record.
        kind: "rustc".into(),
        stdout: stdout.0.clone(),
        stderr: stderr.0.clone(),
    })?;
    let metadata = stage("metadata", &metadata_bytes)?;
    let directory_bytes = canonical_json(&CacheDirectory {
        directories: Vec::new(),
        files: vec![CacheFileNode {
            digest: archive_digest.clone(),
            executable: false,
            mode: 0o644,
            name: "rustdoc.archive".into(),
        }],
        symlinks: Vec::new(),
        version: 1,
    })?;
    let directory = stage("directory", &directory_bytes)?;
    let mut requests = vec![
        AgentRequest::StoreBlob {
            digest: action_blob.0,
            source: action_blob.1,
        },
        AgentRequest::StoreBlob {
            digest: stdout.0,
            source: stdout.1,
        },
        AgentRequest::StoreBlob {
            digest: stderr.0,
            source: stderr.1,
        },
        AgentRequest::StoreBlob {
            digest: archive_digest,
            source: archive.to_path_buf(),
        },
        AgentRequest::StoreBlob {
            digest: metadata.0.clone(),
            source: metadata.1,
        },
        AgentRequest::StoreBlob {
            digest: directory.0.clone(),
            source: directory.1,
        },
        AgentRequest::StoreActionResult {
            result: RemoteActionResult {
                action: action.clone(),
                metadata: Some(metadata.0),
                output_root: Some(directory.0),
                version: 1,
            },
        },
    ];
    for response in session::request_agent(&requests)? {
        if let AgentResponse::Error { message } = response {
            bail!(message);
        }
    }
    requests.clear();
    Ok(())
}

fn write_archive(path: &Path, roots: &[(&Path, &str)]) -> Result<()> {
    let mut files = Vec::new();
    for (root, prefix) in roots {
        collect_archive_files(root, root, prefix, &mut files)?;
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));
    let mut output = File::create(path)?;
    output.write_all(ARCHIVE_MAGIC)?;
    output.write_all(&(files.len() as u64).to_le_bytes())?;
    for (name, source) in files {
        let bytes = name.as_bytes();
        let size = std::fs::metadata(&source)?.len();
        output.write_all(&(bytes.len() as u32).to_le_bytes())?;
        output.write_all(bytes)?;
        output.write_all(&size.to_le_bytes())?;
        std::io::copy(&mut File::open(source)?, &mut output)?;
    }
    Ok(())
}

fn collect_archive_files(
    root: &Path,
    dir: &Path,
    prefix: &str,
    files: &mut Vec<(String, PathBuf)>,
) -> Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_archive_files(root, &path, prefix, files)?;
        } else if path.is_file() {
            let relative = path
                .strip_prefix(root)?
                .to_string_lossy()
                .replace('\\', "/");
            files.push((format!("{prefix}/{relative}"), path));
        }
    }
    Ok(())
}

fn install_archive(archive: &Path, invocation: &Invocation) -> Result<InstalledDocs> {
    let mut input = File::open(archive)?;
    let mut magic = vec![0; ARCHIVE_MAGIC.len()];
    input.read_exact(&mut magic)?;
    if magic != ARCHIVE_MAGIC {
        bail!("cached rustdoc archive has an invalid header");
    }
    let count = read_u64(&mut input)?;
    if count > 1_000_000 {
        bail!("cached rustdoc archive has too many files");
    }
    let parts = invocation.parts_root()?.join(&invocation.crate_name);
    let mut installed = InstalledDocs::default();
    for _ in 0..count {
        let name_len = read_u32(&mut input)? as usize;
        if name_len > 1024 * 1024 {
            bail!("cached rustdoc path is too long");
        }
        let mut name = vec![0; name_len];
        input.read_exact(&mut name)?;
        let name = String::from_utf8(name)?;
        let relative = Path::new(&name);
        if relative
            .components()
            .any(|part| !matches!(part, Component::Normal(_)))
        {
            bail!("cached rustdoc path is unsafe");
        }
        let destination = if let Ok(path) = relative.strip_prefix("doc") {
            invocation.output.join(path)
        } else if let Ok(path) = relative.strip_prefix("parts") {
            parts.join(path)
        } else {
            bail!("cached rustdoc path has an unknown root");
        };
        let size = read_u64(&mut input)?;
        if let Some(parent) = destination.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let temporary =
            destination.with_extension(format!("tuist_cargo_cache-{}", std::process::id()));
        let mut output = File::create(&temporary)?;
        let copied = std::io::copy(&mut (&mut input).take(size), &mut output)?;
        if copied != size {
            bail!("cached rustdoc archive is truncated");
        }
        match std::fs::rename(&temporary, &destination) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                std::fs::remove_file(&destination)?;
                std::fs::rename(temporary, destination)?;
            }
            Err(error) => return Err(error.into()),
        }
        installed.files = installed.files.saturating_add(1);
        installed.bytes = installed.bytes.saturating_add(size);
    }
    Ok(installed)
}

fn read_u64(input: &mut File) -> Result<u64> {
    let mut bytes = [0; 8];
    input.read_exact(&mut bytes)?;
    Ok(u64::from_le_bytes(bytes))
}

fn read_u32(input: &mut File) -> Result<u32> {
    let mut bytes = [0; 4];
    input.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}

fn finalize(rustdoc: &OsStr, invocation: &Invocation) -> Result<()> {
    std::fs::create_dir_all(&invocation.output)?;
    let parts_root = invocation.parts_root()?;
    std::fs::create_dir_all(&parts_root)?;
    let lock_path = parts_root.join("merge.lock");
    let mut lock = fslock::LockFile::open(&lock_path)?;
    lock.lock()?;
    let mut parts = std::fs::read_dir(&parts_root)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.is_dir())
        .collect::<Vec<_>>();
    parts.sort();
    let mut command = Command::new(rustdoc);
    command
        .args(["-Zunstable-options", "--merge=finalize", "-o"])
        .arg(&invocation.output);
    prepare_command(&mut command);
    command.args(finalize_arguments(&invocation.arguments));
    for part in parts {
        command.arg("--include-parts-dir").arg(part);
    }
    let status = command.status()?;
    lock.unlock()?;
    if !status.success() {
        bail!("rustdoc shared-output finalization failed");
    }
    Ok(())
}

fn prepare_command(command: &mut Command) {
    // These variables connect shims to their parent session or carry Cargo's
    // jobserver file descriptors. They are not user compile-time inputs and
    // would otherwise make every session's documentation key unique.
    for name in REMOVED_ENVIRONMENT {
        command.env_remove(name);
    }
    for name in std::env::vars_os()
        .filter_map(|(name, _)| name.into_string().ok())
        .filter(|name| name.starts_with("TUIST_CARGO_CACHE_"))
    {
        command.env_remove(name);
    }
    // Mergeable rustdoc output is still guarded by unstable-options on stable
    // toolchains. Scope the bootstrap escape hatch to this child; Cargo and
    // every compilation it launches remain untouched.
    command.env("RUSTC_BOOTSTRAP", "1");
}

fn finalize_arguments(arguments: &[OsString]) -> Vec<OsString> {
    const WITH_VALUE: &[&str] = &[
        "--resource-suffix",
        "--static-root-path",
        "--extend-css",
        "--index-page",
        "--markdown-css",
        "--html-in-header",
        "--html-before-content",
        "--html-after-content",
        "--default-theme",
        "--theme",
    ];
    const FLAGS: &[&str] = &["--enable-index-page", "--disable-minification"];
    let mut selected = Vec::new();
    let mut index = 0;
    while index < arguments.len() {
        let text = arguments[index].to_string_lossy();
        if WITH_VALUE.contains(&text.as_ref()) {
            if let Some(value) = arguments.get(index + 1) {
                selected.extend([arguments[index].clone(), value.clone()]);
                index += 1;
            }
        } else if WITH_VALUE
            .iter()
            .any(|name| text.starts_with(&format!("{name}=")))
            || FLAGS.contains(&text.as_ref())
        {
            selected.push(arguments[index].clone());
        }
        index += 1;
    }
    selected
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_environment_omits_host_identity_but_keeps_compile_inputs() {
        let environment = action_environment(
            [
                ("GITHUB_RUN_ID".into(), "123".into()),
                ("HOME".into(), "/home/one".into()),
                ("CARGO_PKG_VERSION".into(), "1.2.3".into()),
                ("DOCS_RS".into(), "1".into()),
            ],
            &[],
        );

        assert!(!environment.contains_key("GITHUB_RUN_ID"));
        assert!(!environment.contains_key("HOME"));
        assert_eq!(environment.get("CARGO_PKG_VERSION").unwrap(), "1.2.3");
        assert_eq!(environment.get("DOCS_RS").unwrap(), "1");
    }

    #[cfg(unix)]
    #[test]
    fn managed_target_symlinks_are_excluded_before_source_symlinks_are_rejected() {
        let package = tempfile::tempdir().unwrap();
        let managed = tempfile::tempdir().unwrap();
        std::fs::write(package.path().join("lib.rs"), "pub fn value() {}\n").unwrap();
        std::os::unix::fs::symlink(managed.path(), package.path().join("target")).unwrap();
        let mut inputs = BTreeMap::new();

        collect_tree(
            package.path(),
            package.path(),
            "${package}",
            Some(managed.path()),
            &mut inputs,
        )
        .unwrap();

        assert_eq!(inputs.len(), 1);
        assert!(inputs.contains_key("${package}/lib.rs"));
    }

    #[test]
    fn archive_round_trip_installs_crate_pages_and_parts() {
        let generated = tempfile::tempdir().unwrap();
        let doc = generated.path().join("doc");
        let parts = generated.path().join("parts");
        std::fs::create_dir_all(doc.join("widget")).unwrap();
        std::fs::create_dir_all(&parts).unwrap();
        std::fs::write(doc.join("widget/index.html"), b"docs").unwrap();
        std::fs::write(parts.join("lib.json"), b"parts").unwrap();
        let archive = generated.path().join("archive");
        write_archive(&archive, &[(&doc, "doc"), (&parts, "parts")]).unwrap();

        let destination = tempfile::tempdir().unwrap();
        let invocation = Invocation {
            crate_name: "widget".into(),
            output: destination.path().join("doc"),
            manifest: destination.path().into(),
            arguments: Vec::new(),
        };
        install_archive(&archive, &invocation).unwrap();

        assert_eq!(
            std::fs::read(invocation.output.join("widget/index.html")).unwrap(),
            b"docs"
        );
        assert_eq!(
            std::fs::read(invocation.parts_root().unwrap().join("widget/lib.json")).unwrap(),
            b"parts"
        );
    }

    #[test]
    fn finalize_keeps_only_shared_output_arguments() {
        let arguments = vec![
            "--crate-name".into(),
            "widget".into(),
            "--resource-suffix=abc".into(),
            "--extend-css".into(),
            "theme.css".into(),
            "src/lib.rs".into(),
        ];
        assert_eq!(
            finalize_arguments(&arguments),
            vec![
                OsString::from("--resource-suffix=abc"),
                OsString::from("--extend-css"),
                OsString::from("theme.css"),
            ]
        );
    }
}
