use super::{
    ActionContext, ActionInput, Argument, BypassReason, MAX_NATIVE_INPUT_BYTES,
    MAX_PREDICTED_INPUTS, PathMapping, RustcInvocation, normalize_components,
};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
#[cfg(test)]
use tuist_cargo_cache_core::CacheDigest;
use tuist_cargo_cache_core::{
    FileDigestCache, FileDigestResolution, FileDigestScope, FileIdentity, FileSnapshot,
    RecordedFileDigest, digest_file, digest_file_validated,
};

/// A side-effect-minimized rustc invocation that emits only dependency data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DepInfoCommand {
    arguments: Vec<OsString>,
    output: PathBuf,
}

impl DepInfoCommand {
    /// Arguments for the real compiler, excluding the compiler executable.
    pub fn arguments(&self) -> &[OsString] {
        &self.arguments
    }

    /// Exact file the compiler must populate with dep-info.
    pub fn output(&self) -> &Path {
        &self.output
    }
}

/// The source and environment inputs reported by rustc's dep-info output.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RustcDepInfo {
    /// Source paths listed in the first dep-info dependency rule.
    pub files: Vec<PathBuf>,
    /// Environment inputs recorded by rustc `# env-dep:` lines.
    pub environment: BTreeMap<String, Option<String>>,
}

impl RustcDepInfo {
    /// Read and parse a dep-info file, treating missing or non-UTF-8 output as
    /// an explicit cache bypass.
    pub fn read(path: &Path) -> Result<Self, BypassReason> {
        let contents =
            std::fs::read_to_string(path).map_err(|error| BypassReason::DepInfoRead {
                path: path.to_path_buf(),
                message: error.to_string(),
            })?;
        Self::parse(&contents)
    }

    /// Parse rustc's Makefile-style dep-info format.
    ///
    /// This intentionally follows Cargo's parser contract: the first target
    /// rule contains all source dependencies, spaces are escaped with a
    /// trailing backslash on each token fragment, and `# env-dep:` records
    /// contain the environment observed by `env!` and `option_env!`.
    pub fn parse(contents: &str) -> Result<Self, BypassReason> {
        let mut files = BTreeSet::new();
        let mut environment = BTreeMap::new();
        let mut found_dependencies = false;

        for line in contents.lines() {
            if let Some(record) = line.strip_prefix("# env-dep:") {
                let (name, value) = record
                    .split_once('=')
                    .map_or((record, None), |(name, value)| (name, Some(value)));
                let name = unescape_environment(name)?;
                if name.is_empty() {
                    return Err(BypassReason::MalformedDepInfo(
                        "environment input has an empty name".into(),
                    ));
                }
                let value = value.map(unescape_environment).transpose()?;
                if environment
                    .insert(name.clone(), value.clone())
                    .is_some_and(|previous| previous != value)
                {
                    return Err(BypassReason::ConflictingEnvironment(name));
                }
                continue;
            }

            let Some(separator) = line.find(": ") else {
                continue;
            };
            if found_dependencies {
                continue;
            }
            found_dependencies = true;
            let mut fragments = line[separator + 2..].split_whitespace();
            while let Some(fragment) = fragments.next() {
                let mut file = fragment.to_string();
                while file.ends_with('\\') {
                    file.pop();
                    let continuation = fragments.next().ok_or_else(|| {
                        BypassReason::MalformedDepInfo(
                            "dependency path ends with an unterminated escape".into(),
                        )
                    })?;
                    file.push(' ');
                    file.push_str(continuation);
                }
                if file.is_empty() {
                    return Err(BypassReason::MalformedDepInfo(
                        "dependency path is empty".into(),
                    ));
                }
                files.insert(PathBuf::from(file));
            }
        }

        if !found_dependencies {
            return Err(BypassReason::MalformedDepInfo(
                "dependency rule is missing".into(),
            ));
        }
        if files.is_empty() {
            return Err(BypassReason::MalformedDepInfo(
                "dependency rule contains no inputs".into(),
            ));
        }
        Ok(Self {
            files: files.into_iter().collect(),
            environment,
        })
    }
}

/// A complete, content-addressed compiler input manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveredInputs {
    working_dir: PathBuf,
    /// Content-addressed compiler input files.
    pub inputs: Vec<ActionInput>,
    /// Environment inputs captured from dep-info.
    pub environment: BTreeMap<String, Option<String>>,
    /// What each input looked like on disk when its digest was established,
    /// index-aligned with `inputs`; `None` where the filesystem gave nothing to
    /// compare against later. Lets `verify` confirm an input by stat instead of
    /// by reading it again.
    identities: Vec<Option<FileIdentity>>,
    /// Inputs that entered only because they sit in a native search directory,
    /// not because dep-info or the invocation named them. They belong in a
    /// shared action key, but they are not the crate's own sources.
    native_only: BTreeSet<PathBuf>,
}

impl DiscoveredInputs {
    pub(crate) fn from_paths(
        working_dir: &Path,
        paths: BTreeSet<PathBuf>,
        environment: BTreeMap<String, Option<String>>,
        digests: &dyn FileDigestCache,
    ) -> Result<Self, BypassReason> {
        if !working_dir.is_absolute() {
            return Err(BypassReason::RelativeWorkingDirectory(
                working_dir.to_path_buf(),
            ));
        }
        let working_dir = normalize_components(working_dir);
        // Stat everything first: the identities drive one batched ledger
        // lookup, so an upstream rlib the session already hashed -- once, when
        // it was materialized or published -- is not read again by every crate
        // that links it. A file the filesystem reports no modification time
        // for gets no identity and is simply hashed.
        let mut identified = Vec::with_capacity(paths.len());
        for path in paths {
            let metadata = std::fs::metadata(&path).map_err(|error| BypassReason::InputRead {
                path: path.clone(),
                message: error.to_string(),
            })?;
            if !metadata.is_file() {
                return Err(BypassReason::InputRead {
                    path,
                    message: "input is not a regular file".into(),
                });
            }
            let identity = FileIdentity::for_digest_cache(&path, &metadata).map_err(|error| {
                BypassReason::InputRead {
                    path: path.clone(),
                    message: error.to_string(),
                }
            })?;
            identified.push((path, identity));
        }
        let queries = identified
            .iter()
            .filter_map(|(_, identity)| identity.clone())
            .collect::<Vec<_>>();
        let mut recorded = digests
            .resolve(FileDigestScope::Content, &queries)
            .into_iter();
        let mut inputs = Vec::with_capacity(identified.len());
        let mut identities = Vec::with_capacity(identified.len());
        let mut fresh = Vec::new();
        for (path, identity) in identified {
            let resolution = identity
                .as_ref()
                .and_then(|_| recorded.next())
                .unwrap_or(FileDigestResolution::Unresolved);
            let cached = match resolution {
                FileDigestResolution::Digest(digest)
                    if identity.as_ref().is_some_and(|identity| {
                        identity.len == digest.size && identity.still_describes().unwrap_or(false)
                    }) =>
                {
                    Some(digest)
                }
                FileDigestResolution::Digest(_)
                | FileDigestResolution::EmbeddedTimestampMacro
                | FileDigestResolution::Unresolved => None,
            };
            let digest = if let Some(digest) = cached {
                identities.push(identity);
                digest
            } else {
                let observed =
                    digest_file_validated(FileDigestScope::Content, &path).map_err(|error| {
                        BypassReason::InputRead {
                            path: path.clone(),
                            message: error.to_string(),
                        }
                    })?;
                let (digest, observed_identity) = if let Some(observed) = observed {
                    let digest = observed.resolution.into_digest().ok_or_else(|| {
                        BypassReason::InputRead {
                            path: path.clone(),
                            message: "content digest resolution returned no digest".into(),
                        }
                    })?;
                    if let Some(file) = observed.cache_identity.clone()
                        && file.len == digest.size
                    {
                        fresh.push(RecordedFileDigest {
                            file,
                            digest: digest.clone(),
                        });
                    }
                    (digest, observed.cache_identity)
                } else {
                    let digest = digest_file(FileDigestScope::Content, &path)
                        .and_then(|resolution| {
                            resolution.into_digest().ok_or_else(|| {
                                std::io::Error::other(
                                    "content digest resolution returned no digest",
                                )
                            })
                        })
                        .map_err(|error| BypassReason::InputRead {
                            path: path.clone(),
                            message: error.to_string(),
                        })?;
                    (digest, None)
                };
                identities.push(observed_identity);
                digest
            };
            inputs.push(ActionInput { path, digest });
        }
        if !fresh.is_empty() {
            digests.record(FileDigestScope::Content, fresh);
        }
        Ok(Self {
            working_dir,
            inputs,
            environment,
            identities,
            native_only: BTreeSet::new(),
        })
    }

    /// Mark inputs that were found only by scanning native search directories.
    pub(crate) fn with_native_only(mut self, native_only: BTreeSet<PathBuf>) -> Self {
        self.native_only = native_only;
        self
    }

    /// Whether `path` is an input only because a native search directory holds it.
    pub fn is_native_only(&self, path: &Path) -> bool {
        self.native_only.contains(path)
    }

    /// Reject inputs whose modification time overlaps the compiler invocation.
    ///
    /// Input contents are first hashed after rustc reports their paths. This
    /// timestamp barrier prevents a post-compile write from being mistaken for
    /// the contents that produced the artifact. `verify` closes the remaining
    /// race after hashing.
    pub fn verify_not_modified_since(&self, started_at: SystemTime) -> Result<(), BypassReason> {
        self.verify_not_modified_since_with_snapshots(started_at, &BTreeMap::new())
    }

    /// Reject inputs that changed from snapshots captured before rustc ran,
    /// falling back to the wall-clock barrier for inputs only dep-info named.
    ///
    /// A snapshot may use metadata or content depending on what its filesystem
    /// can compare reliably. Metadata snapshots need a change token: without
    /// one a same-length rewrite can restore its mtime.
    pub fn verify_not_modified_since_with_snapshots(
        &self,
        started_at: SystemTime,
        before: &BTreeMap<PathBuf, FileSnapshot>,
    ) -> Result<(), BypassReason> {
        for input in &self.inputs {
            if let Some(previous) = before.get(&input.path)
                && previous.proves_content_change()
            {
                let metadata =
                    std::fs::metadata(&input.path).map_err(|error| BypassReason::InputRead {
                        path: input.path.clone(),
                        message: error.to_string(),
                    })?;
                let identity = FileIdentity::for_digest_cache(&input.path, &metadata)
                    .map_err(|error| BypassReason::InputRead {
                        path: input.path.clone(),
                        message: error.to_string(),
                    })?
                    .or_else(|| FileIdentity::describe(&input.path, &metadata));
                if previous.matches(identity.as_ref(), &input.digest) {
                    continue;
                }
                return Err(BypassReason::InputModifiedDuringCompilation(
                    input.path.clone(),
                ));
            }
            let metadata =
                std::fs::metadata(&input.path).map_err(|error| BypassReason::InputRead {
                    path: input.path.clone(),
                    message: error.to_string(),
                })?;
            let modified = metadata
                .modified()
                .map_err(|error| BypassReason::InputRead {
                    path: input.path.clone(),
                    message: error.to_string(),
                })?;
            if modified >= started_at {
                return Err(BypassReason::InputModifiedDuringCompilation(
                    input.path.clone(),
                ));
            }
        }
        Ok(())
    }

    /// Compatibility form for callers that captured metadata identities.
    pub fn verify_not_modified_since_with_identities(
        &self,
        started_at: SystemTime,
        before: &BTreeMap<PathBuf, FileIdentity>,
    ) -> Result<(), BypassReason> {
        let snapshots = before
            .iter()
            .map(|(path, identity)| (path.clone(), identity.clone().into()))
            .collect();
        self.verify_not_modified_since_with_snapshots(started_at, &snapshots)
    }

    /// Rehash every discovered file after compilation and before publication.
    /// This closes the discovery/compile race by degrading changed inputs to a
    /// cache miss rather than storing outputs beneath a stale action key.
    pub fn verify(&self) -> Result<(), BypassReason> {
        for (index, input) in self.inputs.iter().enumerate() {
            let read_error = |error: std::io::Error| BypassReason::InputRead {
                path: input.path.clone(),
                message: error.to_string(),
            };
            // An input still wearing the identity discovery recorded -- length,
            // modification time, and change time -- is confirmed by that stat
            // alone. The change time is what makes this as good as reading: it
            // cannot be set from user space, so a rewrite that puts the old
            // modification time back still shows, where a platform that reports
            // none would let a same-length rewrite inside one timestamp tick
            // through. Such an identity is not trusted here, and neither is an
            // input that had none. Reading everything again cost as much as
            // keying the compilation did: a large binary's dependency rlibs, a
            // gigabyte of them, read twice for every edit.
            if let Some(Some(identity)) = self.identities.get(index)
                && identity.can_skip_content_verification()
                && identity.still_describes().map_err(read_error)?
            {
                continue;
            }
            let matches = input.digest.matches_file(&input.path).map_err(|error| {
                BypassReason::InputRead {
                    path: input.path.clone(),
                    message: error.to_string(),
                }
            })?;
            if !matches {
                return Err(BypassReason::InputChanged(input.path.clone()));
            }
        }
        Ok(())
    }

    /// Merge the manifest into an action context after verifying that both use
    /// the same compiler working directory.
    pub fn apply_to(self, context: &mut ActionContext) -> Result<(), BypassReason> {
        if normalize_components(&context.working_dir) != self.working_dir {
            return Err(BypassReason::DiscoveryWorkingDirectory);
        }
        for (name, value) in &self.environment {
            if context
                .environment
                .get(name)
                .is_some_and(|previous| previous != value)
            {
                return Err(BypassReason::ConflictingEnvironment(name.clone()));
            }
        }
        context.environment.extend(self.environment);
        context.inputs.extend(self.inputs);
        Ok(())
    }
}

impl RustcInvocation {
    /// Replace the original output flags with a single explicit dep-info file.
    pub fn dep_info_command(&self, output: &Path) -> Result<DepInfoCommand, BypassReason> {
        if !output.is_absolute() {
            return Err(BypassReason::RelativeDepInfoPath(output.to_path_buf()));
        }
        let output_text = output
            .to_str()
            .ok_or_else(|| BypassReason::NonUtf8Path(output.to_path_buf()))?;
        if output_text.contains(',') {
            return Err(BypassReason::UnsafeDepInfoPath(output.to_path_buf()));
        }

        let mut arguments = Vec::new();
        for argument in &self.arguments {
            match argument {
                Argument::Emit(_) => {}
                Argument::Path { flag, .. } if flag == "--out-dir" || flag == "-o" => {}
                argument => arguments.push(render_argument(argument)?),
            }
        }
        arguments.push(format!("--emit=dep-info={output_text}").into());
        arguments.push(self.source.clone().into_os_string());
        Ok(DepInfoCommand {
            arguments,
            output: output.to_path_buf(),
        })
    }

    /// Hash dep-info sources plus every direct compiler input already modeled
    /// by the invocation (`--extern` artifacts and custom target specs).
    pub fn discover_inputs(
        &self,
        dep_info: &RustcDepInfo,
        working_dir: &Path,
    ) -> Result<DiscoveredInputs, BypassReason> {
        self.discover_inputs_with_mappings(
            dep_info,
            working_dir,
            &[],
            &tuist_cargo_cache_core::NoFileDigestCache,
        )
    }

    /// Hash dep-info sources plus modeled compiler inputs, allowing native
    /// search directories beneath the working directory or a mapped root.
    ///
    /// `digests` may answer for files the session already read in full;
    /// pass [`tuist_cargo_cache_core::NoFileDigestCache`] to hash everything.
    pub fn discover_inputs_with_mappings(
        &self,
        dep_info: &RustcDepInfo,
        working_dir: &Path,
        path_mappings: &[PathMapping],
        digests: &dyn FileDigestCache,
    ) -> Result<DiscoveredInputs, BypassReason> {
        self.discover(dep_info, working_dir, Some(path_mappings), digests)
    }

    /// Hash dep-info sources and modeled compiler inputs, leaving native search
    /// directories out.
    ///
    /// The result cannot key a shared action: the linker may read libraries it
    /// does not list. It is enough to tell whether a crate's own sources changed,
    /// which is all that private incremental state needs, so it works for a
    /// compilation whose search paths [`Self::discover_inputs_with_mappings`]
    /// refuses.
    pub fn discover_source_inputs(
        &self,
        dep_info: &RustcDepInfo,
        working_dir: &Path,
        digests: &dyn FileDigestCache,
    ) -> Result<DiscoveredInputs, BypassReason> {
        self.discover(dep_info, working_dir, None, digests)
    }

    /// Native search directories are collected only when `path_mappings` is given.
    fn discover(
        &self,
        dep_info: &RustcDepInfo,
        working_dir: &Path,
        path_mappings: Option<&[PathMapping]>,
        digests: &dyn FileDigestCache,
    ) -> Result<DiscoveredInputs, BypassReason> {
        if !working_dir.is_absolute() {
            return Err(BypassReason::RelativeWorkingDirectory(
                working_dir.to_path_buf(),
            ));
        }
        let working_dir = normalize_components(working_dir);
        let absolute = |path: &PathBuf| {
            let absolute = if path.is_absolute() {
                path.to_path_buf()
            } else {
                working_dir.join(path)
            };
            normalize_components(&absolute)
        };
        // What dep-info names is the crate's own. A required input also covers
        // the crate root, `--extern` artifacts and target specifications, so it
        // is a source unless a native search directory holds it: there it is a
        // library resolved from that directory, which belongs in a shared key
        // but is no more a source than the directory around it.
        let sources = dep_info.files.iter().map(absolute).collect::<BTreeSet<_>>();
        let mut paths = sources.clone();
        paths.extend(self.required_inputs.iter().map(absolute));
        let admitted_roots = native_input_roots(&working_dir, path_mappings.unwrap_or_default());
        let mut native_bytes = 0_u64;
        for argument in &self.arguments {
            if path_mappings.is_some()
                && let Argument::SearchPath { kind, path } = argument
                && kind == "native"
            {
                let directory = if path.is_absolute() {
                    path.clone()
                } else {
                    working_dir.join(path)
                };
                collect_native_directory(
                    &directory,
                    &admitted_roots,
                    &mut paths,
                    &mut native_bytes,
                )?;
            }
        }
        let native_directories = self
            .arguments
            .iter()
            .filter_map(|argument| match argument {
                Argument::SearchPath { kind, path } if kind == "native" => Some(absolute(path)),
                _ => None,
            })
            .collect::<Vec<_>>();
        let native_only = paths
            .difference(&sources)
            .filter(|path| native_directories.iter().any(|root| path.starts_with(root)))
            .cloned()
            .collect();
        Ok(DiscoveredInputs::from_paths(
            &working_dir,
            paths,
            dep_info.environment.clone(),
            digests,
        )?
        .with_native_only(native_only))
    }
}

/// Return normalized roots whose native search directories can be tracked.
pub(super) fn native_input_roots(
    working_dir: &Path,
    path_mappings: &[PathMapping],
) -> Vec<PathBuf> {
    std::iter::once(working_dir)
        .chain(path_mappings.iter().map(|mapping| mapping.root.as_path()))
        .map(normalize_components)
        .collect()
}

/// Add regular files beneath an admitted native search directory, enforcing
/// the prediction input count and the caller's cumulative native byte budget.
pub(super) fn collect_native_directory(
    directory: &Path,
    admitted_roots: &[PathBuf],
    paths: &mut BTreeSet<PathBuf>,
    native_bytes: &mut u64,
) -> Result<(), BypassReason> {
    let directory = normalize_components(directory);
    if !admitted_roots
        .iter()
        .any(|root| directory.starts_with(root))
    {
        return Err(BypassReason::UnsupportedSearchPath("native".into()));
    }

    let canonical_root = match directory.canonicalize() {
        Ok(root) => root,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => {
            return Err(BypassReason::InputRead {
                path: directory,
                message: error.to_string(),
            });
        }
    };
    let mut pending = vec![directory];
    while let Some(directory) = pending.pop() {
        let entries = match std::fs::read_dir(&directory) {
            Ok(entries) => entries,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
            Err(error) => {
                return Err(BypassReason::InputRead {
                    path: directory,
                    message: error.to_string(),
                });
            }
        };
        for entry in entries {
            let entry = entry.map_err(|error| BypassReason::InputRead {
                path: directory.clone(),
                message: error.to_string(),
            })?;
            let path = entry.path();
            let file_type = entry.file_type().map_err(|error| BypassReason::InputRead {
                path: path.clone(),
                message: error.to_string(),
            })?;
            if file_type.is_dir() {
                pending.push(path);
            } else if file_type.is_file() || file_type.is_symlink() {
                // Homebrew's versionless dylibs are symlinks. Hash their
                // referents under the searched name, but do not follow directory
                // links, dangling links, or links outside this search tree.
                if file_type.is_symlink() {
                    let resolved =
                        path.canonicalize()
                            .map_err(|error| BypassReason::InputRead {
                                path: path.clone(),
                                message: error.to_string(),
                            })?;
                    if !resolved.starts_with(&canonical_root) || !resolved.is_file() {
                        return Err(BypassReason::UnsupportedSearchPath("native".into()));
                    }
                }
                *native_bytes = native_bytes
                    .checked_add(
                        std::fs::metadata(&path)
                            .map_err(|error| BypassReason::InputRead {
                                path: path.clone(),
                                message: error.to_string(),
                            })?
                            .len(),
                    )
                    .ok_or_else(|| BypassReason::UnsupportedSearchPath("native".into()))?;
                paths.insert(path);
            } else {
                return Err(BypassReason::UnsupportedSearchPath("native".into()));
            }
            if paths.len() > MAX_PREDICTED_INPUTS || *native_bytes > MAX_NATIVE_INPUT_BYTES {
                return Err(BypassReason::UnsupportedSearchPath("native".into()));
            }
        }
    }
    Ok(())
}

fn render_argument(argument: &Argument) -> Result<OsString, BypassReason> {
    let rendered = match argument {
        Argument::Plain(value) => value.clone(),
        Argument::Path { flag, path } => format!(
            "{flag}={}",
            path.to_str()
                .ok_or_else(|| BypassReason::NonUtf8Path(path.clone()))?
        ),
        Argument::SearchPath { kind, path } => format!(
            "-L{kind}={}",
            path.to_str()
                .ok_or_else(|| BypassReason::NonUtf8Path(path.clone()))?
        ),
        Argument::Extern { name, path } => match path {
            Some(path) => format!(
                "--extern={name}={}",
                path.to_str()
                    .ok_or_else(|| BypassReason::NonUtf8Path(path.clone()))?
            ),
            None => format!("--extern={name}"),
        },
        Argument::Emit(_) => unreachable!("emit arguments are removed before rendering"),
        Argument::RemapPath { from, to } => format!(
            "--remap-path-prefix={}={to}",
            from.to_str()
                .ok_or_else(|| BypassReason::NonUtf8Path(from.clone()))?
        ),
        // Nothing links while emitting dep-info, so the prefix is inert here;
        // it is replayed verbatim to keep the command faithful.
        Argument::OsoPrefix {
            path,
            trailing_slash,
        } => format!(
            "--codegen=link-arg=-Wl,-oso_prefix,{}{}",
            path.to_str()
                .ok_or_else(|| BypassReason::NonUtf8Path(path.clone()))?,
            if *trailing_slash { "/" } else { "" }
        ),
        // Nothing links while emitting dep-info either; replayed verbatim for
        // the same reason as the prefix above.
        Argument::InstallName(name) => {
            format!("--codegen=link-arg=-Wl,-install_name,@rpath/{name}")
        }
        Argument::FuseLd(selection) => format!("--codegen=link-arg=-fuse-ld={selection}"),
    };
    Ok(rendered.into())
}

fn unescape_environment(value: &str) -> Result<String, BypassReason> {
    let mut output = String::with_capacity(value.len());
    let mut characters = value.chars();
    while let Some(character) = characters.next() {
        if character != '\\' {
            output.push(character);
            continue;
        }
        match characters.next() {
            Some('\\') => output.push('\\'),
            Some('n') => output.push('\n'),
            Some('r') => output.push('\r'),
            Some(character) => {
                return Err(BypassReason::MalformedDepInfo(format!(
                    "unknown environment escape \\{character}"
                )));
            }
            None => {
                return Err(BypassReason::MalformedDepInfo(
                    "environment input ends with an unterminated escape".into(),
                ));
            }
        }
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    fn args(values: &[&str]) -> Vec<OsString> {
        values.iter().map(OsString::from).collect()
    }

    #[test]
    fn parses_files_spaces_and_environment_records() {
        let parsed = RustcDepInfo::parse(
            "target/lib.rlib: src/lib.rs src/a\\ file.rs generated.rs\n\
             src/lib.rs:\n\
             # env-dep:SET=value\\nnext\n\
             # env-dep:UNSET\n\
             # env-dep:SLASH=a\\\\b\n",
        )
        .unwrap();
        assert_eq!(
            parsed.files,
            vec![
                PathBuf::from("generated.rs"),
                PathBuf::from("src/a file.rs"),
                PathBuf::from("src/lib.rs"),
            ]
        );
        assert_eq!(parsed.environment["SET"], Some("value\nnext".into()));
        assert_eq!(parsed.environment["UNSET"], None);
        assert_eq!(parsed.environment["SLASH"], Some(r"a\b".into()));
    }

    #[test]
    fn malformed_dep_info_bypasses_caching() {
        for contents in [
            "",
            "target: ",
            "target: src/trailing\\\n",
            "target: src/lib.rs\n# env-dep:NAME=bad\\q\n",
        ] {
            assert!(RustcDepInfo::parse(contents).is_err(), "{contents:?}");
        }
    }

    #[test]
    fn native_directory_byte_limit_is_cumulative() {
        let directory = tempfile::tempdir().unwrap();
        let native = directory.path().join("native");
        std::fs::create_dir_all(&native).unwrap();
        std::fs::write(native.join("input.lib"), b"xx").unwrap();
        let roots = native_input_roots(directory.path(), &[]);
        let mut paths = BTreeSet::new();
        let mut native_bytes = MAX_NATIVE_INPUT_BYTES - 1;

        assert_eq!(
            collect_native_directory(&native, &roots, &mut paths, &mut native_bytes),
            Err(BypassReason::UnsupportedSearchPath("native".into()))
        );
    }

    #[test]
    fn discovery_command_removes_real_outputs() {
        let invocation = RustcInvocation::parse(&args(&[
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=dep-info,metadata,link",
            "--out-dir=target/debug/deps",
            "-o",
            "target/debug/libwidget.rlib",
            "src/lib.rs",
        ]))
        .unwrap();
        let output = if cfg!(windows) {
            PathBuf::from(r"C:\tmp\tuist_cargo_cache cache\inputs.d")
        } else {
            PathBuf::from("/tmp/tuist_cargo_cache cache/inputs.d")
        };
        let command = invocation.dep_info_command(&output).unwrap();
        let arguments = command
            .arguments()
            .iter()
            .map(|value| value.to_string_lossy())
            .collect::<Vec<_>>();
        assert_eq!(
            arguments,
            vec![
                "--crate-name=widget",
                "--crate-type=lib",
                &format!("--emit=dep-info={}", output.display()),
                "src/lib.rs",
            ]
        );
    }

    #[test]
    fn discovery_hashes_externs_and_custom_targets() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let source = root.join("src/lib.rs");
        let external = root.join("target/libdependency.rlib");
        let target = root.join("targets/custom.json");
        std::fs::create_dir_all(source.parent().unwrap()).unwrap();
        std::fs::create_dir_all(external.parent().unwrap()).unwrap();
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(&source, "pub fn library() {}\n").unwrap();
        std::fs::write(&external, "dependency artifact\n").unwrap();
        std::fs::write(&target, "{}\n").unwrap();

        let invocation = RustcInvocation::parse(&[
            "--crate-name=widget".into(),
            "--crate-type=lib".into(),
            "--emit=metadata".into(),
            format!("--extern=dependency={}", external.display()).into(),
            format!("--target={}", target.display()).into(),
            source.clone().into_os_string(),
        ])
        .unwrap();
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();
        let discovered = invocation.discover_inputs(&dep_info, root).unwrap();
        assert_eq!(discovered.inputs.len(), 3);

        std::fs::remove_file(&external).unwrap();
        assert!(matches!(
            invocation.discover_inputs(&dep_info, root),
            Err(BypassReason::InputRead { path, .. }) if path == external
        ));
    }

    #[test]
    fn discovery_rejects_inputs_modified_during_compilation() {
        let directory = tempfile::tempdir().unwrap();
        let source = directory.path().join("lib.rs");
        std::fs::write(&source, "pub fn library() {}\n").unwrap();
        let invocation = RustcInvocation::parse(&[
            "--crate-name=widget".into(),
            "--crate-type=lib".into(),
            "--emit=dep-info,metadata".into(),
            source.clone().into_os_string(),
        ])
        .unwrap();
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();
        let discovered = invocation
            .discover_inputs(&dep_info, directory.path())
            .unwrap();
        let modified = std::fs::metadata(&source).unwrap().modified().unwrap();

        assert_eq!(
            discovered.verify_not_modified_since(modified),
            Err(BypassReason::InputModifiedDuringCompilation(source))
        );
    }

    #[cfg(unix)]
    #[test]
    fn precompile_snapshot_does_not_depend_on_the_host_clock() {
        let directory = tempfile::tempdir().unwrap();
        let source = directory.path().join("lib.rs");
        std::fs::write(&source, "pub fn library() {0}\n").unwrap();
        let invocation = RustcInvocation::parse(&[
            "--crate-name=widget".into(),
            "--crate-type=lib".into(),
            "--emit=dep-info,metadata".into(),
            source.clone().into_os_string(),
        ])
        .unwrap();
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();
        let discovered = invocation
            .discover_inputs(&dep_info, directory.path())
            .unwrap();
        let snapshot = FileSnapshot::capture(&source).unwrap().unwrap();
        let before = BTreeMap::from([(source.clone(), snapshot)]);

        // Every ordinary mtime is after the epoch. The unchanged identity is
        // nevertheless enough proof when the filesystem clock is far ahead.
        discovered
            .verify_not_modified_since_with_snapshots(SystemTime::UNIX_EPOCH, &before)
            .unwrap();

        // Conversely, a filesystem clock far behind must not conceal a write.
        std::fs::write(&source, "pub fn library() {1}\n").unwrap();
        assert_eq!(
            discovered.verify_not_modified_since_with_snapshots(
                SystemTime::now() + std::time::Duration::from_secs(60),
                &before,
            ),
            Err(BypassReason::InputModifiedDuringCompilation(source))
        );
    }

    /// An external MSVC toolset directory, outside every mapped root.
    fn toolchain_native_directory(version: &str) -> PathBuf {
        if cfg!(windows) {
            PathBuf::from(format!(
                r"C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\{version}\lib\x64"
            ))
        } else {
            PathBuf::from(format!("/opt/msvc/{version}/lib/x64"))
        }
    }

    fn library_with_native_search(source: &Path, directory: &Path) -> RustcInvocation {
        RustcInvocation::parse(&[
            "--crate-name=widget".into(),
            "--crate-type=lib".into(),
            "--emit=metadata,link".into(),
            format!("-Lnative={}", directory.display()).into(),
            source.to_path_buf().into_os_string(),
        ])
        .unwrap()
    }

    fn library_context(root: &Path, mappings: Vec<PathMapping>) -> ActionContext {
        ActionContext {
            compiler: crate::CompilerIdentity {
                toolchain: "core:rust@test".into(),
                rustc_version: "test".into(),
                host: std::env::consts::ARCH.into(),
                driver: None,
            },
            working_dir: root.to_path_buf(),
            path_mappings: mappings,
            environment: BTreeMap::new(),
            portable_environment: BTreeSet::new(),
            inputs: Vec::new(),
        }
    }

    #[cfg(windows)]
    #[test]
    fn unmapped_toolchain_directory_cannot_hide_a_static_archive() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let source = root.join("lib.rs");
        std::fs::write(&source, "pub fn library() {}\n").unwrap();
        let toolchain = toolchain_native_directory("14.51.36231");
        let invocation = library_with_native_search(&source, &toolchain);
        let mappings = vec![PathMapping::new(root, "workspace")];
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();

        let context = library_context(root, mappings.clone());
        assert!(matches!(
            invocation.invocation_digest(&context),
            Err(BypassReason::UnmappedAbsolutePath(path)) if path == toolchain
        ));
        assert_eq!(
            invocation.discover_inputs_with_mappings(
                &dep_info,
                root,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            ),
            Err(BypassReason::UnsupportedSearchPath("native".into()))
        );
    }

    #[test]
    fn source_level_static_link_cannot_hide_an_unmapped_archive() {
        let directory = tempfile::tempdir().unwrap();
        let workspace = directory.path().join("workspace");
        let external = directory.path().join("external");
        std::fs::create_dir(&workspace).unwrap();
        std::fs::create_dir(&external).unwrap();
        let source = workspace.join("lib.rs");
        std::fs::write(
            &source,
            "#[link(name = \"foo\", kind = \"static\")] unsafe extern \"C\" {}\n",
        )
        .unwrap();
        std::fs::write(external.join("libfoo.a"), b"first archive").unwrap();
        let invocation = library_with_native_search(&source, &external);
        let mappings = vec![PathMapping::new(&workspace, "workspace")];
        let context = library_context(&workspace, mappings.clone());
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();

        // rustc's dep-info names the source but not an archive from #[link].
        // A path-only key would restore a stale rlib after libfoo.a changed.
        assert!(matches!(
            invocation.invocation_digest(&context),
            Err(BypassReason::UnmappedAbsolutePath(path)) if path == external
        ));
        assert_eq!(
            invocation.discover_inputs_with_mappings(
                &dep_info,
                &workspace,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache,
            ),
            Err(BypassReason::UnsupportedSearchPath("native".into()))
        );
    }

    #[cfg(windows)]
    #[test]
    fn project_directory_with_toolchain_suffix_is_not_trusted() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().join("workspace");
        std::fs::create_dir(&root).unwrap();
        let source = root.join("lib.rs");
        std::fs::write(&source, "pub fn library() {}\n").unwrap();
        let fake_toolchain = directory.path().join("MSVC/14.51.36231/lib/x64");
        let invocation = library_with_native_search(&source, &fake_toolchain);
        let context = library_context(&root, vec![PathMapping::new(&root, "workspace")]);

        // The apparent toolset version cannot make a mutable project archive inert.
        assert!(matches!(
            invocation.invocation_digest(&context),
            Err(BypassReason::UnmappedAbsolutePath(path)) if path == fake_toolchain
        ));
    }

    #[test]
    fn unmapped_native_directory_still_refuses_a_native_link() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let source = root.join("main.rs");
        std::fs::write(&source, "fn main() {}\n").unwrap();
        let toolchain = toolchain_native_directory("14.51.36231");
        let invocation = RustcInvocation::parse_with(
            &[
                "--crate-name=app".into(),
                "--crate-type=bin".into(),
                "--emit=link".into(),
                format!("-Lnative={}", toolchain.display()).into(),
                source.clone().into_os_string(),
            ],
            crate::ParseOptions::caching_native_links(true),
        )
        .unwrap();
        let mappings = vec![PathMapping::new(root, "workspace")];

        // A linker reads those directories, so their contents stay inputs the
        // key must account for, and an unmapped one stays a bypass.
        let context = library_context(root, mappings.clone());
        assert!(matches!(
            invocation.invocation_digest(&context),
            Err(BypassReason::UnmappedAbsolutePath(_))
        ));
        let dep_info = RustcDepInfo::parse(&format!("output: {}\n", source.display())).unwrap();
        assert_eq!(
            invocation.discover_inputs_with_mappings(
                &dep_info,
                root,
                &mappings,
                &tuist_cargo_cache_core::NoFileDigestCache
            ),
            Err(BypassReason::UnsupportedSearchPath("native".into()))
        );
    }

    #[test]
    fn discovery_resolves_parent_components_against_the_working_directory() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().join("project");
        let shared = directory.path().join("shared.rs");
        std::fs::create_dir(&root).unwrap();
        std::fs::write(&shared, "pub fn shared() {}\n").unwrap();

        let invocation = RustcInvocation::parse(&args(&[
            "--crate-name=widget",
            "--crate-type=lib",
            "--emit=metadata",
            "../shared.rs",
        ]))
        .unwrap();
        let dep_info = RustcDepInfo::parse("output: ../shared.rs\n").unwrap();
        let discovered = invocation.discover_inputs(&dep_info, &root).unwrap();

        assert_eq!(discovered.inputs.len(), 1);
        assert_eq!(discovered.inputs[0].path, shared);
    }

    #[test]
    fn rustc_dep_info_round_trip_discovers_real_inputs() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        std::fs::write(
            root.join("lib.rs"),
            "mod child; const _: &str = include_str!(\"data file.txt\"); \
             const _: &str = env!(\"TUIST_CARGO_CACHE_DISCOVERY_TEST\"); \
             const _: Option<&str> = option_env!(\"TUIST_CARGO_CACHE_DISCOVERY_UNSET\");",
        )
        .unwrap();
        std::fs::write(root.join("child.rs"), "pub fn child() {}\n").unwrap();
        std::fs::write(root.join("data file.txt"), "included\n").unwrap();

        let invocation = RustcInvocation::parse(&args(&[
            "--crate-name=cargo_cache_cache_discovery_test",
            "--crate-type=lib",
            "--emit=metadata,link",
            "lib.rs",
        ]))
        .unwrap();
        let dep_info_path = root.join("discovery inputs.d");
        let discovery_command = invocation.dep_info_command(&dep_info_path).unwrap();
        let rustc = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
        let output = match Command::new(rustc)
            .args(discovery_command.arguments())
            .current_dir(root)
            .env("TUIST_CARGO_CACHE_DISCOVERY_TEST", "observed")
            .env_remove("TUIST_CARGO_CACHE_DISCOVERY_UNSET")
            .output()
        {
            Ok(output) => output,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return,
            Err(error) => panic!("failed to execute rustc: {error}"),
        };
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        let parsed = RustcDepInfo::read(&dep_info_path).unwrap();
        let discovered = invocation.discover_inputs(&parsed, root).unwrap();
        assert_eq!(
            discovered.environment["TUIST_CARGO_CACHE_DISCOVERY_TEST"],
            Some("observed".into())
        );
        assert_eq!(
            discovered.environment["TUIST_CARGO_CACHE_DISCOVERY_UNSET"],
            None
        );
        assert_eq!(discovered.inputs.len(), 3);
        assert!(
            discovered
                .inputs
                .iter()
                .all(|input| input.digest.algorithm == "blake3")
        );
        let mut context = ActionContext {
            compiler: crate::CompilerIdentity {
                toolchain: "core:rust@test".into(),
                rustc_version: "test".into(),
                host: std::env::consts::ARCH.into(),
                driver: None,
            },
            working_dir: root.to_path_buf(),
            path_mappings: vec![crate::PathMapping::new(root, "workspace")],
            environment: BTreeMap::new(),
            portable_environment: BTreeSet::new(),
            inputs: Vec::new(),
        };
        discovered.clone().apply_to(&mut context).unwrap();
        let action = invocation.action(context).unwrap();
        assert!(
            String::from_utf8(action.bytes)
                .unwrap()
                .contains(r#""TUIST_CARGO_CACHE_DISCOVERY_TEST":"observed""#)
        );
        discovered.verify().unwrap();
        std::fs::write(root.join("child.rs"), "pub fn changed() {}\n").unwrap();
        assert_eq!(
            discovered.verify(),
            Err(BypassReason::InputChanged(root.join("child.rs")))
        );
    }

    /// A ledger that answers with a sentinel and remembers what was recorded.
    struct SentinelLedger {
        known: FileIdentity,
        digest: CacheDigest,
        recorded: std::sync::Mutex<Vec<RecordedFileDigest>>,
    }

    impl FileDigestCache for SentinelLedger {
        fn find(&self, scope: FileDigestScope, files: &[FileIdentity]) -> Vec<Option<CacheDigest>> {
            assert_eq!(scope, FileDigestScope::Content);
            files
                .iter()
                .map(|file| (*file == self.known).then(|| self.digest.clone()))
                .collect()
        }

        fn record(&self, scope: FileDigestScope, entries: Vec<RecordedFileDigest>) {
            assert_eq!(scope, FileDigestScope::Content);
            self.recorded.lock().unwrap().extend(entries);
        }
    }

    #[cfg(unix)]
    struct ReplacingLedger {
        path: PathBuf,
        replacement: PathBuf,
        recorded: std::sync::Mutex<Vec<RecordedFileDigest>>,
    }

    #[cfg(unix)]
    impl FileDigestCache for ReplacingLedger {
        fn find(&self, scope: FileDigestScope, files: &[FileIdentity]) -> Vec<Option<CacheDigest>> {
            assert_eq!(scope, FileDigestScope::Content);
            assert_eq!(files.len(), 1);
            std::fs::remove_file(&self.path).unwrap();
            std::fs::rename(&self.replacement, &self.path).unwrap();
            // Digests of files changed this moment are withheld from reuse.
            std::thread::sleep(std::time::Duration::from_millis(50));
            vec![None]
        }

        fn record(&self, scope: FileDigestScope, entries: Vec<RecordedFileDigest>) {
            assert_eq!(scope, FileDigestScope::Content);
            self.recorded.lock().unwrap().extend(entries);
        }
    }

    #[cfg(unix)]
    #[test]
    fn discovery_binds_a_replacement_digest_to_the_replacement_identity() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let path = root.join("libdep.rlib");
        let replacement = root.join("replacement.rlib");
        std::fs::write(&path, b"original....").unwrap();
        std::fs::File::options()
            .write(true)
            .open(&path)
            .unwrap()
            .set_times(std::fs::FileTimes::new().set_modified(SystemTime::UNIX_EPOCH))
            .unwrap();
        std::fs::write(&replacement, b"replacement!").unwrap();
        std::fs::File::options()
            .write(true)
            .open(&replacement)
            .unwrap()
            .set_times(std::fs::FileTimes::new().set_modified(SystemTime::UNIX_EPOCH))
            .unwrap();
        let ledger = ReplacingLedger {
            path: path.clone(),
            replacement,
            recorded: std::sync::Mutex::new(Vec::new()),
        };

        let discovered = DiscoveredInputs::from_paths(
            root,
            BTreeSet::from([path.clone()]),
            BTreeMap::new(),
            &ledger,
        )
        .unwrap();
        let current = FileIdentity::for_digest_cache(&path, &std::fs::metadata(&path).unwrap())
            .unwrap()
            .unwrap();
        let digest = CacheDigest::blake3_file(&path).unwrap();

        assert_eq!(discovered.inputs[0].digest, digest);
        assert_eq!(discovered.identities[0].as_ref(), Some(&current));
        assert_eq!(
            ledger.recorded.lock().unwrap().as_slice(),
            &[RecordedFileDigest {
                file: current,
                digest,
            }]
        );
        discovered.verify().unwrap();
    }

    #[test]
    fn discovery_reuses_recorded_digests_and_records_fresh_ones() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let known_path = root.join("libdep.rlib");
        let fresh_path = root.join("lib.rs");
        std::fs::write(&known_path, b"rlib bytes").unwrap();
        std::fs::write(&fresh_path, b"fn lib() {}").unwrap();
        // Digests of files written this moment are withheld from reuse.
        std::thread::sleep(std::time::Duration::from_millis(50));
        let metadata = std::fs::metadata(&known_path).unwrap();
        // A sentinel digest that hashing could never produce proves the read
        // was skipped: the discovered input carries it verbatim.
        let sentinel = CacheDigest {
            algorithm: "blake3".into(),
            hash: "c".repeat(64),
            size: metadata.len(),
        };
        let ledger = SentinelLedger {
            known: FileIdentity::describe(&known_path, &metadata).unwrap(),
            digest: sentinel.clone(),
            recorded: std::sync::Mutex::new(Vec::new()),
        };

        let discovered = DiscoveredInputs::from_paths(
            root,
            BTreeSet::from([known_path.clone(), fresh_path.clone()]),
            BTreeMap::new(),
            &ledger,
        )
        .unwrap();

        let by_path = |path: &Path| {
            discovered
                .inputs
                .iter()
                .find(|input| input.path == path)
                .unwrap()
                .digest
                .clone()
        };
        assert_eq!(
            by_path(&known_path),
            sentinel,
            "the recorded digest answers"
        );
        assert_eq!(
            by_path(&fresh_path),
            CacheDigest::blake3_file(&fresh_path).unwrap(),
            "an unrecorded file is hashed"
        );
        let recorded = ledger.recorded.lock().unwrap();
        assert_eq!(recorded.len(), 1, "only the fresh hash is recorded");
        assert_eq!(recorded[0].file.path, fresh_path);
        assert_eq!(recorded[0].digest, by_path(&fresh_path));
    }

    /// Verification after the compiler runs confirms an input by its recorded
    /// identity rather than by reading it again; a file that has moved on is
    /// still read and still fails. Only where the identity carries a change
    /// time, which is what makes the stat as good as the read.
    #[cfg(unix)]
    #[test]
    fn verification_trusts_an_unchanged_identity_and_rereads_a_changed_one() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let known_path = root.join("libdep.rlib");
        std::fs::write(&known_path, b"rlib bytes").unwrap();
        let metadata = std::fs::metadata(&known_path).unwrap();
        // The sentinel could never come from hashing the file, so a verify
        // that passes can only have trusted the identity.
        let sentinel = CacheDigest {
            algorithm: "blake3".into(),
            hash: "c".repeat(64),
            size: metadata.len(),
        };
        let ledger = SentinelLedger {
            known: FileIdentity::describe(&known_path, &metadata).unwrap(),
            digest: sentinel,
            recorded: std::sync::Mutex::new(Vec::new()),
        };
        let discovered = DiscoveredInputs::from_paths(
            root,
            BTreeSet::from([known_path.clone()]),
            BTreeMap::new(),
            &ledger,
        )
        .unwrap();

        discovered.verify().unwrap();

        // Rewritten with the same length: the identity moves with the write,
        // so the file is read again and the sentinel no longer matches it.
        std::thread::sleep(std::time::Duration::from_millis(20));
        std::fs::write(&known_path, b"RLIB BYTES").unwrap();
        assert_eq!(
            discovered.verify(),
            Err(BypassReason::InputChanged(known_path.clone()))
        );

        std::fs::remove_file(&known_path).unwrap();
        assert!(matches!(
            discovered.verify(),
            Err(BypassReason::InputRead { path, .. }) if path == known_path
        ));
    }

    /// A rewrite that restores length and modification time must still be
    /// hashed: the platform change token moves with every write, so the
    /// identity the ledger recorded no longer describes the file.
    #[cfg(unix)]
    #[test]
    fn a_disguised_rewrite_is_not_answered_from_the_ledger() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path();
        let path = root.join("lib.rs");
        std::fs::write(&path, b"fn lib() -> u8 { 1 }").unwrap();
        let before = std::fs::metadata(&path).unwrap();
        let identity = FileIdentity::describe(&path, &before).unwrap();

        // Same length, modification time put back: only the change token can
        // tell this file has new contents.
        std::fs::write(&path, b"fn lib() -> u8 { 2 }").unwrap();
        let file = std::fs::File::options().write(true).open(&path).unwrap();
        file.set_times(std::fs::FileTimes::new().set_modified(before.modified().unwrap()))
            .unwrap();
        drop(file);
        let after = std::fs::metadata(&path).unwrap();
        let disguised = FileIdentity::describe(&path, &after).unwrap();
        assert_eq!(disguised.len, identity.len);
        assert_eq!(disguised.modified, identity.modified);
        assert_ne!(
            disguised, identity,
            "the change token must expose the rewrite"
        );

        let ledger = SentinelLedger {
            known: identity,
            digest: CacheDigest {
                algorithm: "blake3".into(),
                hash: "e".repeat(64),
                size: after.len(),
            },
            recorded: std::sync::Mutex::new(Vec::new()),
        };
        let discovered = DiscoveredInputs::from_paths(
            root,
            BTreeSet::from([path.clone()]),
            BTreeMap::new(),
            &ledger,
        )
        .unwrap();
        assert_eq!(
            discovered.inputs[0].digest,
            CacheDigest::blake3_file(&path).unwrap(),
            "the disguised rewrite is hashed, not answered from the ledger"
        );
    }
    #[cfg(unix)]
    #[test]
    fn native_file_symlinks_are_rehashed_on_prediction() {
        use std::os::unix::fs::symlink;
        let directory = tempfile::tempdir().unwrap();
        let workspace = directory.path().join("workspace");
        let native = directory.path().join("cellar/lib");
        std::fs::create_dir_all(&workspace).unwrap();
        std::fs::create_dir_all(&native).unwrap();
        let source = workspace.join("lib.rs");
        std::fs::write(&source, "pub fn value() {}\n").unwrap();
        std::fs::write(native.join("libssl.3.dylib"), "first").unwrap();
        symlink("libssl.3.dylib", native.join("libssl.dylib")).unwrap();
        let opt = directory.path().join("opt");
        symlink(&native, &opt).unwrap();
        let invocation = library_with_native_search(&source, &opt);
        let mappings = vec![
            PathMapping::new(&workspace, "workspace"),
            PathMapping::new(&opt, "native"),
        ];
        let dep_info = RustcDepInfo {
            files: vec![source],
            environment: BTreeMap::new(),
        };
        let discover = || {
            invocation
                .discover_inputs_with_mappings(
                    &dep_info,
                    &workspace,
                    &mappings,
                    &tuist_cargo_cache_core::NoFileDigestCache,
                )
                .unwrap()
        };
        let original = discover();
        let mut context = library_context(&workspace, mappings.clone());
        original.clone().apply_to(&mut context).unwrap();
        let initial = invocation.action(context.clone()).unwrap();
        let prediction = invocation.prediction(&context, &original).unwrap();
        context.inputs.clear();
        let mut previous = initial.digest;
        for change in ["contents", "add", "retarget", "remove"] {
            match change {
                "contents" => std::fs::write(native.join("libssl.3.dylib"), "updated").unwrap(),
                "add" => std::fs::write(native.join("libssl.4.dylib"), "replacement").unwrap(),
                "retarget" => {
                    std::fs::remove_file(native.join("libssl.dylib")).unwrap();
                    symlink("libssl.4.dylib", native.join("libssl.dylib")).unwrap();
                }
                _ => std::fs::remove_file(native.join("libssl.3.dylib")).unwrap(),
            }
            let predicted = prediction
                .discover(
                    &workspace,
                    &mappings,
                    &tuist_cargo_cache_core::NoFileDigestCache,
                )
                .unwrap();
            let mut predicted_context = context.clone();
            predicted.apply_to(&mut predicted_context).unwrap();
            let predicted_action = invocation.action(predicted_context).unwrap();
            let mut discovered_context = context.clone();
            discover().apply_to(&mut discovered_context).unwrap();
            assert_eq!(
                predicted_action,
                invocation.action(discovered_context).unwrap()
            );
            assert_ne!(predicted_action.digest, previous, "{change}");
            previous = predicted_action.digest;
        }
        std::fs::remove_file(native.join("libssl.dylib")).unwrap();
        let outside = directory.path().join("outside");
        std::fs::write(&outside, "untracked").unwrap();
        symlink(&outside, native.join("libssl.dylib")).unwrap();
        assert!(
            prediction
                .discover(
                    &workspace,
                    &mappings,
                    &tuist_cargo_cache_core::NoFileDigestCache
                )
                .is_err()
        );
        std::fs::remove_file(native.join("libssl.dylib")).unwrap();
        symlink(".", native.join("loop")).unwrap();
        assert!(
            prediction
                .discover(
                    &workspace,
                    &mappings,
                    &tuist_cargo_cache_core::NoFileDigestCache
                )
                .is_err()
        );
    }
}
