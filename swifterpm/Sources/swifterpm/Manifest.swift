import Foundation

enum ManifestDependencyKind: Hashable, Sendable {
    case sourceControl
    case registry
}

struct ManifestDependency: Sendable {
    let identity: String
    let kind: ManifestDependencyKind
    let location: String
    let requirement: Requirement
    let nameForTargetDependencyResolutionOnly: String?

    init(
        identity: String,
        kind: ManifestDependencyKind,
        location: String,
        requirement: Requirement,
        nameForTargetDependencyResolutionOnly: String? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.requirement = requirement
        self.nameForTargetDependencyResolutionOnly = nameForTargetDependencyResolutionOnly
    }
}

struct ManifestFileSystemDependency: Sendable {
    let identity: String
    let name: String
    let path: String
}

struct ManifestBinaryTarget: Sendable {
    enum Source: Sendable {
        case local(path: String)
        case remote(url: String, checksum: String)
    }

    let name: String
    let source: Source
}

enum Requirement: Sendable {
    case exact(SemVer)
    case range(lower: SemVer, upper: SemVer)
    case revision(String)
    case branch(String)
}

enum ManifestLoader {
    static let cacheDirectory = ".build/swifterpm/manifests"
    static let cacheFile = "package.json"

    static func cacheFilePath(packageDir: URL) -> URL {
        packageDir
            .appendingPathComponent(cacheDirectory)
            .appendingPathComponent(cacheFile)
    }

    static func dumpPackage(packageDir: URL, disableSandbox: Bool) async throws -> Any {
        try await requireManifest(packageDir: packageDir)
        do {
            let data = try await loadPackageJSON(
                packageDir: packageDir, disableSandbox: disableSandbox
            )
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw await dumpFailure(packageDir: packageDir, underlying: error)
        }
    }

    static func dumpPackageJSON(packageDir: URL, disableSandbox: Bool) async throws -> Data {
        try await requireManifest(packageDir: packageDir)
        do {
            return try await loadPackageJSON(
                packageDir: packageDir, disableSandbox: disableSandbox
            )
        } catch {
            throw await dumpFailure(packageDir: packageDir, underlying: error)
        }
    }

    /// `swift package dump-package` resolves the package root by walking up from its working
    /// directory, and `--package-path` walks up as well, so a directory that holds no manifest
    /// does not fail the dump: it produces the nearest ancestor package instead, which swifterpm
    /// would then cache and resolve under the identity of the package the caller asked for. A
    /// checkout that lives inside another Swift package is enough to turn a broken local
    /// dependency into a silently wrong graph, so refuse the dump before it starts.
    ///
    /// Only the directory-exists-without-a-manifest case is decided here. A directory that is
    /// absent or unreadable cannot adopt an ancestor either way, and letting the subprocess fail
    /// keeps the diagnosis of those states in `dumpFailure`, next to the error they produce.
    private static func requireManifest(packageDir: URL) async throws {
        if case .absent = await manifestPresence(packageDir: packageDir) {
            throw ToolError.message("no Package.swift in \(packageDir.path)")
        }
    }

    /// The unattributed load. Both entry points wrap it in `dumpFailure`, so the reading of the
    /// cache, the `dump-package` hop, and (for `dumpPackage`) the JSON parse are all attributed
    /// once, by whichever entry point the caller used — a toolchain that prints ahead of the
    /// JSON must not fail as anonymously as the missing manifest this change is about.
    private static func loadPackageJSON(packageDir: URL, disableSandbox: Bool) async throws -> Data {
        if let cached = try await readCachedManifest(packageDir: packageDir) {
            return cached
        }

        var args = ["package"]
        if disableSandbox {
            args.append("--disable-sandbox")
        }
        args.append("dump-package")
        let result = try await SystemProcess.run(
            "/usr/bin/swift", args, workingDirectory: packageDir
        )
        let cache = cacheFilePath(packageDir: packageDir)
        try? await fileSystem.atomicWrite(result.stdout, to: cache)
        if let cachePath = try? cache.absolutePath {
            try? await ManifestEnvironmentFingerprint.write(forCacheFile: cachePath)
        }
        return result.stdout
    }

    /// `swift package dump-package` resolves the package root from its working directory and
    /// walks up from there, so a directory that holds no manifest fails with SwiftPM's
    /// "Could not find Package.swift in this directory or any of its parent directories" —
    /// which names neither the directory swifterpm chose nor the package it stands for. Every
    /// dump in the graph reaches the user as that same line, so attribute the failure to the
    /// directory here, and separate a missing manifest (a package that was never materialized,
    /// or a local dependency pointing at the wrong path) from a manifest that failed to
    /// evaluate: the two need different fixes.
    ///
    /// The classification is a hint layered on the evidence, never a replacement for it: the
    /// probe can be wrong (a directory the process cannot traverse reads as absent), so the
    /// underlying error is always appended. The sentence also carries no verb, so it composes
    /// under callers that add one ("failed to load the manifest for X: no Package.swift in …")
    /// without saying it twice.
    static func dumpFailure(packageDir: URL, underlying: any Error) async -> ToolError {
        let description =
            switch await manifestPresence(packageDir: packageDir) {
            case .present, .indeterminate: packageDir.path
            case .absent: "no Package.swift in \(packageDir.path)"
            // Deliberately not "does not exist": `exists` reports an unreadable directory as
            // absent, so that claim would be false for a package under a parent the process
            // cannot traverse. "Could not read" holds either way, and the underlying error
            // below already distinguishes ENOENT from EACCES.
            case .unreadable: "could not read \(packageDir.path)"
            }
        return ToolError.message("\(description): \(underlying)")
    }

    private enum ManifestPresence {
        case present
        case absent
        /// Missing, or present but not readable — `exists` cannot tell the two apart.
        case unreadable
        /// The filesystem could not answer, so the failure is reported without a claim about
        /// what is on disk rather than with a claim that may be false.
        case indeterminate
    }

    private static func manifestPresence(packageDir: URL) async -> ManifestPresence {
        do {
            let path = try packageDir.absolutePath
            if try await fileSystem.exists(path.appending(component: "Package.swift")) {
                return .present
            }
            return try await fileSystem.exists(path) ? .absent : .unreadable
        } catch {
            return .indeterminate
        }
    }

    private static func readCachedManifest(packageDir: URL) async throws -> Data? {
        let cache = cacheFilePath(packageDir: packageDir)
        let manifest = packageDir.appendingPathComponent("Package.swift")
        let cachePath = try cache.absolutePath
        guard try await fileSystem.exists(cachePath) else { return nil }
        guard let cacheDate = try await fileSystem.fileMetadata(at: cachePath)?.lastModificationDate,
              let manifestDate = try await fileSystem.fileMetadata(at: manifest.absolutePath)?.lastModificationDate,
              cacheDate >= manifestDate
        else {
            return nil
        }
        // A dump is reusable only when it was produced under the current environment. A
        // missing sidecar means the cache predates environment fingerprinting (or the
        // sidecar write failed), so the environment that produced the contents is
        // unknown. Treat that as a miss and re-dump rather than blessing unknown contents
        // with the current environment, otherwise a legacy cache that was already stale
        // at upgrade time would stay stale indefinitely.
        switch try await ManifestEnvironmentFingerprint.validate(forCacheFile: cachePath) {
        case .matching:
            return try await fileSystem.readFile(at: cachePath)
        case .mismatching, .missing:
            return nil
        }
    }
}

struct ManifestFileSystemPackage: @unchecked Sendable {
    let dependency: ManifestFileSystemDependency
    let packagePath: URL
    let manifest: Any
}

enum ManifestFileSystemDependencyGraph {
    static func collect(
        rootPackageDir: URL,
        rootManifest: Any,
        disableSandbox: Bool
    ) async throws -> [ManifestFileSystemPackage] {
        var result: [ManifestFileSystemPackage] = []
        var seenPackagePaths = Set<String>()
        var queue = try ManifestParser.fileSystemDependencies(rootManifest).map {
            (parentPackageDir: rootPackageDir, dependency: $0)
        }

        while !queue.isEmpty {
            let item = queue.removeFirst()
            let packagePath = packagePathForFileSystemDependency(
                parentPackageDir: item.parentPackageDir,
                dependency: item.dependency
            )
            let canonicalPath = PathCanonicalizer.realpath(packagePath)
            guard seenPackagePaths.insert(canonicalPath.path).inserted else {
                continue
            }

            let manifest: Any
            do {
                manifest = try await ManifestLoader.dumpPackage(
                    packageDir: canonicalPath,
                    disableSandbox: disableSandbox
                )
            } catch {
                throw ToolError.message(
                    """
                    failed to load the manifest for the local package \
                    \(item.dependency.identity), declared as "\(item.dependency.path)"\
                    \(redirect(declared: item.dependency.path, canonical: canonicalPath)) by \
                    \(item.parentPackageDir.path): \(error)
                    """
                )
            }
            result.append(
                ManifestFileSystemPackage(
                    dependency: item.dependency,
                    packagePath: canonicalPath,
                    manifest: manifest
                )
            )
            for child in try ManifestParser.fileSystemDependencies(manifest) {
                queue.append((parentPackageDir: canonicalPath, dependency: child))
            }
        }

        return result
    }

    /// The failure above names the directory the dump was attempted in, which is the declared
    /// path only when nothing along the way is a symlink. When the two differ, that sentence
    /// names a directory nobody declared and reads like a typo, while the redirect is the whole
    /// diagnosis: a local dependency whose path lands somewhere other than the package.
    private static func redirect(declared: String, canonical: URL) -> String {
        canonical.path == declared ? "" : ", which resolves to \(canonical.path),"
    }

    static func packagePathForFileSystemDependency(
        parentPackageDir: URL,
        dependency: ManifestFileSystemDependency
    ) -> URL {
        if dependency.path.hasPrefix("/") {
            return URL(fileURLWithPath: dependency.path).standardizedFileURL
        }
        return parentPackageDir
            .appendingPathComponent(dependency.path)
            .standardizedFileURL
    }
}

enum ManifestParser {
    static func packageName(_ manifest: Any) -> String? {
        (manifest as? [String: Any])?["name"] as? String
    }

    static func dependencies(_ manifest: Any) throws -> [ManifestDependency] {
        var dependencies: [ManifestDependency] = []
        guard let root = manifest as? [String: Any],
              let items = root["dependencies"] as? [[String: Any]]
        else {
            return dependencies
        }

        for item in items {
            if let sourceControl = item["sourceControl"] as? [[String: Any]] {
                for dependency in sourceControl {
                    guard let identity = dependency["identity"] as? String else {
                        throw ToolError.message("sourceControl dependency is missing identity")
                    }
                    guard let location = parseSourceControlLocation(dependency) else {
                        throw ToolError.message("\(identity) is missing source-control location")
                    }
                    guard let requirementJSON = dependency["requirement"] else {
                        throw ToolError.message("\(identity) is missing requirement")
                    }
                    try dependencies.append(
                        ManifestDependency(
                            identity: identity,
                            kind: .sourceControl,
                            location: location,
                            requirement: requirement(requirementJSON),
                            nameForTargetDependencyResolutionOnly:
                                dependency["nameForTargetDependencyResolutionOnly"] as? String
                        ))
                }
            }

            if let registry = item["registry"] as? [[String: Any]] {
                for dependency in registry {
                    guard let identity = dependency["identity"] as? String else {
                        throw ToolError.message("registry dependency is missing identity")
                    }
                    guard let requirementJSON = dependency["requirement"] else {
                        throw ToolError.message("\(identity) is missing requirement")
                    }
                    try dependencies.append(
                        ManifestDependency(
                            identity: identity,
                            kind: .registry,
                            location: identity,
                            requirement: requirement(requirementJSON)
                        ))
                }
            }
        }

        return dependencies
    }

    private static func parseSourceControlLocation(_ dependency: [String: Any]) -> String? {
        guard let location = dependency["location"] as? [String: Any] else {
            return nil
        }
        if let remote = location["remote"] as? [[String: Any]],
           let first = remote.first,
           let url = first["urlString"] as? String
        {
            return url
        }
        if let local = location["local"] as? [String],
           let first = local.first
        {
            return first
        }
        return nil
    }

    static func requiredDependencies(_ manifest: Any) throws -> [ManifestDependency] {
        let dependencies = try dependencies(manifest)
        let references = activeDependencyReferences(manifest)
        if references.isEmpty {
            return []
        }
        return dependencies.filter { dependency in
            dependencyReferenceNames(dependency).contains { references.contains($0) }
        }
    }

    private static func activeDependencyReferences(_ manifest: Any) -> Set<String> {
        guard let root = manifest as? [String: Any],
              let targets = root["targets"] as? [[String: Any]]
        else {
            return []
        }

        let targetNames = Set(targets.compactMap { $0["name"] as? String })
        var pendingTargets: [String] = []
        if let products = root["products"] as? [[String: Any]] {
            for product in products {
                if let targets = product["targets"] as? [String] {
                    pendingTargets.append(contentsOf: targets)
                }
            }
        }
        var references = Set<String>()
        var visitedTargets = Set<String>()

        while let targetName = pendingTargets.popLast() {
            guard visitedTargets.insert(targetName).inserted,
                  let target = targets.first(where: { $0["name"] as? String == targetName }),
                  let dependencies = target["dependencies"] as? [[String: Any]]
            else {
                continue
            }

            for dependency in dependencies {
                if let product = dependency["product"] as? [Any] {
                    let productName = product.first as? String
                    let packageName = product.count > 1 ? product[1] as? String : nil
                    if let name = packageName ?? productName {
                        references.insert(normalizeDependencyReference(name))
                    }
                }
                if let byName = dependency["byName"] as? [Any],
                   let name = byName.first as? String
                {
                    if targetNames.contains(name) {
                        pendingTargets.append(name)
                    } else {
                        references.insert(normalizeDependencyReference(name))
                    }
                }
                if let target = dependency["target"] as? [Any],
                   let name = target.first as? String,
                   targetNames.contains(name)
                {
                    pendingTargets.append(name)
                }
            }
        }

        return references
    }

    private static func dependencyReferenceNames(_ dependency: ManifestDependency) -> Set<String> {
        var names = Set<String>()
        names.insert(normalizeDependencyReference(dependency.identity))
        if let name = dependency.nameForTargetDependencyResolutionOnly {
            names.insert(normalizeDependencyReference(name))
        }
        if let suffix = dependency.identity.split(separator: ".").last {
            names.insert(normalizeDependencyReference(String(suffix)))
        }
        if dependency.kind == .sourceControl,
           let name = dependency.location.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
           .replacingOccurrences(of: ".git", with: "")
           .split(separator: "/")
           .last
        {
            names.insert(normalizeDependencyReference(String(name)))
        }
        return names
    }

    private static func normalizeDependencyReference(_ name: String) -> String {
        let value = name.hasSuffix(".git") ? String(name.dropLast(4)) : name
        return value.lowercased()
    }

    static func fileSystemDependencies(_ manifest: Any) throws -> [ManifestFileSystemDependency] {
        guard let root = manifest as? [String: Any],
              let items = root["dependencies"] as? [[String: Any]]
        else {
            return []
        }

        var dependencies: [ManifestFileSystemDependency] = []
        for item in items {
            guard let fileSystem = item["fileSystem"] as? [[String: Any]] else { continue }
            for dependency in fileSystem {
                guard let identity = dependency["identity"] as? String else {
                    throw ToolError.message("fileSystem dependency is missing identity")
                }
                guard let path = dependency["path"] as? String else {
                    throw ToolError.message("\(identity) is missing path")
                }
                dependencies.append(
                    ManifestFileSystemDependency(
                        identity: identity,
                        name: dependency["nameForTargetDependencyResolutionOnly"] as? String
                            ?? identity,
                        path: path
                    ))
            }
        }
        return dependencies
    }

    static func binaryTargets(_ manifest: Any) throws -> [ManifestBinaryTarget] {
        guard let root = manifest as? [String: Any],
              let targets = root["targets"] as? [[String: Any]]
        else {
            return []
        }

        var result: [ManifestBinaryTarget] = []
        for target in targets where target["type"] as? String == "binary" {
            guard let name = target["name"] as? String else {
                throw ToolError.message("binary target is missing name")
            }
            if let url = target["url"] as? String {
                guard let checksum = target["checksum"] as? String else {
                    throw ToolError.message("\(name) is missing checksum")
                }
                result.append(
                    ManifestBinaryTarget(name: name, source: .remote(url: url, checksum: checksum))
                )
            } else if let path = target["path"] as? String {
                result.append(ManifestBinaryTarget(name: name, source: .local(path: path)))
            } else {
                throw ToolError.message("\(name) is missing binary artifact path or URL")
            }
        }
        return result
    }

    static func requirement(_ requirement: Any) throws -> Requirement {
        guard let requirement = requirement as? [String: Any] else {
            throw ToolError.message("unsupported requirement shape: \(requirement)")
        }
        if let exact = requirement["exact"] as? [String], let value = exact.first {
            return try .exact(SemVer(value))
        }
        if let range = requirement["range"] as? [[String: Any]], let first = range.first {
            guard let lower = first["lowerBound"] as? String,
                  let upper = first["upperBound"] as? String
            else {
                throw ToolError.message("range is missing lowerBound or upperBound")
            }
            return try .range(lower: SemVer(lower), upper: SemVer(upper))
        }
        if let revision = requirement["revision"] as? [String], let value = revision.first {
            return .revision(value)
        }
        if let branch = requirement["branch"] as? [String], let value = branch.first {
            return .branch(value)
        }
        throw ToolError.message("unsupported requirement shape: \(requirement)")
    }

    static func versionRange(for requirement: Requirement) -> VersionRange? {
        switch requirement {
        case let .exact(version):
            return .singleton(version)
        case let .range(lower, upper):
            return .between(lower, upper)
        case .revision, .branch:
            return nil
        }
    }
}
