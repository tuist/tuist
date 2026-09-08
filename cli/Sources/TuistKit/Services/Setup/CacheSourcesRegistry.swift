import FileSystem
import Foundation
import Path
import TuistEnvironment

/// What setup knows about a project that the proxy cannot work out for itself
/// (see `load_sources` in cas-plugin).
///
/// The registry is a JSON object of instance -> this. JSON because we write it
/// and the proxy reads it from another language: a format each side hand-rolls
/// is one each side can drift on, and every value here is optional, which is the
/// shape a hand-rolled one gets wrong first.
struct RegisteredSource: Codable {
    /// The project's configured default branch, which is a server-side decision.
    /// The proxy would otherwise have to guess it from the local clone's
    /// `origin/HEAD`, a property of how this machine cloned rather than of the
    /// project.
    let trunk: String?
    /// Recorded only on CI. See `ciBranch`.
    let branch: String?
    /// The project's `xcodeCache.upload`. The proxy is the only place that can
    /// enforce this: the plugin reads it as a compiler option, which reaches
    /// Swift, while the build system's Clang caching runs in its own process
    /// with no plugin options at all. Recorded here so one answer covers both.
    let upload: Bool

    init(trunk: String?, branch: String?, upload: Bool) {
        self.trunk = trunk
        self.branch = branch
        self.upload = upload
    }

    /// Hand-written rather than synthesized, so that an absent field means here
    /// what it means to the proxy. The synthesized one requires every
    /// non-optional, which would make this side reject a registry the proxy
    /// reads happily: the drift that using one format on both sides exists to
    /// prevent.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trunk = try container.decodeIfPresent(String.self, forKey: .trunk)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        // Nothing recorded is nothing to withhold (`uploads_by_default` there).
        upload = try container.decodeIfPresent(Bool.self, forKey: .upload) ?? true
    }
}

/// The cache proxy's sources registry: one row per project set up on this
/// machine, holding what `tuist setup cache` knows that the proxy cannot work
/// out for itself.
///
/// The one writer of the file, so that every entry point gets the same lock and
/// the same atomic swap. A policy flip races a concurrent setup exactly as two
/// setups race each other, and both windows are closed here or nowhere.
struct CacheSourcesRegistry {
    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Rewrites this project's row in the proxy's sources registry
    /// (`<state>/cas-proxy.sock.registry.sources`, honoring the same
    /// `TUIST_CAS_PROXY_REGISTRY` override the proxy reads), handing `mutate` the
    /// row recorded for it today (`nil` when it has none) and storing what comes
    /// back.
    func update(
        fullHandle: String,
        _ mutate: (RegisteredSource?) -> RegisteredSource
    ) async throws {
        // Derived from the proxy's OWN socket, not from `stateDirectory`. The two
        // agree by default and diverge under `XDG_STATE_HOME`, which the socket
        // deliberately ignores (see `casProxySocketPath`) because the plugin must
        // resolve it from HOME alone. Writing this file where the proxy is not
        // reading loses the trunk silently: unscoped snapshots and untagged
        // publishes, with nothing to show for it.
        let sourcesPath: AbsolutePath
        if let registry = Environment.current.variables["TUIST_CAS_PROXY_REGISTRY"] {
            sourcesPath = try AbsolutePath(validating: registry + ".sources")
        } else {
            sourcesPath = try AbsolutePath(
                validating: Environment.current.casProxySocketPath().pathString + ".registry.sources"
            )
        }

        if try await !fileSystem.exists(sourcesPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: sourcesPath.parentDirectory)
        }

        // The whole read-modify-write is serialized across processes. Atomic
        // rename gives a READER the old file or the new one, never a torn one,
        // but it does nothing for two setups racing: both read the registry
        // before either renames, and the later rename drops the project the
        // earlier one added, silently losing its trunk and upload policy. An
        // exclusive lock on a sidecar file makes the second setup wait for the
        // first, so it reads the already-updated registry and upserts onto it.
        let lockPath = sourcesPath.parentDirectory
            .appending(component: "\(sourcesPath.basename).lock")
        try await withRegistryLock(at: lockPath) {
            // Read every other project back: this rewrites the whole file, so
            // anything lost here is a project silently losing its policy. A
            // registry we cannot decode therefore fails the command rather than
            // being written over with just this project, which would erase every
            // other one's.
            var entries: [String: RegisteredSource] = [:]
            if try await fileSystem.exists(sourcesPath) {
                let contents = try await fileSystem.readTextFile(at: sourcesPath)
                entries = try JSONDecoder().decode([String: RegisteredSource].self, from: Data(contents.utf8))
            }
            entries[fullHandle] = mutate(entries[fullHandle])

            let encoder = JSONEncoder()
            // Sorted so a rewrite that changes nothing produces the same bytes,
            // and unescaped because every key here is an `account/project`.
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            let body = String(decoding: try encoder.encode(entries), as: UTF8.self)

            // Swapped in, never rewritten in place, and `rename` rather than a
            // remove followed by a write or a move: it is the only one of the
            // three that leaves no instant where the file is missing or
            // half-written.
            //
            // The proxy re-reads this on a timer while we write it, and it
            // carries the upload policy. A reader that finds no file sees no
            // projects, and an unknown project has to be allowed to upload, so
            // any gap here hands an opted-out project a window in which its Clang
            // outputs are published. `rename` gives every reader either the whole
            // old file or the whole new one, and both are answers we can live
            // with.
            let staged = sourcesPath.parentDirectory
                .appending(component: "\(sourcesPath.basename).\(UUID().uuidString)")
            try await fileSystem.writeText(body, at: staged)
            guard rename(staged.pathString, sourcesPath.pathString) == 0 else {
                let code = errno
                try? await fileSystem.remove(staged)
                throw SetupCacheCommandServiceError.registryNotReplaced(sourcesPath.pathString, code)
            }
        }
    }

    /// Runs `body` while holding an exclusive advisory lock on `lockPath`, so two
    /// `tuist setup cache` processes cannot interleave a read-modify-write of the
    /// registry. The lock file is created on demand and never removed: deleting
    /// it would reopen the race it closes. `flock` is released when the descriptor
    /// closes, including on a crash, so a killed setup cannot wedge the next one.
    private func withRegistryLock(at lockPath: AbsolutePath, _ body: () async throws -> Void) async throws {
        let descriptor = open(lockPath.pathString, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw SetupCacheCommandServiceError.registryNotLocked(lockPath.pathString, errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw SetupCacheCommandServiceError.registryNotLocked(lockPath.pathString, errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        try await body()
    }
}
