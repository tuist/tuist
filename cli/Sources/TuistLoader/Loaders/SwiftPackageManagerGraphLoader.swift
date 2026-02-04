import FileSystem
import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

// MARK: - Swift Package Manager Graph Generator Errors

enum SwiftPackageManagerGraphGeneratorError: FatalError, Equatable {
    /// Thrown when `SwiftPackageManagerWorkspaceState.Dependency.Kind` is not one of the expected values.
    case unsupportedDependencyKind(String)
    /// Thrown when `SwiftPackageManagerWorkspaceState.packageRef.path` is not present in a local swift package.
    case missingPathInLocalSwiftPackage(String)
    /// Thrown when dependencies were not installed before loading the graph SwiftPackageManagerGraph
    case installRequired

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unsupportedDependencyKind, .missingPathInLocalSwiftPackage:
            return .bug
        case .installRequired:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .unsupportedDependencyKind(name):
            return "The dependency kind \(name) is not supported."
        case let .missingPathInLocalSwiftPackage(name):
            return "The local package \(name) does not contain the path in the generated `workspace-state.json` file."
        case .installRequired:
            return "We could not find external dependencies. Run `tuist install` before you continue."
        }
    }
}

// MARK: - Swift Package Manager Graph Generator

/// A protocol that defines an interface to load the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
public protocol SwiftPackageManagerGraphLoading {
    func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool
    ) async throws -> TuistLoader.DependenciesGraph
}

public struct SwiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping
    private let manifestLoader: ManifestLoading
    private let fileSystem: FileSysteming
    private let contentHasher: ContentHashing
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let swiftVersionProvider: SwiftVersionProviding
    private let tuistVersion: String
    private let cacheDirectory: ThrowableCaching<AbsolutePath>
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum CacheConstants {
        static let version = 1
    }

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        contentHasher: ContentHashing = ContentHasher(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        swiftVersionProvider: SwiftVersionProviding = SwiftVersionProvider.current,
        tuistVersion: String = Constants.version
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.contentHasher = contentHasher
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.swiftVersionProvider = swiftVersionProvider
        self.tuistVersion = tuistVersion
        cacheDirectory = ThrowableCaching {
            try cacheDirectoriesProvider.cacheDirectory(for: .dependenciesGraph)
        }
    }

    // swiftlint:disable:next function_body_length
    public func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool
    ) async throws -> TuistLoader.DependenciesGraph {
        let path = packagePath.parentDirectory.appending(
            component: Constants.SwiftPackageManager.packageBuildDirectoryName
        )
        let checkoutsFolder = path.appending(component: "checkouts")
        let registryDownloadsFolder = path.appending(try RelativePath(validating: "registry/downloads"))
        let workspacePath = path.appending(component: "workspace-state.json")

        if try await !fileSystem.exists(workspacePath) {
            throw SwiftPackageManagerGraphGeneratorError.installRequired
        }

        let workspaceStateData = try await fileSystem.readFile(at: workspacePath)
        let workspaceState = try decoder
            .decode(SwiftPackageManagerWorkspaceState.self, from: workspaceStateData)

        try await validatePackageResolved(at: packagePath.parentDirectory)

        if let cachedGraph = try await loadCachedDependenciesGraph(
            workspaceState: workspaceState,
            workspaceStateData: workspaceStateData,
            rootPath: packagePath.parentDirectory,
            disableSandbox: disableSandbox,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        ) {
            return cachedGraph
        }

        let rootPackage = try await manifestLoader.loadPackage(at: packagePath.parentDirectory, disableSandbox: disableSandbox)

        var packageInfos: [
            // swiftlint:disable:next large_tuple
            (
                id: String,
                name: String,
                folder: AbsolutePath,
                targetToArtifactPaths: [String: AbsolutePath],
                info: PackageInfo,
                hash: String?,
                kind: String
            )
        ] = try await workspaceState.object.dependencies.concurrentMap { dependency in
            let name = dependency.packageRef.name
            let packageFolderInfo = try packageFolder(
                for: dependency,
                checkoutsFolder: checkoutsFolder,
                registryDownloadsFolder: registryDownloadsFolder
            )
            let packageFolder = packageFolderInfo.folder
            let hash = packageFolderInfo.hash

            let packageInfo = try await manifestLoader.loadPackage(at: packageFolder, disableSandbox: disableSandbox)
            let targetToArtifactPaths = try workspaceState.object.artifacts
                .filter { $0.packageRef.identity == dependency.packageRef.identity }
                .reduce(into: [:]) { result, artifact in
                    result[artifact.targetName] = try AbsolutePath(validating: artifact.path)
                }

            return (
                id: dependency.packageRef.identity.lowercased(),
                name: name,
                folder: packageFolder,
                targetToArtifactPaths: targetToArtifactPaths,
                info: packageInfo,
                hash: hash,
                kind: packageFolderInfo.kind
            )
        }

        packageInfos = packageInfos.filter { packageInfo in
            if packageInfo.kind == "registry" {
                return true
            } else {
                return !packageInfos
                    .contains(where: {
                        $0.kind == "registry" && String($0.name.split(separator: ".").last ?? "") == packageInfo.name
                    })
            }
        }

        let packageInfoDictionary = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.info) })
        let packageToFolder = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.folder) })
        let packageToTargetsToArtifactPaths = Dictionary(uniqueKeysWithValues: packageInfos.map {
            ($0.name, $0.targetToArtifactPaths)
        })

        var mutablePackageModuleAliases: [String: [String: String]] = [:]

        for packageInfo in packageInfoDictionary.values {
            for target in packageInfo.targets {
                for dependency in target.dependencies {
                    switch dependency {
                    case let .product(
                        name: _,
                        package: packageName,
                        moduleAliases: moduleAliases,
                        condition: _
                    ):
                        guard let moduleAliases else { continue }
                        mutablePackageModuleAliases[
                            packageInfos.first(where: { $0.folder.basename == packageName })?
                                .name ?? packageName
                        ] = moduleAliases
                    default:
                        break
                    }
                }
            }
        }

        let externalDependencies = try await packageInfoMapper.resolveExternalDependencies(
            path: path,
            packageInfos: packageInfoDictionary,
            packageToFolder: packageToFolder,
            packageToTargetsToArtifactPaths: packageToTargetsToArtifactPaths,
            packageModuleAliases: mutablePackageModuleAliases
        )

        let packageInfoDictionaryById = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.id, $0.info) })
        let enabledTraitsPerPackage = enabledTraits(
            rootPackageInfo: rootPackage,
            packageInfos: packageInfoDictionaryById
        )

        let packageModuleAliases = mutablePackageModuleAliases
        let mappedPackageInfos = try await packageInfos.concurrentMap { packageInfo in
            (
                packageInfo: packageInfo,
                hash: packageInfo.hash,
                projectManifest: try await packageInfoMapper.map(
                    packageInfo: packageInfo.info,
                    path: packageInfo.folder,
                    packageType: .external(artifactPaths: packageToTargetsToArtifactPaths[packageInfo.name] ?? [:]),
                    packageSettings: packageSettings,
                    packageModuleAliases: packageModuleAliases,
                    enabledTraits: enabledTraitsPerPackage[packageInfo.id] ?? []
                )
            )
        }
        let externalProjects: [Path: DependenciesGraph.ExternalProject] = mappedPackageInfos
            .reduce(into: [:]) { result, item in
                let (packageInfo, hash, projectManifest) = item
                if let projectManifest {
                    result[.path(packageInfo.folder.pathString)] = DependenciesGraph.ExternalProject(
                        manifest: projectManifest,
                        hash: hash
                    )
                }
            }

        let dependenciesGraph = DependenciesGraph(
            externalDependencies: externalDependencies,
            externalProjects: externalProjects
        )
        try await cacheDependenciesGraph(
            dependenciesGraph,
            workspaceState: workspaceState,
            workspaceStateData: workspaceStateData,
            rootPath: packagePath.parentDirectory,
            disableSandbox: disableSandbox,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        )

        return dependenciesGraph
    }

    private func packageFolder(
        for dependency: SwiftPackageManagerWorkspaceState.Dependency,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) throws -> (folder: AbsolutePath, hash: String?, kind: String) {
        let name = dependency.packageRef.name
        switch dependency.packageRef.kind {
        case "remote", "remoteSourceControl":
            return (
                folder: checkoutsFolder.appending(component: dependency.subpath),
                hash: dependency.state?.checkoutState?.revision,
                kind: dependency.packageRef.kind
            )
        case "local", "fileSystem", "localSourceControl":
            // Depending on the swift version, the information is available either in `path` or in `location`
            guard let path = dependency.packageRef.path ?? dependency.packageRef.location else {
                throw SwiftPackageManagerGraphGeneratorError.missingPathInLocalSwiftPackage(name)
            }
            // There's a bug in the `relative` implementation that produces the wrong path when using a symbolic link.
            // This leads to nonexisting path in the `ModuleMapMapper` that relies on that method.
            // To get around this, we're aligning paths from `workspace-state.json` with the /var temporary directory.
            return (
                folder: try AbsolutePath(validating: path.replacingOccurrences(of: "/private/var", with: "/var")),
                hash: nil,
                kind: dependency.packageRef.kind
            )
        case "registry":
            return (
                folder: registryDownloadsFolder.appending(try RelativePath(validating: dependency.subpath)),
                hash: try dependency.state?.version.map { try contentHasher.hash([dependency.packageRef.identity, $0]) },
                kind: dependency.packageRef.kind
            )
        default:
            throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
        }
    }

    private func loadCachedDependenciesGraph(
        workspaceState: SwiftPackageManagerWorkspaceState,
        workspaceStateData: Data,
        rootPath: AbsolutePath,
        disableSandbox: Bool,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) async throws -> DependenciesGraph? {
        guard let cachePath = try await cachedDependenciesGraphPath(
            workspaceState: workspaceState,
            workspaceStateData: workspaceStateData,
            rootPath: rootPath,
            disableSandbox: disableSandbox,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        ) else {
            return nil
        }

        guard try await fileSystem.exists(cachePath) else { return nil }
        guard let data = try? await fileSystem.readFile(at: cachePath) else { return nil }
        return try? decoder.decode(DependenciesGraph.self, from: data)
    }

    private func cacheDependenciesGraph(
        _ dependenciesGraph: DependenciesGraph,
        workspaceState: SwiftPackageManagerWorkspaceState,
        workspaceStateData: Data,
        rootPath: AbsolutePath,
        disableSandbox: Bool,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) async throws {
        guard let cachePath = try await cachedDependenciesGraphPath(
            workspaceState: workspaceState,
            workspaceStateData: workspaceStateData,
            rootPath: rootPath,
            disableSandbox: disableSandbox,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        ) else {
            return
        }

        do {
            if try await !fileSystem.exists(cachePath.parentDirectory) {
                try await fileSystem.makeDirectory(at: cachePath.parentDirectory, options: [.createTargetParentDirectories])
            }
            try await fileSystem.writeAsJSON(dependenciesGraph, at: cachePath)
        } catch {
            return
        }
    }

    private func cachedDependenciesGraphPath(
        workspaceState: SwiftPackageManagerWorkspaceState,
        workspaceStateData: Data,
        rootPath: AbsolutePath,
        disableSandbox: Bool,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) async throws -> AbsolutePath? {
        guard let key = await dependenciesGraphCacheKey(
            workspaceState: workspaceState,
            workspaceStateData: workspaceStateData,
            rootPath: rootPath,
            disableSandbox: disableSandbox,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        ) else { return nil }

        let directory = try cacheDirectory.value
        return directory.appending(component: "\(CacheConstants.version).\(key).json")
    }

    private func dependenciesGraphCacheKey(
        workspaceState: SwiftPackageManagerWorkspaceState,
        workspaceStateData: Data,
        rootPath: AbsolutePath,
        disableSandbox: Bool,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) async -> String? {
        guard let manifestHash = try? await packageManifestHashes(
            workspaceState: workspaceState,
            rootPath: rootPath,
            checkoutsFolder: checkoutsFolder,
            registryDownloadsFolder: registryDownloadsFolder
        ) else {
            return nil
        }
        guard let swiftlangVersion = try? swiftVersionProvider.swiftlangVersion() else { return nil }

        let resolvedHash = await packageResolvedHash(at: rootPath) ?? "no-resolved"

        let keyComponents = [
            "\(CacheConstants.version)",
            rootPath.pathString,
            workspaceStateData.md5,
            manifestHash,
            resolvedHash,
            swiftlangVersion,
            tuistVersion,
            "\(disableSandbox)",
        ]

        return keyComponents.joined(separator: "|").md5
    }

    private func packageResolvedHash(at rootPath: AbsolutePath) async -> String? {
        let resolvedCandidates: [AbsolutePath] = [
            rootPath.appending(component: ".package.resolved"),
            rootPath.appending(component: Constants.SwiftPackageManager.packageResolvedName),
            rootPath.appending(components: [".swiftpm", Constants.SwiftPackageManager.packageResolvedName]),
        ]

        var hashes: [String] = []
        for candidate in resolvedCandidates {
            guard (try? await fileSystem.exists(candidate)) == true else { continue }
            guard let data = try? await fileSystem.readFile(at: candidate) else { continue }
            hashes.append("\(candidate.basename):\(data.md5)")
        }

        guard !hashes.isEmpty else { return nil }
        return hashes.joined(separator: "|").md5
    }

    private func packageManifestHashes(
        workspaceState: SwiftPackageManagerWorkspaceState,
        rootPath: AbsolutePath,
        checkoutsFolder: AbsolutePath,
        registryDownloadsFolder: AbsolutePath
    ) async throws -> String? {
        var hashes: [String] = []
        let rootManifestPath = rootPath.appending(component: Constants.SwiftPackageManager.packageSwiftName)
        guard try await fileSystem.exists(rootManifestPath) else { return nil }
        let rootData = try await fileSystem.readFile(at: rootManifestPath)
        hashes.append("root:\(rootData.md5)")

        for dependency in workspaceState.object.dependencies {
            let packageFolderInfo = try packageFolder(
                for: dependency,
                checkoutsFolder: checkoutsFolder,
                registryDownloadsFolder: registryDownloadsFolder
            )
            let manifestPath = packageFolderInfo.folder.appending(component: Constants.SwiftPackageManager.packageSwiftName)
            guard try await fileSystem.exists(manifestPath) else { return nil }
            let data = try await fileSystem.readFile(at: manifestPath)
            hashes.append("\(dependency.packageRef.identity):\(data.md5)")
        }

        guard !hashes.isEmpty else { return nil }
        return hashes.sorted().joined(separator: "|").md5
    }

    private func validatePackageResolved(at path: AbsolutePath) async throws {
        let savedPackageResolvedPath = path.appending(components: [
            Constants.SwiftPackageManager.packageBuildDirectoryName,
            Constants.DerivedDirectory.name,
            Constants.SwiftPackageManager.packageResolvedName,
        ])
        let savedData: Data?
        if try await fileSystem.exists(savedPackageResolvedPath) {
            savedData = try await fileSystem.readFile(at: savedPackageResolvedPath)
        } else {
            savedData = nil
        }

        let currentPackageResolvedPath = path.appending(component: Constants.SwiftPackageManager.packageResolvedName)
        let currentData: Data?
        if try await fileSystem.exists(currentPackageResolvedPath) {
            currentData = try await fileSystem.readFile(at: currentPackageResolvedPath)
        } else {
            currentData = nil
        }

        if currentData != savedData {
            AlertController.current.warning(.alert(
                "We detected outdated dependencies.",
                takeaway: "Run \(.command("tuist install")) to update them."
            ))
        }
    }
}

extension ProjectDescription.Platform {
    /// Maps a XcodeGraph.Platform instance into a  ProjectDescription.Platform instance.
    /// - Parameters:
    ///   - graph: Graph representation of platform model.
    static func from(graph: XcodeGraph.Platform) -> ProjectDescription.Platform {
        switch graph {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        }
    }
}

// MARK: - Trait Processing

/// Extracts the enabled traits for each package dependency from the root package and all packages in the dependency graph.
/// - Parameters:
///   - rootPackageInfo: The `PackageInfo` of the root package (the Tuist `Package.swift`)
///   - packageInfos: All `PackageInfo`s in the dependency graph, keyed by package identity
/// - Returns: A dictionary where keys are package identities and values are the set of enabled trait names
func enabledTraits(
    rootPackageInfo: PackageInfo,
    packageInfos: [String: PackageInfo]
) -> [String: Set<String>] {
    var result: [String: Set<String>] = [:]

    processTraits(
        from: rootPackageInfo.dependencies,
        enabledTraitsForCurrentPackage: [],
        result: &result
    )

    for (packageId, packageInfo) in packageInfos {
        let enabledForThisPackage = result[packageId] ?? []
        processTraits(
            from: packageInfo.dependencies,
            enabledTraitsForCurrentPackage: enabledForThisPackage,
            result: &result
        )
    }

    return result
}

private func processTraits(
    from dependencies: [PackageDependency],
    enabledTraitsForCurrentPackage: Set<String>,
    result: inout [String: Set<String>]
) {
    for dependency in dependencies {
        for trait in dependency.traits {
            if let condition = trait.condition {
                if !condition.isDisjoint(with: enabledTraitsForCurrentPackage) {
                    result[dependency.identity, default: []].insert(trait.name)
                }
            } else {
                result[dependency.identity, default: []].insert(trait.name)
            }
        }
    }
}
