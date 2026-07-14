import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLogging
import TuistSupport

/// The set of hashes that determine the mapped Swift Package Manager dependency graph.
///
/// Mapping is deterministic in these inputs:
/// - `workspaceStateHash` pins the resolved dependency set, including revisions of source-control
///   checkouts, versions of registry downloads, artifacts, and prebuilts. Checkout and download
///   contents are immutable for a given revision/version, so hashing their pins is sufficient.
/// - `rootManifestHash` and `localPackagesHash` cover the packages whose content can change
///   without the resolution changing. Local packages are fingerprinted by file content (not
///   only their manifest) because mapping inspects their disk layout: public headers, custom
///   module maps, and resources.
/// - `swiftVersion` and `environmentHash` cover the remaining mapper inputs; `packagePath` and
///   `scratchDirectoryPath` are embedded in the mapped graph's absolute paths.
///
/// The package settings are part of the cached entry rather than this key: their JSON encoding is
/// not deterministic across processes (they contain sets and non-string-keyed dictionaries), so
/// they are compared with `Equatable` on load instead of by hash.
struct SwiftPackageManagerGraphCacheKey: Equatable, Codable {
    var tuistVersion: String
    var swiftVersion: String
    var workspaceStateHash: String
    var rootManifestHash: String
    var localPackagesHash: String
    var environmentHash: String
    var disableSandbox: Bool
    var packagePath: String
    var scratchDirectoryPath: String
}

private struct CachedSwiftPackageManagerGraph: Codable {
    /// Note: please bump the version in case the cache structure is modified.
    /// This ensures older cache versions are not loaded using this structure.
    static let currentCacheVersion = 1

    var cacheVersion: Int = currentCacheVersion
    var key: SwiftPackageManagerGraphCacheKey
    var packageSettings: TuistCore.PackageSettings
    var derivedFiles: [String]
    var graph: Data
}

/// Caches the Swift Package Manager dependency graph that `SwiftPackageManagerGraphLoader` maps
/// from `workspace-state.json` and the per-package `PackageInfo`s, so repeated generations with
/// unchanged inputs skip the mapping entirely (the same pattern as `CachedManifestLoader`).
///
/// A hit is only served while the graph's external package folders and the derived files it wrote
/// as a side effect (generated module maps and synthesized XCFrameworks for static-library artifact
/// bundles) all still exist. Pruning a checkout, registry download, or derived directory therefore
/// falls back to re-mapping rather than serving a graph with missing source or binary paths.
///
/// Every failure in this cache degrades to re-mapping; it never fails the load.
struct SwiftPackageManagerGraphCache {
    private let fileSystem: FileSysteming
    private let contentHasher: ContentHashing
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let tuistVersion: String

    /// Directories that never affect the mapped graph and would otherwise churn the fingerprint
    /// of local packages. `Derived` and the generated projects are excluded because generation
    /// itself writes them into the package folder; including them would invalidate the entry
    /// that stored them.
    private static let excludedLocalPackageComponents: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        Constants.DerivedDirectory.name,
    ]

    private static let excludedLocalPackageComponentExtensions = [
        ".xcodeproj",
        ".xcworkspace",
    ]

    init(
        fileSystem: FileSysteming = FileSystem(),
        contentHasher: ContentHashing = ContentHasher(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        tuistVersion: String = Constants.version
    ) {
        self.fileSystem = fileSystem
        self.contentHasher = contentHasher
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.tuistVersion = tuistVersion
    }

    /// Computes the cache key for the current mapping inputs, or `nil` when the cache directory
    /// is unavailable or any input can't be hashed, in which case caching is skipped for this load.
    func cacheKey(
        packagePath: AbsolutePath,
        scratchDirectory: AbsolutePath,
        workspaceStateData: Data,
        localPackageFolders: [AbsolutePath],
        disableSandbox: Bool
    ) async -> SwiftPackageManagerGraphCacheKey? {
        do {
            _ = try cacheDirectoriesProvider.cacheDirectory(for: .swiftPackageManagerGraphs)
            let environmentVariables = Environment.current.manifestLoadingVariables
                .map { "\($0.key)=\($0.value)" }
                .sorted()
            return SwiftPackageManagerGraphCacheKey(
                tuistVersion: tuistVersion,
                swiftVersion: try await SwiftVersionProvider.current.swiftVersion(),
                workspaceStateHash: try contentHasher.hash(workspaceStateData),
                rootManifestHash: try await contentHasher.hash(path: packagePath),
                localPackagesHash: try await localPackagesHash(folders: localPackageFolders),
                environmentHash: try contentHasher.hash(environmentVariables),
                disableSandbox: disableSandbox,
                packagePath: packagePath.pathString,
                scratchDirectoryPath: scratchDirectory.pathString
            )
        } catch {
            Logger.current
                .debug("Skipping the Swift Package Manager graph cache because its key could not be computed: \(error)")
            return nil
        }
    }

    /// Returns the cached dependencies graph for the given key and package settings, or `nil` on
    /// any mismatch: absent entry, different key or settings, missing external package roots,
    /// missing derived files, or an undecodable payload.
    func cachedGraph(
        for key: SwiftPackageManagerGraphCacheKey,
        packageSettings: TuistCore.PackageSettings
    ) async -> TuistLoader.DependenciesGraph? {
        do {
            let cacheEntryPath = try cacheEntryPath(for: key)
            guard try await fileSystem.exists(cacheEntryPath) else { return nil }
            let data = try await fileSystem.readFile(at: cacheEntryPath)
            let decoder = JSONDecoder()
            guard let cached = try? decoder.decode(CachedSwiftPackageManagerGraph.self, from: data),
                  cached.cacheVersion == CachedSwiftPackageManagerGraph.currentCacheVersion
            else {
                Logger.current.debug("Ignoring an incompatible Swift Package Manager graph cache entry")
                return nil
            }
            guard cached.key == key else {
                Logger.current.debug("The cached Swift Package Manager graph is stale: its inputs changed")
                return nil
            }
            guard cached.packageSettings == packageSettings else {
                Logger.current.debug("The cached Swift Package Manager graph is stale: the package settings changed")
                return nil
            }
            guard let graph = try? decoder.decode(TuistLoader.DependenciesGraph.self, from: cached.graph) else {
                Logger.current.debug("Ignoring an undecodable Swift Package Manager graph cache entry")
                return nil
            }

            // The key pins remote and registry packages only through `workspace-state.json`, and the
            // recorded derived files live under the derived directories. A checkout, registry download,
            // or local package folder can be pruned while `workspace-state.json` survives (e.g. a partial
            // `.build` restore), which would make the cached graph reference missing source roots. Serving
            // it would produce a broken project instead of re-mapping, so verify the package roots exist.
            let externalRoots = graph.externalProjects.keys.compactMap { try? AbsolutePath(validating: $0.pathString) }
            if let missingRoot = try await firstMissingPath(in: externalRoots) {
                Logger.current
                    .debug("The cached Swift Package Manager graph is stale: a package folder is missing, such as \(missingRoot)")
                return nil
            }

            let recordedDerivedFiles = cached.derivedFiles.compactMap { try? AbsolutePath(validating: $0) }
            if let missingDerivedFile = try await firstMissingPath(in: recordedDerivedFiles) {
                Logger.current
                    .debug(
                        "The cached Swift Package Manager graph is stale: derived files are missing, such as \(missingDerivedFile)"
                    )
                return nil
            }

            return graph
        } catch {
            Logger.current.debug("Skipping the Swift Package Manager graph cache because it could not be read: \(error)")
            return nil
        }
    }

    private func firstMissingPath(in paths: [AbsolutePath]) async throws -> AbsolutePath? {
        try await paths
            .concurrentMap { path -> AbsolutePath? in
                try await fileSystem.exists(path) ? nil : path
            }
            .compactMap { $0 }
            .first
    }

    func store(
        _ graph: TuistLoader.DependenciesGraph,
        for key: SwiftPackageManagerGraphCacheKey,
        packageSettings: TuistCore.PackageSettings,
        scratchDirectory: AbsolutePath
    ) async {
        do {
            let encoder = JSONEncoder()
            let cached = CachedSwiftPackageManagerGraph(
                key: key,
                packageSettings: packageSettings,
                derivedFiles: try await derivedFiles(scratchDirectory: scratchDirectory, graph: graph),
                graph: try encoder.encode(graph)
            )
            let cacheEntryPath = try cacheEntryPath(for: key)
            try await fileSystem.makeDirectory(
                at: cacheEntryPath.parentDirectory,
                options: [.createTargetParentDirectories]
            )
            try await fileSystem.writeText(String(decoding: try encoder.encode(cached), as: UTF8.self), at: cacheEntryPath)
        } catch {
            Logger.current.debug("The Swift Package Manager graph could not be cached: \(error)")
        }
    }

    // MARK: - Private

    private func cacheEntryPath(for key: SwiftPackageManagerGraphCacheKey) throws -> AbsolutePath {
        let fileName = [
            String(CachedSwiftPackageManagerGraph.currentCacheVersion),
            try contentHasher.hash([key.packagePath, key.scratchDirectoryPath]),
            "json",
        ].joined(separator: ".")
        return try cacheDirectoriesProvider.cacheDirectory(for: .swiftPackageManagerGraphs).appending(component: fileName)
    }

    /// Fingerprints local packages by the relative path and content of every file, because mapping
    /// depends on their disk layout beyond the manifest. Content hashes (rather than modification
    /// times) keep the fingerprint stable across fresh checkouts of the same sources.
    private func localPackagesHash(folders: [AbsolutePath]) async throws -> String {
        let folderHashes = try await folders
            .sorted(by: { $0.pathString < $1.pathString })
            .concurrentMap { folder in
                let fileHashes = try await fileSystem.glob(directory: folder, include: ["**/*"])
                    .collect()
                    .filter { path in
                        let relativeComponents = path.relative(to: folder).components
                        return Self.excludedLocalPackageComponents.isDisjoint(with: relativeComponents)
                            && !relativeComponents.contains { component in
                                Self.excludedLocalPackageComponentExtensions.contains { component.hasSuffix($0) }
                            }
                    }
                    .concurrentMap { path -> String? in
                        guard try await !fileSystem.exists(path, isDirectory: true) else { return nil }
                        let contentHash = (try? await contentHasher.hash(path: path)) ?? "unreadable"
                        return "\(path.relative(to: folder).pathString):\(contentHash)"
                    }
                    .compactMap { $0 }
                    .sorted()
                let folderHash = try contentHasher.hash(fileHashes)
                return "\(folder.pathString):\(folderHash)"
            }
        return try contentHasher.hash(folderHashes)
    }

    /// Collects the files that mapping wrote as a side effect: generated module maps and
    /// synthesized XCFrameworks under the scratch directory's `tuist-derived` directory, and
    /// generated module maps under each package's `Derived` directory.
    private func derivedFiles(
        scratchDirectory: AbsolutePath,
        graph: TuistLoader.DependenciesGraph
    ) async throws -> [String] {
        var directories = [scratchDirectory.appending(component: Constants.DerivedDirectory.dependenciesDerivedDirectory)]
        directories += graph.externalProjects.keys.compactMap { path in
            (try? AbsolutePath(validating: path.pathString))?.appending(component: Constants.DerivedDirectory.name)
        }

        var files: Set<String> = []
        for directory in directories {
            guard try await fileSystem.exists(directory, isDirectory: true) else { continue }
            for path in try await fileSystem.glob(directory: directory, include: ["**/*"]).collect() {
                files.insert(path.pathString)
            }
        }
        return files.sorted()
    }
}
