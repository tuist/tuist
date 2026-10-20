//! Conservative parsing and action-key construction for `rustc` invocations.
//!
//! The adapter deliberately rejects any compiler option whose effect on the
//! action key is unknown. Callers should treat [`BypassReason`] as a safe cache
//! bypass, run the real compiler, and avoid publishing an action result.
//!
//! A typical integration parses an invocation, discovers precise inputs from
//! rustc dep-info with [`RustcInvocation::discover_inputs`], adds them to an
//! [`ActionContext`], and finally calls [`RustcInvocation::action`]. Path
//! mappings make workspace-local absolute paths stable across machines.
//!
//! ```
//! use tuist_cargo_cache_rustc::{PathMapping, normalize_mapped_path};
//! use std::path::Path;
//!
//! let mappings = PathMapping::ordered(&[
//!     PathMapping::new("/work/project", "workspace"),
//! ]);
//! assert_eq!(
//!     normalize_mapped_path(
//!         Path::new("src/lib.rs"),
//!         Path::new("/work/project"),
//!         &mappings,
//!     )?,
//!     "${workspace}/src/lib.rs",
//! );
//! # Ok::<(), tuist_cargo_cache_rustc::BypassReason>(())
//! ```
#![deny(missing_docs)]

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::path::{Component, Path, PathBuf};
use thiserror::Error;
use tuist_cargo_cache_core::{
    CacheDigest, FileDigestCache, PathAliases, PathMapping as SharedPathMapping,
    PathNormalizationError, canonical_json, normalize_mapped_path as normalize_shared_path,
    normalize_resolved_mapped_path_with as normalize_resolved_shared_path_with,
    resolve_path_mappings,
};

mod dep_info;

pub use dep_info::{DepInfoCommand, DiscoveredInputs, RustcDepInfo};

/// Schema version embedded in canonical rustc action descriptors.
pub const ACTION_SCHEMA_VERSION: u8 = 1;
/// Version of the rustc argument and input model used to construct keys.
///
/// Bumped to 2 when the dep-info and diagnostics stored with a result stopped
/// carrying the publishing checkout's absolute paths. Entries written before
/// that hold the old spelling, and nothing in them says so, so they are retired
/// by the key rather than restored into a checkout they do not describe.
pub const ADAPTER_VERSION: u8 = 2;

impl BypassReason {
    /// A stable, low-cardinality name for this reason.
    ///
    /// Many variants carry a path or a flag, so `Display` text cannot be
    /// aggregated; statistics group by this instead.
    pub fn kind(&self) -> &'static str {
        self.into()
    }

    /// A concrete change that can make this invocation cacheable, when one is
    /// available.
    ///
    /// Expected probes and failures that require adapter support return
    /// `None`; callers can still explain those from [`BypassReason::kind`].
    pub fn remediation(&self) -> Option<&'static str> {
        match self {
            Self::Incremental => Some(
                "Set `TUIST_CARGO_CACHE_INCREMENTAL=0`; tuist_cargo_cache will then disable Cargo incremental state and cache the compilation.",
            ),
            Self::UnportableNativeLink(detail) if detail.contains("linker") => Some(
                "Make the native linker resolvable on `PATH`, or configure a linker tuist_cargo_cache can identify for this target.",
            ),
            Self::UnportableNativeLink(_) => Some(
                "Remove the reported `-C` option from the active Cargo profile or `RUSTFLAGS` to make these links cacheable.",
            ),
            Self::UnknownFlag(_) | Self::UnknownCodegenOption(_) => Some(
                "Remove the reported compiler option, or upgrade tuist_cargo_cache if the option should be modeled.",
            ),
            Self::UnmodeledLinkArgument(_) => Some(
                "Remove the reported linker argument, or keep these links uncached if the argument is required.",
            ),
            Self::UnmappedAbsolutePath(_) => Some(
                "Move the input under the workspace, target, Cargo, toolchain, or home roots so tuist_cargo_cache can give it a portable cache name.",
            ),
            Self::BuildScriptInputOverlapsOutputs(_) => Some(
                "Keep compiler output directories outside watched trees, or narrow `rerun-if-changed` to source and asset paths.",
            ),
            _ => None,
        }
    }
}

impl From<PathNormalizationError> for BypassReason {
    fn from(reason: PathNormalizationError) -> Self {
        match reason {
            PathNormalizationError::UnmappedAbsolutePath(path) => Self::UnmappedAbsolutePath(path),
            PathNormalizationError::NonUtf8Path(path) => Self::NonUtf8Path(path),
        }
    }
}

const SUPPORTED_CODEGEN_OPTIONS: &[&str] = &[
    "codegen-units",
    "control-flow-guard",
    "debug-assertions",
    "debuginfo",
    "default-linker-libraries",
    "embed-bitcode",
    "extra-filename",
    "force-frame-pointers",
    "force-unwind-tables",
    "instrument-coverage",
    "link-arg",
    "link-args",
    "link-dead-code",
    "link-self-contained",
    "linker-plugin-lto",
    "lto",
    "metadata",
    "no-prepopulate-passes",
    "opt-level",
    "overflow-checks",
    "panic",
    "prefer-dynamic",
    "relocation-model",
    "rpath",
    "save-temps",
    "soft-float",
    "split-debuginfo",
    "split-dwarf-kind",
    "strip",
    "symbol-mangling-version",
    "target-cpu",
    "target-feature",
    "tls-model",
];

const NATIVE_DIRECTORY_PREDICTION_PREFIX: &str = "@native-directory:";
const MAX_PREDICTED_INPUTS: usize = 16 * 1024;
// A compact payload is capped on the wire by the protocol. Bound its expanded
// form too, so a hostile prefix chain cannot turn a small manifest into an
// unreasonable allocation while it is being decoded.
const MAX_DECODED_PREDICTION_BYTES: usize = 16 * 1024 * 1024;
const MAX_NATIVE_INPUT_BYTES: u64 = 2 * 1024 * 1024 * 1024;

/// Built-in WebAssembly targets whose default linkers and CRT inputs ship in
/// the Rust toolchain. Custom target specs never enter this list.
const COMPILER_BUNDLED_WASM_TARGETS: &[&str] = &[
    "wasm32-unknown-unknown",
    "wasm32-wasip1",
    "wasm32-wasip1-threads",
    "wasm32-wasip2",
    "wasm32v1-none",
    "wasm64-unknown-unknown",
];

#[derive(Debug, Clone, PartialEq, Eq, Error, strum::IntoStaticStr)]
#[strum(serialize_all = "kebab-case")]
/// Reason an invocation cannot safely use the action cache.
///
/// A bypass is an expected conservative outcome, not necessarily a compiler
/// error. Variants carry diagnostic context while [`BypassReason::kind`]
/// provides a stable aggregation key.
///
/// This set exists to shrink: every invocation the adapter learns to model
/// retires a variant, and every construct it learns to reject adds one. Match
/// on [`BypassReason::kind`] for aggregation rather than on the variants.
#[non_exhaustive]
pub enum BypassReason {
    /// An argument cannot be represented in the canonical UTF-8 key.
    #[error("rustc argument {index} is not valid UTF-8")]
    NonUtf8Argument {
        /// Zero-based index in the argument slice.
        index: usize,
    },
    /// A rustc response file could not be read or parsed exactly.
    #[error("could not model rustc response file: {0}")]
    ResponseFile(String),
    /// A compiler flag is not modeled by this adapter version.
    #[error("rustc flag is not modeled by the cache adapter: {0}")]
    UnknownFlag(String),
    /// A `-C` option is not modeled by this adapter version.
    #[error("rustc codegen option is not modeled by the cache adapter: {0}")]
    UnknownCodegenOption(String),
    /// A recognized flag was not followed by its required value.
    #[error("rustc flag requires a value: {0}")]
    MissingValue(String),
    /// The invocation queries compiler information instead of compiling.
    #[error("rustc invocation is a compiler query, not a compilation")]
    CompilerQuery,
    /// Source would be read from standard input and cannot be rediscovered.
    #[error("rustc invocation reads source from standard input")]
    StandardInput,
    /// No Rust source input was supplied.
    #[error("rustc invocation has no source input")]
    MissingInput,
    /// More than one source input was supplied.
    #[error("rustc invocation has multiple source inputs")]
    MultipleInputs,
    /// Incremental state makes the outputs unsuitable for action caching.
    #[error("incremental compilation cannot be combined with action caching")]
    Incremental,
    /// The requested crate type is outside the supported cacheability tier.
    #[error("rustc crate type is not cacheable yet: {0}")]
    UnsupportedCrateType(String),
    /// The requested emit kind is outside the supported cacheability tier.
    #[error("rustc output type is not cacheable yet: {0}")]
    UnsupportedEmit(String),
    /// The invocation emits no artifact in the supported cacheability tier.
    #[error("rustc invocation does not emit a cacheable artifact")]
    NoCacheableOutput,
    /// The invocation does not emit the dep-info needed for input discovery.
    #[error("rustc invocation does not emit dependency information")]
    NoDepInfo,
    /// Outputs cannot be represented as one cache directory.
    #[error("rustc output paths do not share one directory")]
    SplitOutputDirectories,
    /// An output path does not name a file.
    #[error("rustc output path has no file name: {0}")]
    InvalidOutputPath(PathBuf),
    /// `-o` leaves the name of an implicit emit ambiguous.
    #[error("rustc -o with an emit that has no explicit path is not modeled: {0}")]
    ImplicitEmitWithOutputFile(PathBuf),
    /// A linked output hands its native libraries to a linker whose search
    /// is not modeled; only a library emit can name what rustc reads.
    #[error("native library on a linked output is not cacheable yet: {0}")]
    NativeLibrary(String),
    /// A static library named by `-l` is not in any directory rustc would
    /// read it from, so there is no archive to hash.
    #[error("native static library was not found on any search path: {0}")]
    MissingNativeLibrary(String),
    /// A custom target specification chooses its own static-library file
    /// names, so the archive rustc would read cannot be named without it.
    #[error("static library file names are not known for a custom target: {0}")]
    CustomTargetNativeLibrary(String),
    /// An output's name does not say whether it is a program or a library.
    #[error("rustc output name does not distinguish a program from a library: {0}")]
    AmbiguousOutputName(PathBuf),
    /// A native link would embed something no other checkout can reproduce.
    #[error("native link is not reproducible across checkouts: {0}")]
    UnportableNativeLink(String),
    /// A linked output was given an argument to pass on to its linker.
    #[error("rustc link argument is not modeled by the cache adapter: {0}")]
    UnmodeledLinkArgument(String),
    /// A library search-path kind is not modeled.
    #[error("rustc search path kind is not cacheable yet: {0}")]
    UnsupportedSearchPath(String),
    /// An extern name does not resolve to a concrete input artifact.
    #[error("rustc extern does not identify an input artifact: {0}")]
    UnresolvedExtern(String),
    /// An absolute path has no stable placeholder mapping.
    #[error("absolute path has no stable cache mapping: {0}")]
    UnmappedAbsolutePath(PathBuf),
    /// A path cannot be represented in a canonical UTF-8 action key.
    #[error("cache key paths must be valid UTF-8: {0}")]
    NonUtf8Path(PathBuf),
    /// The action working directory is not absolute.
    #[error("cache action working directory must be absolute: {0}")]
    RelativeWorkingDirectory(PathBuf),
    /// A path-mapping root is not absolute.
    #[error("cache path mapping must use an absolute root: {0}")]
    RelativePathMapping(PathBuf),
    /// A mapping placeholder is empty or contains unsafe characters.
    #[error("cache path mapping placeholder is invalid: {0}")]
    InvalidPathPlaceholder(String),
    /// An input referenced by compiler arguments is missing from the context.
    #[error("required compiler input was not provided: {0}")]
    MissingRequiredInput(String),
    /// A supplied compiler-input digest is malformed.
    #[error("compiler input has an invalid digest: {0}")]
    InvalidInputDigest(String),
    /// One normalized input path has multiple distinct digests.
    #[error("compiler input appears more than once with different content: {0}")]
    ConflictingInput(String),
    /// rustc dep-info does not follow the supported format.
    #[error("rustc dep-info is malformed: {0}")]
    MalformedDepInfo(String),
    /// A dep-info file could not be read as UTF-8 text.
    #[error("failed to read rustc dep-info {path}: {message}")]
    DepInfoRead {
        /// Dep-info file path.
        path: PathBuf,
        /// Underlying I/O or decoding error.
        message: String,
    },
    /// The requested dep-info output path is not absolute.
    #[error("rustc dep-info output path must be absolute: {0}")]
    RelativeDepInfoPath(PathBuf),
    /// A dep-info output path contains a comma and cannot be safely rendered.
    #[error("rustc dep-info output path cannot contain a comma: {0}")]
    UnsafeDepInfoPath(PathBuf),
    /// A discovered compiler input could not be read or was not a file.
    #[error("failed to read compiler input {path}: {message}")]
    InputRead {
        /// Compiler-input path.
        path: PathBuf,
        /// Underlying filesystem error.
        message: String,
    },
    /// A declared build-script input includes files the compiler writes.
    #[error("declared build-script input overlaps compiler outputs: {0}")]
    BuildScriptInputOverlapsOutputs(PathBuf),
    /// A build script's watched paths or environment changed after discovery.
    /// The path identifies Cargo's recorded declarations, not a changed input.
    #[error("build-script inputs changed during compilation (declarations: {0})")]
    BuildScriptInputsChanged(PathBuf),
    /// Input contents changed after they were hashed.
    #[error("compiler input changed after discovery: {0}")]
    InputChanged(PathBuf),
    /// An input's modification time overlaps the compiler execution.
    #[error("compiler input was modified during compilation: {0}")]
    InputModifiedDuringCompilation(PathBuf),
    /// Discovered inputs and the action use different working directories.
    #[error("discovered inputs were collected from a different working directory")]
    DiscoveryWorkingDirectory,
    /// One observed environment input has conflicting values.
    #[error("compiler environment input has conflicting values: {0}")]
    ConflictingEnvironment(String),
    /// Canonical action serialization failed.
    #[error("failed to serialize the rustc action: {0}")]
    Serialization(String),
    /// The stored prediction uses an unsupported version or exceeds limits.
    #[error("rustc action prediction is unsupported")]
    UnsupportedPrediction,
    /// A normalized predicted path cannot be mapped back to the host.
    #[error("rustc action prediction contains an invalid input path: {0}")]
    InvalidPredictedInput(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Argument {
    Plain(String),
    Path {
        flag: String,
        path: PathBuf,
    },
    SearchPath {
        kind: String,
        path: PathBuf,
    },
    Extern {
        name: String,
        path: Option<PathBuf>,
    },
    Emit(Vec<Emit>),
    RemapPath {
        from: PathBuf,
        to: String,
    },
    /// A single @rpath filename used as a macOS proc macro install name.
    InstallName(String),
    /// An `-oso_prefix` handed to ld64, whose path strips checkout-specific
    /// prefixes from the debug map the linker records.
    OsoPrefix {
        path: PathBuf,
        trailing_slash: bool,
    },
    /// A `-fuse-ld=<name>` handed to the driver, selecting which linker a
    /// link invokes. Modeled for native links only, where the linker identity
    /// probe resolves and pins the linker it names.
    FuseLd(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Emit {
    kind: String,
    path: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parsed, cache-safe model of one `rustc` command line.
///
/// Fields are intentionally private so new modeled flags can be added without
/// exposing the adapter's internal representation.
pub struct RustcInvocation {
    arguments: Vec<Argument>,
    source: PathBuf,
    required_inputs: Vec<PathBuf>,
    crate_name: String,
    extra_filename: String,
    out_dir: Option<PathBuf>,
    explicit_output: Option<PathBuf>,
    emits: Vec<Emit>,
    target: Option<String>,
    link_output: LinkOutput,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LinkOutput {
    Library,
    WasmExecutable,
    NativeExecutable,
    NativeProcMacro,
    /// A `cdylib` linked for the host. Admitted on Linux only: an ELF shared
    /// object names neither its own path nor an import library beside it,
    /// where a Mach-O dylib records its output path as its install name and
    /// a Windows DLL leaves an import library and export file next to it.
    NativeSharedLibrary,
}

/// What the caller is prepared to model beyond the default tier.
///
/// The parser itself stays pure: whether the host can describe its linker
/// precisely enough to key a native link is the caller's question, and the
/// answer arrives here rather than being read out of the environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[non_exhaustive]
pub struct ParseOptions {
    /// Admit natively linked test binaries, executables, and proc macros,
    /// given a linker identity in the action key. Off by default.
    pub cache_native_links: bool,
    /// rustc may resolve this invocation's bare `--target NAME` to a custom
    /// specification: a `NAME.json` under `RUST_TARGET_PATH` or a
    /// `lib/rustlib/NAME/target.json` in the sysroot exists. Such a target
    /// chooses its own static-library file names, which the parser cannot
    /// know, so `-l static` bypasses.
    pub custom_target_search: bool,
}

impl ParseOptions {
    /// Options that admit native links when `enabled`.
    pub fn caching_native_links(enabled: bool) -> Self {
        Self {
            cache_native_links: enabled,
            ..Self::default()
        }
    }

    /// Options that also say whether rustc could resolve a bare target name
    /// to a custom specification.
    pub fn with_custom_target_search(mut self, enabled: bool) -> Self {
        self.custom_target_search = enabled;
        self
    }
}

/// The cacheable files and dependency manifest produced by a rustc invocation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RustcOutputs {
    /// Common directory containing all modeled outputs.
    pub directory: PathBuf,
    /// Cacheable library, metadata, and/or linked program files.
    pub files: Vec<PathBuf>,
    /// Dep-info file used for precise input discovery.
    pub dep_info: PathBuf,
}

impl RustcInvocation {
    /// Parse rustc's arguments, excluding the compiler executable supplied as
    /// the first argument to `RUSTC_WRAPPER`.
    ///
    /// Any flag whose cache semantics are not modeled returns a bypass reason
    /// instead of guessing. A successful parse admits the rlib/rmeta tier,
    /// every compilation that links nothing at all -- what `cargo check` and
    /// clippy run, whatever the crate type -- and binaries linked by
    /// compiler-bundled WebAssembly toolchains.
    pub fn parse(arguments: &[OsString]) -> Result<Self, BypassReason> {
        Self::parse_with(arguments, ParseOptions::default())
    }

    /// The command line with `@argfile` response files expanded, as the
    /// parser sees it. A caller that scans the arguments before parsing, for a
    /// `--target` a response file may carry, reads this rather than the raw
    /// list.
    pub fn expand_arguments(arguments: &[OsString]) -> Result<Vec<OsString>, BypassReason> {
        Ok(expand_response_files(arguments)?.arguments)
    }

    /// Parse as [`RustcInvocation::parse`] does, admitting what `options`
    /// says the caller can model.
    pub fn parse_with(arguments: &[OsString], options: ParseOptions) -> Result<Self, BypassReason> {
        let expanded = expand_response_files(arguments)?;
        Parser::new(&expanded.arguments, options).parse()
    }

    /// Whether this invocation links a native artifact, whose key must
    /// therefore describe the linker that produced it.
    pub fn links_natively(&self) -> bool {
        matches!(
            self.link_output,
            LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        )
    }

    /// Stable Mach-O identity for a cached macOS proc macro. The compiler loads
    /// these by filename; embedding the checkout's output path only makes the
    /// bytes (and dependent action keys) vary between otherwise identical builds.
    pub fn portable_install_name(&self, outputs: &RustcOutputs) -> Option<String> {
        if !cfg!(target_os = "macos")
            || self.link_output != LinkOutput::NativeProcMacro
            || self
                .arguments
                .iter()
                .any(|arg| matches!(arg, Argument::InstallName(_)))
        {
            return None;
        }
        let file = outputs
            .files
            .iter()
            .find(|path| path.extension().is_some_and(|ext| ext == "dylib"))?;
        let name = file.file_name()?.to_str()?;
        if !safe_install_name(name) {
            return None;
        }
        Some(format!("-Clink-arg=-Wl,-install_name,@rpath/{name}"))
    }

    /// Linker selected with `-C linker`, if the invocation overrides rustc's
    /// platform default.
    pub fn linker_override(&self) -> Option<&Path> {
        self.arguments.iter().find_map(|argument| {
            let Argument::Plain(value) = argument else {
                return None;
            };
            value.strip_prefix("--codegen=linker=").map(Path::new)
        })
    }

    /// Linker selected with `-C link-arg=-fuse-ld=<name>`, if the invocation
    /// passes one the adapter models.
    pub fn fuse_ld(&self) -> Option<&str> {
        self.arguments.iter().find_map(|argument| {
            let Argument::FuseLd(selection) = argument else {
                return None;
            };
            Some(selection.as_str())
        })
    }

    fn emits_windows_pdb(&self) -> bool {
        if !cfg!(windows) || !self.links_natively() {
            return false;
        }
        let mut enabled = false;
        for argument in &self.arguments {
            let Argument::Plain(value) = argument else {
                continue;
            };
            if value == "-g" {
                enabled = true;
            } else if let Some(value) = value.strip_prefix("--codegen=debuginfo=") {
                enabled = !matches!(value, "0" | "none");
            }
        }
        enabled
    }

    /// Native directories explicitly searched by this invocation. Callers can
    /// map external installations so their contents participate in discovery
    /// and prediction, rather than treating their paths as immutable inputs.
    pub fn native_search_paths(&self) -> impl Iterator<Item = &Path> {
        self.arguments.iter().filter_map(|argument| match argument {
            Argument::SearchPath { kind, path } if kind == "native" => Some(path.as_path()),
            _ => None,
        })
    }

    /// Return the source input passed to rustc.
    pub fn source(&self) -> &Path {
        &self.source
    }

    /// Absolute files named directly by the invocation that rustc must read.
    ///
    /// This includes the source, explicit extern artifacts, and custom target
    /// specifications. Callers can snapshot these before rustc starts even
    /// though the complete input set is only known from dep-info afterwards.
    pub fn required_inputs_in(&self, working_dir: &Path) -> Vec<PathBuf> {
        self.required_inputs
            .iter()
            .map(|path| absolute_path(path, working_dir))
            .collect()
    }

    /// Return the explicitly selected compilation target, if any.
    pub fn target(&self) -> Option<&str> {
        self.target.as_deref()
    }

    /// Return the crate name rustc will assign to this compilation.
    pub fn crate_name(&self) -> &str {
        &self.crate_name
    }

    /// Digest of the inputs this compilation owns: its sources and whatever
    /// they read, but not the artifacts it merely links against.
    ///
    /// This is what separates a crate someone is editing from one sitting
    /// above it in the graph. Rebuilding a dependency changes the action key of
    /// every crate that links it, because their keys hash its artifact; it does
    /// not change this. A caller watching for churn has to watch this instead,
    /// or a single edited crate would drag its whole dependent cone along.
    ///
    /// Host paths enter the digest as they are. This describes one checkout to
    /// itself rather than to the cache, so there is nothing here to make
    /// portable.
    pub fn source_fingerprint(&self, discovered: &DiscoveredInputs) -> CacheDigest {
        let linked = self
            .arguments
            .iter()
            .filter_map(|argument| match argument {
                Argument::Extern {
                    path: Some(path), ..
                } => Some(path.as_path()),
                _ => None,
            })
            .collect::<BTreeSet<_>>();
        let owned = discovered
            .inputs
            .iter()
            .filter(|input| {
                !linked.contains(input.path.as_path()) && !discovered.is_native_only(&input.path)
            })
            .map(|input| (input.path.as_path(), &input.digest))
            .collect::<BTreeMap<_, _>>();
        let mut bytes = Vec::new();
        for (path, digest) in owned {
            bytes.extend_from_slice(path.as_os_str().as_encoded_bytes());
            bytes.push(0);
            bytes.extend_from_slice(digest.key().as_bytes());
            bytes.push(0);
        }
        CacheDigest::blake3(&bytes)
    }

    /// Resolve the files produced by this invocation.
    ///
    /// The initial cache tier requires one output directory so its artifact can
    /// be represented by one protocol directory and restored atomically later.
    pub fn outputs(&self, working_dir: &Path) -> Result<RustcOutputs, BypassReason> {
        if !working_dir.is_absolute() {
            return Err(BypassReason::RelativeWorkingDirectory(
                working_dir.to_path_buf(),
            ));
        }
        let explicit_output = self
            .explicit_output
            .as_deref()
            .map(|path| absolute_path(path, working_dir));
        let output_directory = explicit_output
            .as_deref()
            .and_then(Path::parent)
            .map(Path::to_path_buf)
            .or_else(|| {
                self.out_dir
                    .as_deref()
                    .map(|path| absolute_path(path, working_dir))
            })
            .unwrap_or_else(|| normalize_components(working_dir));
        // rustc applies `-o` to every emit that has no path of its own, so the
        // file names cannot be derived from the crate name here. Cargo always
        // uses --out-dir instead, so refusing to model this costs nothing.
        if let Some(output) = &explicit_output
            && self.emits.iter().any(|emit| {
                emit.path.is_none()
                    && matches!(emit.kind.as_str(), "dep-info" | "link" | "metadata")
            })
        {
            return Err(BypassReason::ImplicitEmitWithOutputFile(output.clone()));
        }
        let mut files = BTreeSet::new();
        let mut dep_info = None;
        for emit in &self.emits {
            if emit.kind == "dep-info" {
                let path = emit.path.as_ref().map_or_else(
                    || {
                        explicit_output.clone().map_or_else(
                            || {
                                output_directory
                                    .join(format!("{}{}.d", self.crate_name, self.extra_filename))
                            },
                            |path| path.with_extension("d"),
                        )
                    },
                    |path| absolute_path(path, working_dir),
                );
                if path.file_name().is_none() {
                    return Err(BypassReason::InvalidOutputPath(path));
                }
                dep_info = Some(path);
                continue;
            }
            let (prefix, extension) = match emit.kind.as_str() {
                "link" => match self.link_output {
                    LinkOutput::Library => ("lib", "rlib"),
                    LinkOutput::WasmExecutable => ("", "wasm"),
                    LinkOutput::NativeExecutable => ("", std::env::consts::EXE_EXTENSION),
                    LinkOutput::NativeProcMacro | LinkOutput::NativeSharedLibrary => (
                        std::env::consts::DLL_PREFIX,
                        std::env::consts::DLL_SUFFIX.trim_start_matches('.'),
                    ),
                },
                "metadata" => ("lib", "rmeta"),
                _ => continue,
            };
            let path = if let Some(path) = &emit.path {
                absolute_path(path, working_dir)
            } else {
                let name = format!("{prefix}{}{}", self.crate_name, self.extra_filename);
                output_directory.join(if extension.is_empty() {
                    name
                } else {
                    format!("{name}.{extension}")
                })
            };
            if path.file_name().is_none() {
                return Err(BypassReason::InvalidOutputPath(path));
            }
            if path.parent() != Some(output_directory.as_path()) {
                return Err(BypassReason::SplitOutputDirectories);
            }
            // Whether a restored output is a program is read back off its name,
            // so a program that answers to a library's name would be restored
            // without the permission that makes it runnable. Nothing cargo
            // emits looks like this; a hand-built invocation could.
            let has_library_extension = path
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| matches!(extension, "rlib" | "rmeta"))
                || (cfg!(windows)
                    && path
                        .file_stem()
                        .and_then(|stem| Path::new(stem).extension())
                        .and_then(|extension| extension.to_str())
                        .is_some_and(|extension| matches!(extension, "rlib" | "rmeta")));
            if emit.kind == "link"
                && !matches!(self.link_output, LinkOutput::Library)
                && has_library_extension
            {
                return Err(BypassReason::AmbiguousOutputName(path));
            }
            if emit.kind == "link" && self.emits_windows_pdb() {
                files.insert(path.with_extension("pdb"));
            }
            files.insert(path);
        }
        let dep_info = dep_info.ok_or(BypassReason::NoDepInfo)?;
        if dep_info.parent() != Some(output_directory.as_path()) {
            return Err(BypassReason::SplitOutputDirectories);
        }
        Ok(RustcOutputs {
            directory: output_directory,
            files: files.into_iter().collect(),
            dep_info,
        })
    }

    /// Build canonical action bytes after precise input discovery has run.
    ///
    /// `context.inputs` must contain the source, every explicit extern, and
    /// every additional source or environment-generated input discovered from
    /// dep-info.
    pub fn action(&self, context: ActionContext) -> Result<RustcAction, BypassReason> {
        self.action_linked_by(context, None)
    }

    /// Build canonical action bytes for an invocation that links a native
    /// program.
    ///
    /// A `linker` is required whenever [`RustcInvocation::links_natively`]
    /// holds: the linker, its startup objects, and the platform SDK are inputs
    /// rustc dep-info does not enumerate, so a key without them would claim
    /// more than it can support. Passing one for anything else is ignored,
    /// since nothing else depends on a linker.
    pub fn action_linked_by(
        &self,
        context: ActionContext,
        linker: Option<LinkerIdentity>,
    ) -> Result<RustcAction, BypassReason> {
        ActionBuilder::new(self, context).linked_by(linker).build()
    }

    /// Fingerprint the modeled invocation before dependency contents are known.
    pub fn invocation_digest(&self, context: &ActionContext) -> Result<CacheDigest, BypassReason> {
        let descriptor = ActionBuilder::new(self, context.clone()).invocation_descriptor()?;
        let bytes = canonical_json(&descriptor)
            .map_err(|error| BypassReason::Serialization(error.to_string()))?;
        Ok(CacheDigest::blake3(&bytes))
    }

    /// Capture normalized dependency paths for a future invocation that has no
    /// dep-info file yet.
    pub fn prediction(
        &self,
        context: &ActionContext,
        discovered: &DiscoveredInputs,
    ) -> Result<RustcInputPrediction, BypassReason> {
        let builder = ActionBuilder::new(self, context.clone());
        builder.validate_mappings()?;
        let mut native_directories = BTreeSet::new();
        for argument in &self.arguments {
            if let Argument::SearchPath { kind, path } = argument
                && kind == "native"
            {
                native_directories.insert(builder.normalize_path(path)?);
            }
        }
        // A file beneath a recorded directory is rediscovered by walking that
        // directory, so naming it as well only makes the payload grow with the
        // object tree a C dependency leaves in its `OUT_DIR`. `aws-lc-sys`
        // leaves thousands of files there, which was enough to push the
        // serialized prediction past the protocol's payload limit and lose the
        // prediction entirely for the crate that most needed one.
        //
        // A file dep-info itself names stays, even beneath a recorded
        // directory. It is a source of the crate, and rediscovery can only tell
        // it from the objects around it if the prediction says which it is.
        // There are few of those; the thousands of objects are not named.
        let mut inputs = BTreeSet::new();
        for input in &discovered.inputs {
            let normalized = builder.normalize_path(&input.path)?;
            if !under_any_directory(&normalized, &native_directories)
                || !discovered.is_native_only(&input.path)
            {
                inputs.insert(normalized);
            }
        }
        inputs.extend(
            native_directories
                .into_iter()
                .map(|directory| format!("{NATIVE_DIRECTORY_PREDICTION_PREFIX}{directory}")),
        );
        Ok(RustcInputPrediction {
            version: 4,
            inputs: inputs.into_iter().collect(),
            environment: discovered.environment.keys().cloned().collect(),
            compiler_duration_ns: 0,
            crate_name: String::new(),
        })
    }
}

/// Whether a crate name has the form Cargo gives every build script.
///
/// The name alone is not proof: see [`RustcOutputs::build_script_executable`].
pub fn is_build_script_crate_name(crate_name: &str) -> bool {
    crate_name
        .strip_prefix("build_script_")
        .is_some_and(|stem| !stem.is_empty())
}

impl RustcOutputs {
    /// The linked executable Cargo will run as a build script, when this is a
    /// build-script compilation.
    ///
    /// Cargo names a build script's crate `build_script_` plus the stem of its
    /// source: `build_script_build` for `build.rs`, `build_script_main` for
    /// `build = "builder/main.rs"`. A `[[bin]]` target can take the same name,
    /// and Cargo's output directory does not tell them apart, so the caller
    /// has to confirm from Cargo's environment that this is a build script:
    /// Cargo sets `CARGO_BIN_NAME` for binary targets and never for one.
    pub fn build_script_executable(&self, crate_name: &str) -> Option<&Path> {
        is_build_script_crate_name(crate_name)
            .then(|| self.files.iter().find(|path| self.is_executable(path)))
            .flatten()
            .map(PathBuf::as_path)
    }

    /// Whether `path` is a linked program whose executable permission is part
    /// of the declared output contract.
    /// A program is whatever this invocation emitted that is not a library
    /// artifact. Every tier the adapter admits distinguishes the two by
    /// extension -- `rlib` and `rmeta` are the compiler's own, and a linked
    /// program carries either the target's (`wasm`) or none at all -- so the
    /// name is enough and no separate list has to be carried alongside.
    pub fn is_executable(&self, path: &Path) -> bool {
        self.files.iter().any(|output| output == path)
            && !matches!(
                path.extension().and_then(|extension| extension.to_str()),
                Some("rlib" | "rmeta")
            )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Mapping from a host-specific absolute root to a stable key placeholder.
pub struct PathMapping {
    /// Absolute host path to replace.
    pub root: PathBuf,
    /// Placeholder name without the surrounding `${...}` syntax.
    pub placeholder: String,
}

impl PathMapping {
    /// Map an absolute host path to a stable cache-key placeholder.
    pub fn new(root: impl Into<PathBuf>, placeholder: impl Into<String>) -> Self {
        Self {
            root: root.into(),
            placeholder: placeholder.into(),
        }
    }

    /// Order mappings deepest root first, which is what normalization needs:
    /// a target directory inside the workspace has to win over the workspace.
    pub fn ordered(mappings: &[PathMapping]) -> Vec<PathMapping> {
        let mut ordered = mappings.to_vec();
        ordered.sort_by_key(|mapping| std::cmp::Reverse(mapping.root.components().count()));
        ordered
    }
}

fn shared_path_mappings(mappings: &[PathMapping]) -> Vec<SharedPathMapping> {
    mappings
        .iter()
        .map(|mapping| SharedPathMapping::new(&mapping.root, &mapping.placeholder))
        .collect()
}

/// Map an absolute path to its cache-key placeholder form.
///
/// `mappings` must already be ordered by [`PathMapping::ordered`]. Exposed for
/// callers that need the placeholder text before an action exists -- notably to
/// build the `--remap-path-prefix` flag that makes a compilation independent of
/// a path in its environment.
pub fn normalize_mapped_path(
    path: &Path,
    working_dir: &Path,
    mappings: &[PathMapping],
) -> Result<String, BypassReason> {
    normalize_shared_path(path, working_dir, &shared_path_mappings(mappings)).map_err(Into::into)
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Compiler properties that distinguish incompatible action outputs.
pub struct CompilerIdentity {
    /// Toolchain selector or installation identity.
    pub toolchain: String,
    /// Complete verbose rustc version string.
    pub rustc_version: String,
    /// Compiler host target triple.
    pub host: String,
    /// Identity of a compiler driver layered over rustc, when one is in use.
    pub driver: Option<String>,
}

/// One file input paired with the digest used in the action key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionInput {
    /// Absolute host path used to read and verify the input.
    pub path: PathBuf,
    /// Digest of the input contents.
    pub digest: CacheDigest,
}

/// External information needed to construct a canonical rustc action.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionContext {
    /// Identity of the compiler that produces the outputs.
    pub compiler: CompilerIdentity,
    /// Absolute directory in which rustc runs.
    pub working_dir: PathBuf,
    /// Host roots replaced with stable placeholders in the key.
    pub path_mappings: Vec<PathMapping>,
    /// Environment inputs and their observed values.
    pub environment: BTreeMap<String, Option<String>>,
    /// Environment inputs whose absolute values the compilation has been made
    /// independent of, and whose values the key therefore normalizes.
    ///
    /// Naming one here is a claim about the compilation, not a preference: the
    /// caller must both neutralize the value inside it (with
    /// `--remap-path-prefix`) and confirm no output carries the value anyway.
    pub portable_environment: BTreeSet<String>,
    /// Complete set of direct and discovered file inputs.
    pub inputs: Vec<ActionInput>,
}

/// What produced a linked native program, beyond the compiler itself.
///
/// The fields are identity rather than content wherever a compiler's own
/// identity is: a driver's version output names its toolchain more cheaply than
/// hashing a hundred megabytes of it, and matches how rustc is identified. The
/// CRT objects are hashed, because nothing else pins the libc a link resolves
/// against. Nothing here is placeholder-mapped -- these paths are host
/// locations rather than checkout locations, and two hosts that differ should
/// miss rather than share.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LinkerIdentity {
    /// Resolved absolute path of the linker driver rustc will invoke.
    pub driver: String,
    /// Version output of that driver.
    pub driver_version: String,
    /// Version of the linker the driver selects.
    pub linker_version: String,
    /// Startup objects and libc the driver resolves, by probe name.
    #[serde(skip_serializing_if = "BTreeMap::is_empty", default)]
    pub crt_objects: BTreeMap<String, CacheDigest>,
    /// Platform SDK identity, where the platform has one.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub sdk: Option<String>,
    /// Deployment target the link was made against, where one applies.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub deployment_target: Option<String>,
}

/// Canonical action descriptor and its content digest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RustcAction {
    /// Digest of `bytes`, used as the action-cache key.
    pub digest: CacheDigest,
    /// Canonical serialized action descriptor.
    pub bytes: Vec<u8>,
}

/// Normalized input names from the last successful execution of one modeled
/// rustc invocation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RustcInputPrediction {
    /// Prediction schema version.
    pub version: u8,
    /// Normalized input paths observed during the successful invocation.
    pub inputs: Vec<String>,
    /// Names of environment variables read by the compilation.
    pub environment: Vec<String>,
    /// Compiler wall time from the successful invocation that produced this
    /// prediction. Zero means no timing hint was recorded.
    pub compiler_duration_ns: u64,
    /// Crate name associated with the timing hint.
    pub crate_name: String,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct RustcInputPredictionWire {
    version: u8,
    inputs: Vec<String>,
    environment: Vec<String>,
    #[serde(default, skip_serializing_if = "is_zero")]
    compiler_duration_ns: u64,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    crate_name: String,
}

impl Serialize for RustcInputPrediction {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        RustcInputPredictionWire {
            version: self.version,
            inputs: if self.version == 4 {
                compact_prediction_inputs(&self.inputs)
            } else {
                self.inputs.clone()
            },
            environment: self.environment.clone(),
            compiler_duration_ns: self.compiler_duration_ns,
            crate_name: self.crate_name.clone(),
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for RustcInputPrediction {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let wire = RustcInputPredictionWire::deserialize(deserializer)?;
        let inputs = if wire.version == 4 {
            expand_prediction_inputs(&wire.inputs).map_err(serde::de::Error::custom)?
        } else {
            wire.inputs
        };
        Ok(Self {
            version: wire.version,
            inputs,
            environment: wire.environment,
            compiler_duration_ns: wire.compiler_duration_ns,
            crate_name: wire.crate_name,
        })
    }
}

fn compact_prediction_inputs(inputs: &[String]) -> Vec<String> {
    let mut previous = "";
    inputs
        .iter()
        .map(|input| {
            let mut shared = previous
                .bytes()
                .zip(input.bytes())
                .take_while(|(left, right)| left == right)
                .count();
            while !input.is_char_boundary(shared) {
                shared -= 1;
            }
            let compact = format!("{shared}:{}", &input[shared..]);
            previous = input;
            compact
        })
        .collect()
}

fn expand_prediction_inputs(inputs: &[String]) -> Result<Vec<String>, &'static str> {
    let mut expanded: Vec<String> = Vec::with_capacity(inputs.len());
    let mut decoded_bytes = 0_usize;
    for input in inputs {
        let (shared_text, suffix) = input
            .split_once(':')
            .ok_or("compact rustc prediction input has no prefix length")?;
        let shared: usize = shared_text
            .parse()
            .map_err(|_| "compact rustc prediction prefix length is invalid")?;
        if shared.to_string() != shared_text
            || shared > expanded.last().map_or(0, String::len)
            || expanded
                .last()
                .is_some_and(|previous| !previous.is_char_boundary(shared))
        {
            return Err("compact rustc prediction prefix is not canonical");
        }
        let mut path = expanded
            .last()
            .map_or_else(String::new, |previous| previous[..shared].to_string());
        path.push_str(suffix);
        decoded_bytes = decoded_bytes
            .checked_add(path.len())
            .ok_or("compact rustc prediction is too large")?;
        if decoded_bytes > MAX_DECODED_PREDICTION_BYTES {
            return Err("compact rustc prediction is too large");
        }
        expanded.push(path);
    }
    Ok(expanded)
}

fn is_zero(value: &u64) -> bool {
    *value == 0
}

impl RustcInputPrediction {
    /// Rehash the predicted paths and read the current environment. The caller
    /// still recomputes the full action digest, so changed inputs are misses.
    pub fn discover(
        &self,
        working_dir: &Path,
        path_mappings: &[PathMapping],
        digests: &dyn FileDigestCache,
    ) -> Result<DiscoveredInputs, BypassReason> {
        if !matches!(self.version, 2..=4) {
            return Err(BypassReason::UnsupportedPrediction);
        }
        if self.inputs.len() > MAX_PREDICTED_INPUTS || self.environment.len() > 4 * 1024 {
            return Err(BypassReason::UnsupportedPrediction);
        }
        let mut paths = BTreeSet::new();
        let mut named = BTreeSet::new();
        let admitted_roots = dep_info::native_input_roots(working_dir, path_mappings);
        let mut native_bytes = 0_u64;
        for path in &self.inputs {
            if self.version >= 3
                && let Some(path) = path.strip_prefix(NATIVE_DIRECTORY_PREDICTION_PREFIX)
            {
                let directory = denormalize_path(path, path_mappings)?;
                dep_info::collect_native_directory(
                    &directory,
                    &admitted_roots,
                    &mut paths,
                    &mut native_bytes,
                )?;
            } else {
                let path = denormalize_path(path, path_mappings)?;
                named.insert(path.clone());
                paths.insert(path);
            }
        }
        let native_only = paths.difference(&named).cloned().collect();
        let environment = self
            .environment
            .iter()
            .map(|name| {
                if name.is_empty() || name.contains(['=', '\0']) {
                    return Err(BypassReason::UnsupportedPrediction);
                }
                let value = std::env::var_os(name)
                    .map(|value| {
                        value
                            .into_string()
                            .map_err(|_| BypassReason::UnsupportedPrediction)
                    })
                    .transpose()?;
                Ok((name.clone(), value))
            })
            .collect::<Result<BTreeMap<_, _>, _>>()?;
        Ok(
            DiscoveredInputs::from_paths(working_dir, paths, environment, digests)?
                .with_native_only(native_only),
        )
    }
}

#[derive(Serialize)]
struct ActionDescriptor {
    version: u8,
    kind: &'static str,
    adapter_version: u8,
    compiler: CompilerDescriptor,
    arguments: Vec<String>,
    environment: BTreeMap<String, Option<String>>,
    inputs: Vec<InputDescriptor>,
    /// Omitted entirely unless the invocation links natively, so every key
    /// written before this field existed still serializes to the same bytes.
    #[serde(skip_serializing_if = "Option::is_none")]
    linker: Option<LinkerIdentity>,
}

#[derive(Serialize)]
struct InvocationDescriptor {
    version: u8,
    kind: &'static str,
    adapter_version: u8,
    compiler: CompilerDescriptor,
    arguments: Vec<String>,
    required_inputs: Vec<String>,
}

#[derive(Serialize)]
struct CompilerDescriptor {
    toolchain: String,
    rustc_version: String,
    host: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    driver: Option<String>,
}

#[derive(Debug, Serialize, PartialEq, Eq, PartialOrd, Ord)]
struct InputDescriptor {
    path: String,
    digest: CacheDigest,
}

/// The static-library file names a built-in target uses.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum StaticLibraryNaming {
    /// `NAME.lib`, then the Unix spelling as a fallback.
    Msvc,
    /// `libNAME.a`.
    Unix,
}

struct Parser<'a> {
    arguments: &'a [OsString],
    index: usize,
    parsed: Vec<Argument>,
    source: Option<PathBuf>,
    crate_types: Vec<String>,
    emits: Vec<Emit>,
    required_inputs: Vec<PathBuf>,
    native_libraries: Vec<String>,
    test: bool,
    crate_name: Option<String>,
    extra_filename: String,
    out_dir: Option<PathBuf>,
    explicit_output: Option<PathBuf>,
    target: Option<String>,
    sysroot_backend: Option<String>,
    options: ParseOptions,
}

struct ExpandedArguments {
    arguments: Vec<OsString>,
}

#[derive(Default)]
struct ResponseExpander {
    shell_argfiles: bool,
    next_is_unstable_option: bool,
    arguments: Vec<OsString>,
}

impl ResponseExpander {
    fn push(&mut self, argument: String) {
        if self.next_is_unstable_option {
            self.shell_argfiles |= argument == "shell-argfiles";
            self.next_is_unstable_option = false;
        } else if let Some(option) = argument.strip_prefix("-Z") {
            if option.is_empty() {
                self.next_is_unstable_option = true;
            } else {
                self.shell_argfiles |= option == "shell-argfiles";
            }
        }
        self.arguments.push(argument.into());
    }
}

/// Match rustc's argfile expansion: UTF-8, one option per line, no recursive
/// expansion, with the nightly shell form enabled only after its `-Z` flag.
fn expand_response_files(arguments: &[OsString]) -> Result<ExpandedArguments, BypassReason> {
    let mut expanded = ResponseExpander::default();
    for (index, argument) in arguments.iter().enumerate() {
        let argument = argument
            .to_str()
            .ok_or(BypassReason::NonUtf8Argument { index })?;
        let Some(argfile) = argument.strip_prefix('@') else {
            expanded.push(argument.to_string());
            continue;
        };
        let (path, shell) = match argfile.split_once(':') {
            Some(("shell", path)) if expanded.shell_argfiles => (path, true),
            _ => (argfile, false),
        };
        let contents = std::fs::read_to_string(path).map_err(|error| {
            BypassReason::ResponseFile(format!("{}: {error}", Path::new(path).display()))
        })?;
        if shell {
            let arguments = shlex::split(&contents).ok_or_else(|| {
                BypassReason::ResponseFile(format!(
                    "invalid shell-style arguments in {}",
                    Path::new(path).display()
                ))
            })?;
            for argument in arguments {
                expanded.push(argument);
            }
        } else {
            for argument in contents.lines() {
                expanded.push(argument.to_string());
            }
        }
    }
    Ok(ExpandedArguments {
        arguments: expanded.arguments,
    })
}

impl<'a> Parser<'a> {
    fn new(arguments: &'a [OsString], options: ParseOptions) -> Self {
        Self {
            arguments,
            options,
            index: 0,
            parsed: Vec::new(),
            source: None,
            crate_types: Vec::new(),
            emits: Vec::new(),
            required_inputs: Vec::new(),
            native_libraries: Vec::new(),
            test: false,
            crate_name: None,
            extra_filename: String::new(),
            out_dir: None,
            explicit_output: None,
            target: None,
            sysroot_backend: None,
        }
    }

    fn parse(mut self) -> Result<RustcInvocation, BypassReason> {
        while self.index < self.arguments.len() {
            let value = self.current()?.to_string();
            self.index += 1;
            if let Some(long) = value.strip_prefix("--") {
                self.parse_long(long)?;
            } else if value.starts_with('-') && value != "-" {
                self.parse_short(&value)?;
            } else {
                self.parse_input(&value)?;
            }
        }

        // rustc searches an explicit sysroot for the backend first, and only the compiler's own is hashed.
        if let Some(backend) = self.sysroot_backend.take()
            && self.parsed.iter().any(
                |argument| matches!(argument, Argument::Path { flag, .. } if flag == "--sysroot"),
            )
        {
            return Err(BypassReason::UnknownFlag(backend));
        }
        let source = self.source.clone().ok_or(BypassReason::MissingInput)?;
        let link_output = self.classify()?;
        self.require_native_libraries(link_output)?;
        let crate_name = self.crate_name.clone().map_or_else(
            || {
                source
                    .file_stem()
                    .and_then(|name| name.to_str())
                    .map(|name| name.replace('-', "_"))
                    .ok_or_else(|| BypassReason::NonUtf8Path(source.clone()))
            },
            Ok,
        )?;
        self.required_inputs.push(source.clone());
        Ok(RustcInvocation {
            arguments: self.parsed,
            source,
            required_inputs: self.required_inputs,
            crate_name,
            extra_filename: self.extra_filename,
            out_dir: self.out_dir,
            explicit_output: self.explicit_output,
            emits: self.emits,
            target: self.target,
            link_output,
        })
    }

    fn current(&self) -> Result<&str, BypassReason> {
        self.arguments[self.index]
            .to_str()
            .ok_or(BypassReason::NonUtf8Argument { index: self.index })
    }

    fn take_value(&mut self, flag: &str, inline: Option<&str>) -> Result<String, BypassReason> {
        if let Some(value) = inline {
            if value.is_empty() {
                return Err(BypassReason::MissingValue(flag.into()));
            }
            return Ok(value.into());
        }
        if self.index >= self.arguments.len() {
            return Err(BypassReason::MissingValue(flag.into()));
        }
        let value = self.current()?.to_string();
        self.index += 1;
        Ok(value)
    }

    fn parse_long(&mut self, value: &str) -> Result<(), BypassReason> {
        let (flag, inline) = value
            .split_once('=')
            .map_or((value, None), |(flag, value)| (flag, Some(value)));
        let rendered_flag = format!("--{flag}");
        match flag {
            "help" | "version" | "explain" | "print" => Err(BypassReason::CompilerQuery),
            "test" => {
                self.test = true;
                self.parsed.push(Argument::Plain(rendered_flag));
                Ok(())
            }
            "verbose" => {
                self.parsed.push(Argument::Plain(rendered_flag));
                Ok(())
            }
            "crate-name" => {
                let value = self.take_value(&rendered_flag, inline)?;
                self.crate_name = Some(value.clone());
                self.parsed
                    .push(Argument::Plain(format!("{rendered_flag}={value}")));
                Ok(())
            }
            "cfg" | "check-cfg" | "edition" | "error-format" | "json" | "color"
            | "diagnostic-width" | "remap-path-scope" | "allow" | "warn" | "force-warn"
            | "deny" | "forbid" | "cap-lints" => {
                let value = self.take_value(&rendered_flag, inline)?;
                self.parsed
                    .push(Argument::Plain(format!("{rendered_flag}={value}")));
                Ok(())
            }
            "target" => {
                let value = self.take_value(&rendered_flag, inline)?;
                // rustc reads the first `--target`, as getopts does; a later
                // one is still keyed as an argument but does not decide the
                // target, so it is not read and not a required input either.
                let effective = self.target.is_none();
                if effective {
                    self.target = Some(value.clone());
                }
                if value.ends_with(".json") || value.contains(['/', '\\']) {
                    let path = PathBuf::from(value);
                    if effective {
                        self.required_inputs.push(path.clone());
                    }
                    self.parsed.push(Argument::Path {
                        flag: rendered_flag,
                        path,
                    });
                } else {
                    self.parsed
                        .push(Argument::Plain(format!("{rendered_flag}={value}")));
                }
                Ok(())
            }
            "crate-type" => {
                let value = self.take_value(&rendered_flag, inline)?;
                self.crate_types
                    .extend(value.split(',').map(ToOwned::to_owned));
                self.parsed
                    .push(Argument::Plain(format!("{rendered_flag}={value}")));
                Ok(())
            }
            "emit" => {
                let value = self.take_value(&rendered_flag, inline)?;
                let emits = parse_emits(&value);
                self.emits.extend(emits.clone());
                self.parsed.push(Argument::Emit(emits));
                Ok(())
            }
            "out-dir" => {
                let path = PathBuf::from(self.take_value(&rendered_flag, inline)?);
                self.out_dir = Some(path.clone());
                self.parsed.push(Argument::Path {
                    flag: rendered_flag,
                    path,
                });
                Ok(())
            }
            "sysroot" => {
                let path = self.take_value(&rendered_flag, inline)?;
                self.parsed.push(Argument::Path {
                    flag: rendered_flag,
                    path: path.into(),
                });
                Ok(())
            }
            "extern" => {
                let value = self.take_value(&rendered_flag, inline)?;
                let (name, path) = value
                    .split_once('=')
                    .map_or((value.as_str(), None), |(name, path)| {
                        (name, Some(PathBuf::from(path)))
                    });
                if let Some(path) = &path {
                    self.required_inputs.push(path.clone());
                }
                self.parsed.push(Argument::Extern {
                    name: name.into(),
                    path,
                });
                Ok(())
            }
            "remap-path-prefix" => {
                let value = self.take_value(&rendered_flag, inline)?;
                let Some((from, to)) = value.split_once('=') else {
                    return Err(BypassReason::MissingValue(rendered_flag));
                };
                self.parsed.push(Argument::RemapPath {
                    from: from.into(),
                    to: to.into(),
                });
                Ok(())
            }
            "codegen" => {
                let value = self.take_value(&rendered_flag, inline)?;
                self.parse_codegen(&value)
            }
            "jobs-frontend" => {
                let value = self.take_value(&rendered_flag, inline)?;
                self.parsed
                    .push(Argument::Plain(format!("{rendered_flag}={value}")));
                Ok(())
            }
            _ => Err(BypassReason::UnknownFlag(rendered_flag)),
        }
    }

    fn parse_short(&mut self, value: &str) -> Result<(), BypassReason> {
        if let Some(attached) = value.strip_prefix("-Z") {
            let option = self.take_value("-Z", (!attached.is_empty()).then_some(attached))?;
            match option.as_str() {
                // Cargo passes `force-unstable-if-unmarked` to every standard
                // library unit under `-Zbuild-std`. It changes the stability
                // recorded in the crate's metadata, so it stays in the key.
                "embed-metadata=no"
                | "embed-metadata=yes"
                | "force-unstable-if-unmarked"
                | "shell-argfiles"
                | "unstable-options" => {
                    self.parsed.push(Argument::Plain(format!("-Z{option}")));
                    return Ok(());
                }
                // Selects a distinct unwind-table encoding. Preserve the
                // exact value in the action key; reject other spellings.
                "use-sync-unwind=yes" | "use-sync-unwind=no" => {
                    self.parsed.push(Argument::Plain(format!("-Z{option}")));
                    return Ok(());
                }
                "threads" | "threads=" => {
                    return Err(BypassReason::MissingValue("-Zthreads".into()));
                }
                _ => {}
            }
            if option.starts_with("threads=") {
                self.parsed.push(Argument::Plain(format!("-Z{option}")));
                return Ok(());
            }
            // rustc loads a value containing a `.` as a library path, which the key doesn't hash.
            if let Some(backend) = option.strip_prefix("codegen-backend=")
                && !backend.is_empty()
                && !backend.contains(['.', '/', '\\'])
            {
                self.sysroot_backend = Some(format!("-Z{option}"));
                self.parsed.push(Argument::Plain(format!("-Z{option}")));
                return Ok(());
            }
            return Err(BypassReason::UnknownFlag(format!("-Z{option}")));
        }
        match value {
            // `-vV` is how cargo and build scripts ask for the verbose
            // version, so it is a query rather than a flag left unmodeled.
            "-h" | "-V" | "-vV" => return Err(BypassReason::CompilerQuery),
            "-g" | "-O" | "-v" => {
                self.parsed.push(Argument::Plain(value.into()));
                return Ok(());
            }
            _ => {}
        }
        for (short, long) in [
            ("-A", "--allow"),
            ("-W", "--warn"),
            ("-D", "--deny"),
            ("-F", "--forbid"),
        ] {
            if let Some(attached) = value.strip_prefix(short) {
                let lint = self.take_value(short, (!attached.is_empty()).then_some(attached))?;
                self.parsed.push(Argument::Plain(format!("{long}={lint}")));
                return Ok(());
            }
        }
        if let Some(attached) = value.strip_prefix("-C") {
            let option = self.take_value("-C", (!attached.is_empty()).then_some(attached))?;
            return self.parse_codegen(&option);
        }
        if let Some(attached) = value.strip_prefix("-L") {
            let search = self.take_value("-L", (!attached.is_empty()).then_some(attached))?;
            let (kind, path) = search
                .split_once('=')
                .map_or(("all", search.as_str()), |(kind, path)| (kind, path));
            if !matches!(kind, "dependency" | "native") {
                return Err(BypassReason::UnsupportedSearchPath(kind.into()));
            }
            self.parsed.push(Argument::SearchPath {
                kind: kind.into(),
                path: path.into(),
            });
            return Ok(());
        }
        if let Some(attached) = value.strip_prefix("-l") {
            let library = self.take_value("-l", (!attached.is_empty()).then_some(attached))?;
            self.parsed.push(Argument::Plain(format!("-l{library}")));
            self.native_libraries.push(library);
            return Ok(());
        }
        if let Some(attached) = value.strip_prefix("-o") {
            let path = self.take_value("-o", (!attached.is_empty()).then_some(attached))?;
            self.explicit_output = Some(path.clone().into());
            self.parsed.push(Argument::Path {
                flag: "-o".into(),
                path: path.into(),
            });
            return Ok(());
        }
        Err(BypassReason::UnknownFlag(value.into()))
    }

    fn parse_codegen(&mut self, value: &str) -> Result<(), BypassReason> {
        let name = value.split_once('=').map_or(value, |(name, _)| name);
        if name == "incremental" {
            return Err(BypassReason::Incremental);
        }
        if SUPPORTED_CODEGEN_OPTIONS.binary_search(&name).is_err() && name != "linker" {
            return Err(BypassReason::UnknownCodegenOption(name.into()));
        }
        // Cargo compiles every dependency of an LTO build with this flag, so
        // the rlibs carry bitcode for the final link to optimize across. The
        // switch is keyed as text like any other option. A value naming the
        // linker plugin is a host file the key does not describe, so that
        // spelling still bypasses.
        if name == "linker-plugin-lto"
            && let Some((_, selection)) = value.split_once('=')
            && !matches!(
                selection,
                "" | "y" | "yes" | "on" | "true" | "n" | "no" | "off" | "false"
            )
        {
            return Err(BypassReason::UnknownCodegenOption(format!(
                "linker-plugin-lto={selection}"
            )));
        }
        // `-fuse-ld=<name>` selects the linker the driver invokes. Parsed
        // rather than keyed as text so the linker identity probe can pin the
        // selected linker; a repeated selection dedups, and a conflicting
        // second selection falls through to Plain, which native-link handling
        // declines to model. The driver honors the last selection, so a
        // conflict is a link whose linker this adapter cannot name.
        if name == "link-arg"
            && let Some((_, option)) = value.split_once('=')
            && let Some(selection) = option.strip_prefix("-fuse-ld=")
            && !selection.is_empty()
            && !selection.contains(',')
            && !self.parsed.iter().any(
                |argument| matches!(argument, Argument::FuseLd(existing) if existing != selection),
            )
        {
            if !self.parsed.iter().any(
                |argument| matches!(argument, Argument::FuseLd(existing) if existing == selection),
            ) {
                self.parsed.push(Argument::FuseLd(selection.to_owned()));
            }
            return Ok(());
        }
        // Only a single filename under @rpath is modeled. Other spellings,
        // combined linker options, and explicit absolute names still bypass.
        if name == "link-arg"
            && let Some(option) = value.strip_prefix("link-arg=-Wl,-install_name,@rpath/")
            && safe_install_name(option)
        {
            self.parsed.push(Argument::InstallName(option.to_owned()));
            return Ok(());
        }
        // `-oso_prefix` names a checkout-specific path, so it is parsed
        // rather than keyed as text: the path normalizes like every other
        // path in the key, which is what lets two checkouts passing their own
        // prefixes agree on one action.
        if matches!(name, "link-arg" | "link-args")
            && let Some((_, option)) = value.split_once('=')
            && let Some(prefix) = option.strip_prefix("-Wl,-oso_prefix,")
            && !prefix.trim_end_matches('/').is_empty()
            && !prefix.contains(',')
        {
            let trailing_slash = prefix.ends_with('/');
            self.parsed.push(Argument::OsoPrefix {
                path: PathBuf::from(prefix.trim_end_matches('/')),
                trailing_slash,
            });
            return Ok(());
        }
        self.parsed
            .push(Argument::Plain(format!("--codegen={value}")));
        if name == "extra-filename" {
            self.extra_filename = value
                .split_once('=')
                .map_or(String::new(), |(_, value)| value.to_string());
        }
        Ok(())
    }

    /// Model what rustc reads for each `-l`, now that the emit is known.
    ///
    /// A library emit runs no linker. For `dylib`, `framework`, `link-arg`,
    /// and an unspecified kind, rustc only records the name in the crate's
    /// metadata, so the flag text already in the key is the whole input. A
    /// `static` library is different: rustc opens the archive and bundles its
    /// members into the rlib, so the archive's content decides the output. It
    /// is found the way rustc finds it and named as a required input, keyed
    /// by content exactly like an `--extern` artifact. With `-bundle` rustc
    /// records the name for a downstream link instead of reading the archive,
    /// so that flag is text like the name-only kinds.
    ///
    /// A linked output hands every `-l` to its linker, whose search is not
    /// modeled here, so those still bypass whatever the kind.
    fn require_native_libraries(&mut self, link_output: LinkOutput) -> Result<(), BypassReason> {
        for library in std::mem::take(&mut self.native_libraries) {
            if link_output != LinkOutput::Library {
                return Err(BypassReason::NativeLibrary(library));
            }
            // `-l [KIND[:MODIFIERS]=]NAME[:RENAME]`. Without a kind the
            // library is rustc's "unspecified" kind: it is handed to the
            // linker of whatever finally links, and an rlib only records the
            // name. rustc bundles into an rlib only what `-l static` names
            // (`link_rlib` takes `NativeLibKind::Static` with bundling on),
            // so a `libNAME.a` that later appears beside a plain `-l NAME`
            // changes that final link, not this compilation.
            let Some((kind, name)) = library.split_once('=') else {
                continue;
            };
            let (kind, modifiers) = kind.split_once(':').unwrap_or((kind, ""));
            match kind {
                "static" => {}
                "dylib" | "framework" | "link-arg" => continue,
                _ => return Err(BypassReason::UnknownFlag(format!("-l{library}"))),
            }
            // A rename links RENAME in place of the NAME a `#[link]` attribute
            // gave, so RENAME is the archive on disk.
            let name = name.split_once(':').map_or(name, |(_, renamed)| renamed);
            let (mut verbatim, mut bundle) = (false, true);
            for modifier in modifiers.split(',') {
                match modifier {
                    "+verbatim" => verbatim = true,
                    "-verbatim" => verbatim = false,
                    "+bundle" => bundle = true,
                    "-bundle" => bundle = false,
                    _ => {}
                }
            }
            if !bundle {
                continue;
            }
            let archive = self
                .find_native_static_library(name, verbatim)
                .map_err(|()| BypassReason::CustomTargetNativeLibrary(library.clone()))?
                .ok_or_else(|| BypassReason::MissingNativeLibrary(library.clone()))?;
            self.required_inputs.push(archive);
        }
        Ok(())
    }

    /// Resolve a static library the way rustc does: the first `-L native`
    /// directory, in command-line order, holding the target's file name for
    /// it. rustc would also search a plain `-L` directory, but that kind
    /// already bypasses as unsupported before it gets here. Targets with
    /// MSVC-style libraries (Windows MSVC and UEFI) accept `NAME.lib` before
    /// falling back to the `libNAME.a` every built-in target otherwise uses;
    /// `+verbatim` names the file literally. A custom target specification
    /// sets its own prefix and suffix, which are not read here, so it is an
    /// `Err` rather than a guess that could hash a different archive than
    /// rustc bundles. A relative search directory resolves against the
    /// process working directory, as it does for rustc.
    fn find_native_static_library(
        &self,
        name: &str,
        verbatim: bool,
    ) -> Result<Option<PathBuf>, ()> {
        let file_names = if verbatim {
            vec![name.to_owned()]
        } else {
            match self.static_library_naming() {
                Some(StaticLibraryNaming::Msvc) => {
                    vec![format!("{name}.lib"), format!("lib{name}.a")]
                }
                Some(StaticLibraryNaming::Unix) => vec![format!("lib{name}.a")],
                None => return Err(()),
            }
        };
        Ok(self
            .parsed
            .iter()
            .filter_map(|argument| match argument {
                Argument::SearchPath { kind, path } if kind == "native" => Some(path),
                _ => None,
            })
            .flat_map(|directory| {
                file_names
                    .iter()
                    .map(move |file_name| directory.join(file_name))
            })
            .find(|candidate| candidate.is_file()))
    }

    /// How the target names a static library, or `None` for a custom target
    /// specification, whose names only the specification knows.
    ///
    /// A bare name is a built-in target unless a specification file for it
    /// exists where rustc would look, under `RUST_TARGET_PATH` or in the
    /// sysroot, which the caller reports through
    /// [`ParseOptions::custom_target_search`].
    fn static_library_naming(&self) -> Option<StaticLibraryNaming> {
        let Some(target) = self.target.as_deref() else {
            return Some(if cfg!(any(target_env = "msvc", target_os = "uefi")) {
                StaticLibraryNaming::Msvc
            } else {
                StaticLibraryNaming::Unix
            });
        };
        if target.ends_with(".json")
            || target.contains(['/', '\\'])
            || self.options.custom_target_search
        {
            return None;
        }
        // rustc's `is_like_msvc` targets: `*-windows-msvc`, `*-win7-windows-msvc`,
        // and the UEFI targets, which borrow the MSVC toolchain's conventions.
        Some(if target.contains("msvc") || target.ends_with("-uefi") {
            StaticLibraryNaming::Msvc
        } else {
            StaticLibraryNaming::Unix
        })
    }

    fn parse_input(&mut self, value: &str) -> Result<(), BypassReason> {
        if value == "-" {
            return Err(BypassReason::StandardInput);
        }
        if self.source.replace(value.into()).is_some() {
            return Err(BypassReason::MultipleInputs);
        }
        Ok(())
    }

    fn classify(&self) -> Result<LinkOutput, BypassReason> {
        // A compilation that emits no `link` produces exactly what an rlib's
        // metadata emit does -- dep-info and `lib<name>.rmeta` -- whatever it
        // calls its crate type. `cargo check` and clippy compile every binary
        // and test target this way, and those were bypassing as an
        // unsupported crate type for a linked artifact none of them asked
        // for. No linker runs, so nothing downstream needs a linker identity
        // to describe, and rustc names the metadata the same way for every
        // crate type.
        let never_links = !self.emits.iter().any(|emit| emit.kind == "link");
        let builds_a_library = !self.test
            && !self.crate_types.is_empty()
            && self
                .crate_types
                .iter()
                .all(|crate_type| matches!(crate_type.as_str(), "lib" | "rlib"));
        let link_output = if never_links || builds_a_library {
            LinkOutput::Library
        } else if self
            .target
            .as_deref()
            .is_some_and(compiler_bundled_wasm_target)
            && ((self.test && self.crate_types.is_empty())
                || matches!(self.crate_types.as_slice(), [kind] if kind == "bin" || kind == "cdylib"))
        {
            if self.parsed.iter().any(|argument| match argument {
                Argument::Plain(value) if value == "--codegen=link-self-contained" => false,
                Argument::Plain(value) if value.starts_with("--codegen=link-self-contained=") => {
                    !matches!(
                        value.rsplit_once('=').map(|(_, value)| value),
                        Some("y" | "yes" | "on" | "true")
                    )
                }
                _ => false,
            }) {
                return Err(BypassReason::UnknownCodegenOption(
                    "link-self-contained".into(),
                ));
            }
            if self.target.as_deref().is_some_and(|target| target.contains("wasi"))
                && self.parsed.iter().any(|argument| {
                    matches!(argument, Argument::Plain(value) if value.strip_prefix("--codegen=target-feature=").is_some_and(|features| features.split(',').any(|feature| feature == "-crt-static")))
                })
            {
                return Err(BypassReason::UnknownCodegenOption(
                    "target-feature=-crt-static".into(),
                ));
            }
            // These targets use a linker and, where applicable, CRT objects
            // and libc shipped in the Rust toolchain. Unlike native linking,
            // there are no implicit host inputs outside compiler identity.
            LinkOutput::WasmExecutable
        } else if self.options.cache_native_links && self.links_a_native_artifact() {
            self.check_native_link_is_portable()?;
            if matches!(self.crate_types.as_slice(), [kind] if kind == "proc-macro") {
                LinkOutput::NativeProcMacro
            } else if matches!(self.crate_types.as_slice(), [kind] if kind == "cdylib") {
                LinkOutput::NativeSharedLibrary
            } else {
                LinkOutput::NativeExecutable
            }
        } else if self.test {
            return Err(BypassReason::UnsupportedCrateType("test".into()));
        } else {
            return Err(BypassReason::UnsupportedCrateType(
                self.crate_types
                    .iter()
                    .find(|crate_type| !matches!(crate_type.as_str(), "lib" | "rlib"))
                    .cloned()
                    .unwrap_or_else(|| "bin".into()),
            ));
        };
        // A link argument is handed to the linker verbatim, and its text is all
        // the adapter has to go on. `-Clink-arg=-Tlink.x` names a linker script
        // resolved off the search path, `-Clink-arg=-fuse-ld=lld` replaces the
        // linker the identity in the key describes, and neither is told apart
        // from `/STACK:8000000` by any rule short of knowing the linker's own
        // grammar. Where nothing links there is nothing to tell apart: an rlib
        // or an rmeta is produced without a linker invocation, so the option is
        // inert and the key carries its text like any other codegen option.
        if link_output != LinkOutput::Library
            && let Some(option) = self.first_link_argument(link_output)
        {
            return Err(BypassReason::UnmodeledLinkArgument(option.to_owned()));
        }
        if self
            .parsed
            .iter()
            .any(|arg| matches!(arg, Argument::InstallName(_)))
            && !(cfg!(target_os = "macos") && link_output == LinkOutput::NativeProcMacro)
        {
            return Err(BypassReason::UnmodeledLinkArgument(
                "link-arg=-Wl,-install_name".into(),
            ));
        }
        // `-fuse-ld` is modeled only for native links, where the linker
        // identity probe resolves and pins the linker it names. A wasm or
        // other non-native link consuming the selection has no identity that
        // describes it, so it declines the action like any other link
        // argument. Where nothing links, the selection is inert and the key
        // carries its text.
        if let Some(selection) = self.parsed.iter().find_map(|argument| {
            let Argument::FuseLd(selection) = argument else {
                return None;
            };
            Some(selection.as_str())
        }) && !matches!(
            link_output,
            LinkOutput::Library
                | LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        ) {
            return Err(BypassReason::UnmodeledLinkArgument(format!(
                "link-arg=-fuse-ld={selection}"
            )));
        }
        if self.parsed.iter().any(|argument| {
            matches!(argument, Argument::Plain(value) if value.starts_with("--codegen=linker="))
        }) && !matches!(
            link_output,
            LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        ) {
            return Err(BypassReason::UnknownCodegenOption("linker".into()));
        }
        // `-oso_prefix` is modeled, but only where ld64 is the linker reading
        // it: a native macOS link. Any other linker sees an option this
        // adapter cannot vouch for, exactly like the arguments above.
        if !matches!(
            link_output,
            LinkOutput::Library
                | LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        ) && self
            .parsed
            .iter()
            .any(|argument| matches!(argument, Argument::OsoPrefix { .. }))
        {
            return Err(BypassReason::UnmodeledLinkArgument(
                "link-arg=-Wl,-oso_prefix".into(),
            ));
        }
        if let Some(name) = self.parsed.iter().find_map(|argument| match argument {
            Argument::Extern { name, path: None } if name != "proc_macro" => Some(name),
            _ => None,
        }) {
            return Err(BypassReason::UnresolvedExtern(name.clone()));
        }
        if let Some(emit) = self
            .emits
            .iter()
            .find(|emit| !matches!(emit.kind.as_str(), "dep-info" | "link" | "metadata"))
        {
            return Err(BypassReason::UnsupportedEmit(emit.kind.clone()));
        }
        if !self
            .emits
            .iter()
            .any(|emit| matches!(emit.kind.as_str(), "link" | "metadata"))
        {
            return Err(BypassReason::NoCacheableOutput);
        }
        Ok(link_output)
    }
}

impl Parser<'_> {
    /// The first `-C link-arg` or `-C link-args` option in the invocation,
    /// rendered as it appears in the action key.
    fn first_link_argument(&self, link_output: LinkOutput) -> Option<&str> {
        self.parsed.iter().find_map(|argument| {
            let Argument::Plain(value) = argument else {
                return None;
            };
            let option = value.strip_prefix("--codegen=")?;
            let (name, value) = option.split_once('=').unwrap_or((option, ""));
            (matches!(name, "link-arg" | "link-args")
                && !(name == "link-arg" && elf_keyword_is_modeled(link_output, value))
                && !msvc_options_are_modeled(link_output, name, value))
            .then_some(option)
        })
    }

    /// Whether an `-oso_prefix` strips the directory this link's objects live
    /// in from the debug map ld64 records.
    ///
    /// The objects a native link reads -- this unit's own compiled objects
    /// and the rlibs it links -- sit in the output directory, so a prefix
    /// covering that directory leaves the debug map naming spellings every
    /// checkout shares. Toolchain objects stay absolute, as they do in the
    /// paths rustc itself embeds on every platform.
    fn oso_prefix_covers_outputs(&self) -> bool {
        let Some(directory) = self
            .out_dir
            .as_deref()
            .or_else(|| self.explicit_output.as_deref().and_then(Path::parent))
        else {
            return false;
        };
        if !directory.is_absolute() {
            return false;
        }
        let directory = normalize_components(directory);
        self.parsed.iter().any(|argument| {
            let Argument::OsoPrefix { path, .. } = argument else {
                return false;
            };
            path.is_absolute()
                && (directory.starts_with(normalize_components(path))
                    || std::fs::canonicalize(&directory)
                        .ok()
                        .zip(std::fs::canonicalize(path).ok())
                        .is_some_and(|(directory, prefix)| directory.starts_with(prefix)))
        })
    }

    /// Whether this invocation links an artifact for the host.
    ///
    /// An explicit `--target` bypasses even when it spells the host triple:
    /// rustc without one links for the host by construction, which is the
    /// cheapest description of "the linker this adapter can identify", and
    /// cargo omits it for host builds anyway.
    fn links_a_native_artifact(&self) -> bool {
        self.target.is_none()
            // A compilation that emits no linked artifact did not link, so it
            // needs no linker to describe it. `cargo check --tests` asks for
            // metadata alone, and reading that as a link would send it looking
            // for a linker identity and refusing flags no linker ever saw.
            && self.emits.iter().any(|emit| emit.kind == "link")
            && ((self.test && self.crate_types.is_empty())
                || matches!(self.crate_types.as_slice(), [kind] if matches!(kind.as_str(), "bin" | "proc-macro"))
                || (cfg!(target_os = "linux")
                    && matches!(self.crate_types.as_slice(), [kind] if kind == "cdylib")))
    }

    /// Reject a native link whose result depends on something the key cannot
    /// describe, or that leaves artifacts beside the ones tuist_cargo_cache would store.
    ///
    /// Each check names a value rather than a flag: an option absent from the
    /// invocation keeps rustc's default, which the compiler identity already
    /// pins, while any other spelling is refused rather than guessed at.
    fn check_native_link_is_portable(&self) -> Result<(), BypassReason> {
        for argument in &self.parsed {
            let Argument::Plain(value) = argument else {
                continue;
            };
            // `-g` is rustc's shorthand for debug info, and arrives as itself
            // rather than as a codegen option.
            let (name, value) = if value == "-g" {
                ("debuginfo", Some("2"))
            } else if let Some(option) = value.strip_prefix("--codegen=") {
                match option.split_once('=') {
                    Some((name, value)) => (name, Some(value)),
                    // A codegen flag with no value asks for its enabled form,
                    // which is what cargo passes for `-Crpath`. Reading it as
                    // "nothing to check" is how these slipped through.
                    None => (option, None),
                }
            } else {
                continue;
            };
            let unportable = match name {
                // Packed debug info leaves a .dSYM bundle or .dwp file beside
                // the binary, and tuist_cargo_cache stores neither. Unpacked is macOS's
                // debug-map arrangement -- debug info stays in the objects and
                // nothing lands beside the binary -- so the same covering
                // `-oso_prefix` that makes the debug map portable covers it.
                "split-debuginfo" => match value {
                    Some("off") => false,
                    Some("unpacked") if cfg!(target_os = "macos") => {
                        !self.oso_prefix_covers_outputs()
                    }
                    _ => true,
                },
                // ld64 records absolute object paths and their timestamps in
                // the binary's debug map, so the same source links to
                // different bytes in another checkout -- or the same one
                // twice. An `-oso_prefix` covering the output directory
                // strips those paths down to spellings every checkout
                // shares, which is the same leniency a Linux link already
                // gets for the paths rustc itself embeds; what remains
                // (object timestamps) only shows up under verification.
                "debuginfo" if cfg!(target_os = "macos") => {
                    !matches!(value, Some("0" | "none")) && !self.oso_prefix_covers_outputs()
                }
                // An rpath and a dynamically linked native program embed this
                // checkout's absolute target directory. Cargo also passes
                // `prefer-dynamic` to proc macros, but their dynamic runtime
                // is rustc's own sysroot (already pinned by compiler identity),
                // while Cargo's dependencies are linked into the macro. There
                // is no checkout rpath to carry; keep rejecting an explicit
                // `rpath` independently.
                "rpath" => is_enabled(value),
                "prefer-dynamic" => {
                    is_enabled(value)
                        && !matches!(self.crate_types.as_slice(), [kind] if kind == "proc-macro")
                }
                // The CRT objects a self-contained link uses come from
                // somewhere other than where the driver reports.
                "link-self-contained" => true,
                _ => false,
            };
            if unportable {
                return Err(BypassReason::UnportableNativeLink(match value {
                    Some(value) => format!("{name}={value}"),
                    None => name.to_owned(),
                }));
            }
        }
        Ok(())
    }
}

fn safe_install_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte))
}

/// Whether a boolean codegen option is asking for its enabled form. Absent a
/// value, rustc reads the flag itself as the request.
fn is_enabled(value: Option<&str>) -> bool {
    matches!(value, None | Some("y" | "yes" | "on" | "true"))
}

/// Whether `-Wl,-z,KEYWORD` is a native Linux link option the key can carry
/// as text.
///
/// A link argument is refused because its text cannot say whether it names a
/// file. These keywords are the exception: each sets a flag or a dynamic
/// section entry in the ELF output and reads nothing, in every linker the
/// identity probe resolves (GNU ld, gold, lld, and mold all spell them the
/// same). napi-build passes `-z nodelete` to every Node-API addon, so without
/// it no such addon caches.
fn elf_keyword_is_modeled(link_output: LinkOutput, value: &str) -> bool {
    cfg!(target_os = "linux")
        && matches!(
            link_output,
            LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        )
        && value.strip_prefix("-Wl,-z,").is_some_and(|keyword| {
            matches!(
                keyword,
                "defs"
                    | "lazy"
                    | "nodelete"
                    | "nodlopen"
                    | "noexecstack"
                    | "norelro"
                    | "now"
                    | "origin"
                    | "relro"
            )
        })
}

/// `-C link-arg` / `-C link-args` values that `link.exe` and `lld-link` read
/// as a plain switch or number and never as a file name.
///
/// `-C link-arg=/STACK:8000000` is how projects raise the main thread's stack
/// for Windows, usually through a `rustflags` entry in `.cargo/config.toml`
/// that reaches every proc macro, build script, and binary the workspace
/// builds. Refusing it leaves each of those linking on every build, and a MSVC
/// link is not reproducible (the PE header and PDB carry a timestamp and a
/// GUID), so each fresh proc-macro DLL hashes differently and every crate
/// compiled against it misses too.
///
/// Only spellings whose grammar is closed are listed: a number after
/// `/STACK:`, and `/Brepro`, which makes the link reproducible. Anything else
/// (`/DEF:`, `/MANIFESTINPUT:`, `/LIBPATH:`, a bare file name) can name a file
/// the key never hashes, so it still bypasses.
fn msvc_options_are_modeled(link_output: LinkOutput, name: &str, value: &str) -> bool {
    cfg!(target_env = "msvc")
        && matches!(
            link_output,
            LinkOutput::NativeExecutable
                | LinkOutput::NativeProcMacro
                | LinkOutput::NativeSharedLibrary
        )
        && match name {
            "link-arg" => msvc_option_reads_no_file(value),
            // The plural spelling is a whitespace-separated list, each entry
            // of which has to qualify.
            "link-args" => {
                let mut options = value.split_ascii_whitespace().peekable();
                options.peek().is_some() && options.all(msvc_option_reads_no_file)
            }
            _ => false,
        }
}

/// One MSVC linker option from the closed list in [`msvc_options_are_modeled`].
/// The linker takes `-` for `/` and ignores the case of option names, and so
/// does this.
fn msvc_option_reads_no_file(option: &str) -> bool {
    let Some(option) = option.strip_prefix(['/', '-']) else {
        return false;
    };
    if option.eq_ignore_ascii_case("brepro") {
        return true;
    }
    let Some((name, sizes)) = option.split_once(':') else {
        return false;
    };
    // `/STACK:reserve[,commit]`. Sizes are decimal or `0x` hexadecimal, and
    // nothing else, so a value cannot smuggle in a path.
    let is_size = |size: &str| match size.strip_prefix("0x").or_else(|| size.strip_prefix("0X")) {
        Some(hex) => !hex.is_empty() && hex.bytes().all(|byte| byte.is_ascii_hexdigit()),
        None => !size.is_empty() && size.bytes().all(|byte| byte.is_ascii_digit()),
    };
    name.eq_ignore_ascii_case("stack")
        && sizes.split(',').count() <= 2
        && sizes.split(',').all(is_size)
}

fn compiler_bundled_wasm_target(target: &str) -> bool {
    COMPILER_BUNDLED_WASM_TARGETS.binary_search(&target).is_ok()
}

fn parse_emits(value: &str) -> Vec<Emit> {
    value
        .split(',')
        .map(|emit| {
            let (kind, path) = emit
                .split_once('=')
                .map_or((emit, None), |(kind, path)| (kind, Some(path.into())));
            Emit {
                kind: kind.into(),
                path,
            }
        })
        .collect()
}

struct ActionBuilder<'a> {
    invocation: &'a RustcInvocation,
    context: ActionContext,
    mappings: Vec<SharedPathMapping>,
    /// The directories resolved while building this one action. Its inputs
    /// share a few parents, and resolving each once is what keeps a crate
    /// with hundreds of them from paying a `realpath` walk per input.
    aliases: PathAliases,
    linker: Option<LinkerIdentity>,
}

impl<'a> ActionBuilder<'a> {
    fn new(invocation: &'a RustcInvocation, mut context: ActionContext) -> Self {
        context.path_mappings = PathMapping::ordered(&context.path_mappings);
        let mappings = resolve_path_mappings(&shared_path_mappings(&context.path_mappings));
        Self {
            linker: None,
            invocation,
            mappings,
            aliases: PathAliases::default(),
            context,
        }
    }

    fn linked_by(mut self, linker: Option<LinkerIdentity>) -> Self {
        self.linker = linker;
        self
    }

    fn build(self) -> Result<RustcAction, BypassReason> {
        self.validate_mappings()?;
        let invocation = self.invocation_descriptor()?;
        let environment = self.environment_descriptor()?;

        let mut inputs = BTreeMap::<String, CacheDigest>::new();
        for input in &self.context.inputs {
            input
                .digest
                .validate()
                .map_err(|_| BypassReason::InvalidInputDigest(input.path.display().to_string()))?;
            let path = self.normalize_input_path(&input.path)?;
            if inputs
                .insert(path.clone(), input.digest.clone())
                .is_some_and(|existing| existing != input.digest)
            {
                return Err(BypassReason::ConflictingInput(path));
            }
        }
        let required = self
            .invocation
            .required_inputs
            .iter()
            .map(|path| self.normalize_input_path(path))
            .collect::<Result<BTreeSet<_>, _>>()?;
        if let Some(missing) = required.iter().find(|path| !inputs.contains_key(*path)) {
            return Err(BypassReason::MissingRequiredInput(missing.clone()));
        }
        let inputs = inputs
            .into_iter()
            .map(|(path, digest)| InputDescriptor { path, digest })
            .collect();
        // A native link without a linker identity would be keyed as though the
        // host did not matter. Refuse rather than publish that claim.
        if self.invocation.links_natively() && self.linker.is_none() {
            return Err(BypassReason::UnportableNativeLink(
                "linker identity is unknown".into(),
            ));
        }
        let descriptor = ActionDescriptor {
            version: ACTION_SCHEMA_VERSION,
            kind: "rustc",
            adapter_version: ADAPTER_VERSION,
            compiler: invocation.compiler,
            arguments: invocation.arguments,
            environment,
            inputs,
            linker: self.linker.clone(),
        };
        let bytes = canonical_json(&descriptor)
            .map_err(|error| BypassReason::Serialization(error.to_string()))?;
        let digest = CacheDigest::blake3(&bytes);
        Ok(RustcAction { digest, bytes })
    }

    fn invocation_descriptor(&self) -> Result<InvocationDescriptor, BypassReason> {
        self.validate_mappings()?;
        let arguments = self
            .invocation
            .arguments
            .iter()
            .map(|argument| self.normalize_argument(argument))
            .collect::<Result<Vec<_>, _>>()?;
        let required_inputs = self
            .invocation
            .required_inputs
            .iter()
            .map(|path| self.normalize_path(path))
            .collect::<Result<BTreeSet<_>, _>>()?
            .into_iter()
            .collect();
        Ok(InvocationDescriptor {
            version: ACTION_SCHEMA_VERSION,
            kind: "rustc",
            adapter_version: ADAPTER_VERSION,
            compiler: CompilerDescriptor {
                toolchain: self.context.compiler.toolchain.clone(),
                rustc_version: self.context.compiler.rustc_version.clone(),
                host: self.context.compiler.host.clone(),
                driver: self.context.compiler.driver.clone(),
            },
            arguments,
            required_inputs,
        })
    }

    fn validate_mappings(&self) -> Result<(), BypassReason> {
        if !self.context.working_dir.is_absolute() {
            return Err(BypassReason::RelativeWorkingDirectory(
                self.context.working_dir.clone(),
            ));
        }
        let mut roots = BTreeSet::new();
        let mut placeholders = BTreeSet::new();
        for mapping in &self.mappings {
            if !mapping.root.is_absolute() {
                return Err(BypassReason::RelativePathMapping(mapping.root.clone()));
            }
            if mapping.placeholder.is_empty()
                || !mapping
                    .placeholder
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
                || !roots.insert(normalize_components(&mapping.root))
                || !placeholders.insert(&mapping.placeholder)
            {
                return Err(BypassReason::InvalidPathPlaceholder(
                    mapping.placeholder.clone(),
                ));
            }
        }
        Ok(())
    }

    fn normalize_argument(&self, argument: &Argument) -> Result<String, BypassReason> {
        match argument {
            Argument::Plain(value) => Ok(value.clone()),
            Argument::Path { flag, path } => Ok(format!("{flag}={}", self.normalize_path(path)?)),
            Argument::SearchPath { kind, path } => {
                let text = self.normalize_path(path)?;
                Ok(format!("-L{kind}={text}"))
            }
            Argument::Extern { name, path } => match path {
                Some(path) => Ok(format!("--extern={name}={}", self.normalize_path(path)?)),
                None => Ok(format!("--extern={name}")),
            },
            Argument::Emit(emits) => Ok(format!(
                "--emit={}",
                emits
                    .iter()
                    .map(|emit| match &emit.path {
                        Some(path) => self
                            .normalize_path(path)
                            .map(|path| format!("{}={path}", emit.kind)),
                        None => Ok(emit.kind.clone()),
                    })
                    .collect::<Result<Vec<_>, _>>()?
                    .join(",")
            )),
            Argument::RemapPath { from, to } => Ok(format!(
                "--remap-path-prefix={}={}",
                self.normalize_path(from)?,
                to
            )),
            Argument::InstallName(name) => Ok(format!(
                "--codegen=link-arg=-Wl,-install_name,@rpath/{name}"
            )),
            Argument::OsoPrefix {
                path,
                trailing_slash,
            } => Ok(format!(
                "--codegen=link-arg=-Wl,-oso_prefix,{}{}",
                self.normalize_path(path)?,
                if *trailing_slash { "/" } else { "" }
            )),
            Argument::FuseLd(selection) => Ok(format!("--codegen=link-arg=-fuse-ld={selection}")),
        }
    }

    /// Environment values enter the key verbatim, because rustc may embed one
    /// through `env!`: unlike a path used to locate an input, changing the value
    /// changes the artifact.
    ///
    /// A name in `portable_environment` is the exception the caller has earned.
    /// Its value normalizes like any other path, so two checkouts agree on it.
    fn environment_descriptor(&self) -> Result<BTreeMap<String, Option<String>>, BypassReason> {
        self.context
            .environment
            .iter()
            .map(|(name, value)| {
                let value = match value {
                    Some(value) if self.context.portable_environment.contains(name) => {
                        Some(self.normalize_path(Path::new(value))?)
                    }
                    value => value.clone(),
                };
                Ok((name.clone(), value))
            })
            .collect()
    }

    fn normalize_input_path(&self, path: &Path) -> Result<String, BypassReason> {
        let absolute = normalize_components(&self.context.working_dir.join(path));
        for directory in self.invocation.native_search_paths() {
            let directory = normalize_components(&self.context.working_dir.join(directory));
            if let Ok(relative) = absolute.strip_prefix(&directory) {
                // Preserve the searched filename. Resolving a symlink here
                // would collapse libssl.dylib into its versioned referent, so
                // retargeting that link between two existing files could leave
                // the input map unchanged. Discovery rejects directory links
                // inside the tree and hashes regular-file links by content.
                let suffix = relative
                    .components()
                    .map(|component| {
                        component
                            .as_os_str()
                            .to_str()
                            .ok_or_else(|| BypassReason::NonUtf8Path(path.to_path_buf()))
                    })
                    .collect::<Result<Vec<_>, _>>()?
                    .join("/");
                if !suffix.is_empty() {
                    return Ok(format!("{}/{}", self.normalize_path(&directory)?, suffix));
                }
            }
        }
        self.normalize_path(path)
    }

    fn normalize_path(&self, path: &Path) -> Result<String, BypassReason> {
        normalize_resolved_shared_path_with(
            &self.aliases,
            path,
            &self.context.working_dir,
            &self.mappings,
        )
        .map_err(Into::into)
    }
}

/// Whether a normalized path names something strictly beneath one of
/// `directories`, which are normalized the same way and so share its `/`
/// separator regardless of platform.
fn under_any_directory(path: &str, directories: &BTreeSet<String>) -> bool {
    directories.iter().any(|directory| {
        path.len() > directory.len()
            && path.as_bytes()[directory.len()] == b'/'
            && path.starts_with(directory)
    })
}

fn denormalize_path(value: &str, mappings: &[PathMapping]) -> Result<PathBuf, BypassReason> {
    for mapping in mappings {
        let prefix = format!("${{{}}}", mapping.placeholder);
        let suffix = if value == prefix {
            ""
        } else if let Some(suffix) = value.strip_prefix(&format!("{prefix}/")) {
            suffix
        } else {
            continue;
        };
        if !mapping.root.is_absolute()
            || (!suffix.is_empty()
                && suffix.split('/').any(|component| {
                    component.is_empty()
                        || matches!(component, "." | "..")
                        || component.contains('\\')
                }))
        {
            return Err(BypassReason::InvalidPredictedInput(value.into()));
        }
        let mut path = normalize_components(&mapping.root);
        path.extend(suffix.split('/').filter(|component| !component.is_empty()));
        return Ok(path);
    }
    Err(BypassReason::InvalidPredictedInput(value.into()))
}

fn normalize_components(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            component => normalized.push(component.as_os_str()),
        }
    }
    normalized
}

fn absolute_path(path: &Path, working_dir: &Path) -> PathBuf {
    if path.is_absolute() {
        normalize_components(path)
    } else {
        normalize_components(&working_dir.join(path))
    }
}

#[cfg(test)]
#[path = "rustc_cache_tests.rs"]
mod tests;
