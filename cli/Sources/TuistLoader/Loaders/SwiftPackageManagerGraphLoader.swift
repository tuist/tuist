import FileSystem
import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLogging
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
        disableSandbox: Bool,
        swiftPackageManagerArguments: [String]
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue])
}

public struct SwiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping
    private let manifestLoader: ManifestLoading
    private let fileSystem: FileSysteming
    private let contentHasher: ContentHashing
    private let swiftPackageManagerLock: SwiftPackageManagerLock
    private let swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        contentHasher: ContentHashing = ContentHasher(),
        swiftPackageManagerLock: SwiftPackageManagerLock = SwiftPackageManagerLock(),
        swiftPackageManagerScratchDirectoryLocator: SwiftPackageManagerScratchDirectoryLocator =
            SwiftPackageManagerScratchDirectoryLocator()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.contentHasher = contentHasher
        self.swiftPackageManagerLock = swiftPackageManagerLock
        self.swiftPackageManagerScratchDirectoryLocator = swiftPackageManagerScratchDirectoryLocator
    }

    public func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool,
        swiftPackageManagerArguments: [String] = []
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue]) {
        let scratchDirectory = try await swiftPackageManagerScratchDirectory(
            packagePath: packagePath.parentDirectory,
            arguments: swiftPackageManagerArguments
        )
        // The lock is held only while we read SwiftPM's state files directly.
        // Subprocess invocations of `swift package` happen outside the lock, since each
        // subprocess acquires its own scratch-directory lock — holding our lock around
        // a `swift package` invocation on the same scratch directory deadlocks.
        let workspaceState = try await swiftPackageManagerLock
            .withLock(scratchDirectory: scratchDirectory) {
                let workspacePath = scratchDirectory.appending(component: "workspace-state.json")
                if try await !fileSystem.exists(workspacePath) {
                    throw SwiftPackageManagerGraphGeneratorError.installRequired
                }
                return try JSONDecoder()
                    .decode(SwiftPackageManagerWorkspaceState.self, from: try await fileSystem.readFile(at: workspacePath))
            }
        return try await loadUnsafe(
            packagePath: packagePath,
            packageSettings: packageSettings,
            disableSandbox: disableSandbox,
            scratchDirectory: scratchDirectory,
            workspaceState: workspaceState
        )
    }

    // swiftlint:disable:next function_body_length
    private func loadUnsafe(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool,
        scratchDirectory: AbsolutePath,
        workspaceState: SwiftPackageManagerWorkspaceState
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue]) {
        let path = scratchDirectory
        let checkoutsFolder = path.appending(component: "checkouts")
        let packageInfoCache = await SwifterPMPackageInfoCache.load(
            scratchDirectory: scratchDirectory,
            fileSystem: fileSystem
        )

        let rootPackage = if let packageInfoCache,
                             let rootPackageInfo = packageInfoCache.rootPackageInfo(for: packagePath.parentDirectory)
        {
            rootPackageInfo
        } else {
            try await manifestLoader.loadPackage(at: packagePath.parentDirectory, disableSandbox: disableSandbox)
        }

        var packageInfos: [SwiftPackageManagerResolvedPackageInfo] = try await workspaceState.object.dependencies
            .concurrentMap { dependency in
                let name = dependency.packageRef.name
                let packageFolder: AbsolutePath
                let hash: String?
                switch dependency.packageRef.kind {
                case "remote", "remoteSourceControl":
                    packageFolder = checkoutsFolder.appending(component: dependency.subpath)
                    hash = dependency.state?.checkoutState?.revision
                case "local", "fileSystem", "localSourceControl":
                    // Depending on the swift version, the information is available either in `path` or in `location`
                    guard let path = dependency.packageRef.path ?? dependency.packageRef.location else {
                        throw SwiftPackageManagerGraphGeneratorError.missingPathInLocalSwiftPackage(name)
                    }
                    // There's a bug in the `relative` implementation that produces the wrong path when using a symbolic link.
                    // This leads to nonexisting path in the `ModuleMapMapper` that relies on that method.
                    // To get around this, we're aligning paths from `workspace-state.json` with the /var temporary directory.
                    // Anchor against `scratchDirectory` so swifterpm's relative-path encoding resolves correctly;
                    // absolute paths from older swifterpm output pass through unchanged.
                    packageFolder = try AbsolutePath(
                        validating: path.replacingOccurrences(of: "/private/var", with: "/var"),
                        relativeTo: scratchDirectory
                    )
                    hash = nil
                case "registry":
                    let registryFolder = path.appending(try RelativePath(validating: "registry/downloads"))
                    packageFolder = registryFolder.appending(try RelativePath(validating: dependency.subpath))
                    hash = try dependency.state?.version.map { try contentHasher.hash([dependency.packageRef.identity, $0]) }
                default:
                    throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
                }

                let packageInfo = if let packageInfoCache,
                                     let cachedPackageInfo = packageInfoCache.packageInfo(for: packageFolder)
                {
                    cachedPackageInfo
                } else {
                    try await manifestLoader.loadPackage(at: packageFolder, disableSandbox: disableSandbox)
                }
                let targetToArtifactPaths = try workspaceState.object.artifacts
                    .filter { $0.packageRef.identity == dependency.packageRef.identity }
                    .reduce(into: [:]) { result, artifact in
                        result[artifact.targetName] = try AbsolutePath(
                            validating: artifact.path,
                            relativeTo: scratchDirectory
                        )
                    }

                return SwiftPackageManagerResolvedPackageInfo(
                    id: dependency.packageRef.identity.lowercased(),
                    name: name,
                    folder: packageFolder,
                    targetToArtifactPaths: targetToArtifactPaths,
                    info: packageInfo,
                    hash: hash,
                    kind: dependency.packageRef.kind
                )
            }

        // When the same package appears from multiple sources (e.g. local path, registry, or source control),
        // we keep a single entry to avoid duplicates. Selection is based on the following precedence:
        //
        //   1) Local (path-based)
        //   2) Registry
        //   3) Source Control (SCM)
        //
        // If multiple candidates exist, the highest-precedence source wins and the others are discarded.
        //
        // References:
        // - https://github.com/tuist/tuist/pull/7518
        // - https://community.tuist.dev/t/swift-package-registry-overriding-local-dependency-in-tuist-generated-project/902
        packageInfos = Dictionary(grouping: packageInfos, by: {
            if $0.kind == "registry" {
                // A package is uniquely identified by a scoped identifier in the form scope.package-name.
                return String($0.name.split(separator: ".").last ?? "").lowercased()
            } else {
                return $0.name.lowercased()
            }
        })
        .compactMap { _, groupedPackageInfos in
            if let localPackage = groupedPackageInfos.first(where: {
                Self.isLocalDependencyKind($0.kind)
            }) {
                return localPackage
            } else if let registryPackage = groupedPackageInfos.first(where: { $0.kind == "registry" }) {
                return registryPackage
            } else {
                return groupedPackageInfos.first
            }
        }

        let packageInfoDictionary = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.info) })
        let packageToFolder = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.folder) })
        let packageToTargetsToArtifactPaths = Dictionary(uniqueKeysWithValues: packageInfos.map {
            ($0.name, $0.targetToArtifactPaths)
        })
        let packagePrebuilts = try mapPackagePrebuilts(
            packageInfos: packageInfos,
            prebuilts: workspaceState.object.prebuilts,
            scratchDirectory: scratchDirectory
        )

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
            packagePath: packagePath.parentDirectory,
            packageInfos: packageInfoDictionary,
            packageToFolder: packageToFolder,
            packageToTargetsToArtifactPaths: packageToTargetsToArtifactPaths,
            packageModuleAliases: mutablePackageModuleAliases,
            packageSettings: packageSettings
        )

        let packageInfoDictionaryById = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.id, $0.info) })
        let enabledTraitsPerPackage = Self.enabledTraits(
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
                    packageType: .external(
                        origin: Self.packageOrigin(for: packageInfo.kind),
                        artifactPaths: packageToTargetsToArtifactPaths[packageInfo.name] ?? [:],
                        packagePrebuilts: packagePrebuilts,
                        derivedXCFrameworksPath: scratchDirectory.appending(
                            components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
                            Constants.DerivedDirectory.dependenciesXCFrameworkDirectory
                        )
                    ),
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
                    let swiftPackageManagerScratchDirectory: Path? = if Self.isLocalDependencyKind(packageInfo.kind) {
                        nil
                    } else {
                        SwiftPackageManagerPaths
                            .scratchDirectory(containingCheckout: packageInfo.folder)
                            .map { Path.path($0.pathString) }
                    }
                    result[.path(packageInfo.folder.pathString)] = DependenciesGraph.ExternalProject(
                        manifest: projectManifest,
                        hash: hash,
                        swiftPackageManagerScratchDirectory: swiftPackageManagerScratchDirectory
                    )
                }
            }

        return (
            DependenciesGraph(
                externalDependencies: externalDependencies,
                externalProjects: externalProjects
            ),
            []
        )
    }

    private static func isLocalDependencyKind(_ kind: String) -> Bool {
        ["local", "fileSystem", "localSourceControl"].contains(kind)
    }

    private static func packageOrigin(for kind: String) -> PackageType.ExternalOrigin {
        isLocalDependencyKind(kind) ? .local : .remote
    }

    static func enabledTraits(
        rootPackageInfo: PackageInfo,
        packageInfos: [String: PackageInfo]
    ) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]

        processTraits(
            from: rootPackageInfo.dependencies,
            enabledTraitsForCurrentPackage: [],
            packageInfos: packageInfos,
            result: &result
        )

        for (packageId, packageInfo) in packageInfos {
            let enabledForThisPackage = result[packageId] ?? []
            processTraits(
                from: packageInfo.dependencies,
                enabledTraitsForCurrentPackage: enabledForThisPackage,
                packageInfos: packageInfos,
                result: &result
            )
        }

        return result
    }

    private static func processTraits(
        from dependencies: [PackageDependency],
        enabledTraitsForCurrentPackage: Set<String>,
        packageInfos: [String: PackageInfo],
        result: inout [String: Set<String>]
    ) {
        for dependency in dependencies {
            let enabledTraits = dependency.traits.reduce(into: Set<String>()) { result, trait in
                if let condition = trait.condition {
                    if !condition.isDisjoint(with: enabledTraitsForCurrentPackage) {
                        result.insert(trait.name)
                    }
                } else {
                    result.insert(trait.name)
                }
            }

            let resolvedTraits = resolvedEnabledTraits(
                enabledTraits,
                packageTraits: packageInfos[dependency.identity]?.traits ?? []
            )

            guard !resolvedTraits.isEmpty else { continue }
            result[dependency.identity, default: []].formUnion(resolvedTraits)
        }
    }

    private static func resolvedEnabledTraits(
        _ traitNames: some Collection<String>,
        packageTraits: [PackageTrait]
    ) -> Set<String> {
        var resolvedTraitNames = Set(traitNames)

        resolveEnabledTraitNames(
            resolvedTraitNames,
            packageTraits: packageTraits,
            into: &resolvedTraitNames
        )

        return resolvedTraitNames
    }

    private static func resolveEnabledTraitNames(
        _ traitNames: some Collection<String>,
        packageTraits: [PackageTrait],
        into resolvedTraitNames: inout Set<String>
    ) {
        for traitName in traitNames {
            guard let trait = packageTraits.first(where: { $0.name == traitName }) else {
                continue
            }

            for enabledTrait in trait.enabledTraits {
                guard resolvedTraitNames.insert(enabledTrait).inserted else { continue }
                resolveEnabledTraitNames(
                    [enabledTrait],
                    packageTraits: packageTraits,
                    into: &resolvedTraitNames
                )
            }
        }
    }

    private func swiftPackageManagerScratchDirectory(
        packagePath: AbsolutePath,
        arguments: [String]
    ) async throws -> AbsolutePath {
        try swiftPackageManagerScratchDirectoryLocator.locate(
            packagePath: packagePath,
            arguments: arguments,
            environment: Environment.current.variables,
            workingDirectory: try await Environment.current.currentWorkingDirectory()
        )
    }
}

private struct SwiftPackageManagerResolvedPackageInfo {
    let id: String
    let name: String
    let folder: AbsolutePath
    let targetToArtifactPaths: [String: AbsolutePath]
    let info: PackageInfo
    let hash: String?
    let kind: String
}

private func mapPackagePrebuilts(
    packageInfos: [SwiftPackageManagerResolvedPackageInfo],
    prebuilts: [SwiftPackageManagerWorkspaceState.Prebuilt],
    scratchDirectory: AbsolutePath
) throws -> [String: [String: SwiftPackageManagerPrebuilt]] {
    try packageInfos.reduce(into: [:]) { result, packageInfo in
        let packagePrebuilts = prebuilts.filter { $0.identity.lowercased() == packageInfo.id.lowercased() }
        guard !packagePrebuilts.isEmpty else { return }

        let packageKeys = Set([
            packageInfo.id,
            packageInfo.name,
            packageInfo.name.lowercased(),
            packageInfo.folder.basename,
            packageInfo.folder.basename.lowercased(),
        ])

        for prebuilt in packagePrebuilts {
            let mappedPrebuilt = SwiftPackageManagerPrebuilt(
                identity: prebuilt.identity,
                version: prebuilt.version,
                libraryName: prebuilt.libraryName,
                path: try AbsolutePath(validating: prebuilt.path, relativeTo: scratchDirectory),
                checkoutPath: try prebuilt.checkoutPath
                    .map { try AbsolutePath(validating: $0, relativeTo: scratchDirectory) },
                products: prebuilt.products,
                includePath: try prebuilt.includePath?.map { try RelativePath(validating: $0) },
                cModules: prebuilt.cModules
            )

            for packageKey in packageKeys {
                for product in prebuilt.products {
                    result[packageKey, default: [:]][product] = mappedPrebuilt
                }
            }
        }
    }
}

private struct SwifterPMPackageInfoCache {
    private struct Index: Decodable {
        let schemaVersion: Int
        let root: Entry
        let packages: [Entry]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case root
            case packages
        }
    }

    private struct Entry: Decodable {
        let kind: String
        let packagePath: String
        let packageInfoPath: String

        enum CodingKeys: String, CodingKey {
            case kind
            case packagePath = "package_path"
            case packageInfoPath = "package_info_path"
        }
    }

    private struct CachedPackageInfo {
        let packagePath: AbsolutePath
        let packageInfo: PackageInfo
    }

    private let root: CachedPackageInfo?
    private let packagesByPath: [String: CachedPackageInfo]

    /// schema_version 1: paths in the index are absolute strings (older swifterpm output).
    /// schema_version 2: paths are relative to `scratchDirectory` so `.build/` is portable
    /// across hosts. `AbsolutePath(validating:relativeTo:)` accepts either form, so both
    /// schemas are handled by the same code path.
    private static let supportedSchemaVersions: Set<Int> = [1, 2]

    static func load(
        scratchDirectory: AbsolutePath,
        fileSystem: FileSysteming
    ) async -> SwifterPMPackageInfoCache? {
        let cacheDirectory = scratchDirectory.appending(components: "swifterpm", "package-info")
        let indexPath = cacheDirectory.appending(component: "index.json")
        guard (try? await fileSystem.exists(indexPath)) == true,
              let indexData = try? await fileSystem.readFile(at: indexPath),
              let index = try? JSONDecoder().decode(Index.self, from: indexData),
              supportedSchemaVersions.contains(index.schemaVersion)
        else {
            return nil
        }

        let root = await cachedPackageInfo(
            for: index.root,
            scratchDirectory: scratchDirectory,
            fileSystem: fileSystem
        )
        var packagesByPath: [String: CachedPackageInfo] = [:]
        for entry in index.packages {
            guard let cachedPackageInfo = await cachedPackageInfo(
                for: entry,
                scratchDirectory: scratchDirectory,
                fileSystem: fileSystem
            ) else {
                continue
            }
            packagesByPath[normalizedPackagePath(cachedPackageInfo.packagePath.pathString)] = cachedPackageInfo
        }

        return SwifterPMPackageInfoCache(
            root: root,
            packagesByPath: packagesByPath
        )
    }

    func rootPackageInfo(for packagePath: AbsolutePath) -> PackageInfo? {
        guard let root,
              Self.normalizedPackagePath(root.packagePath.pathString)
              == Self.normalizedPackagePath(packagePath.pathString)
        else {
            return nil
        }
        return root.packageInfo
    }

    func packageInfo(for packagePath: AbsolutePath) -> PackageInfo? {
        packagesByPath[Self.normalizedPackagePath(packagePath.pathString)]?.packageInfo
    }

    private static func cachedPackageInfo(
        for entry: Entry,
        scratchDirectory: AbsolutePath,
        fileSystem: FileSysteming
    ) async -> CachedPackageInfo? {
        guard let packagePath = absolutePath(entry.packagePath, scratchDirectory: scratchDirectory),
              let packageInfoPath = absolutePath(entry.packageInfoPath, scratchDirectory: scratchDirectory),
              await isFreshPackageInfo(
                  kind: entry.kind,
                  packageInfoPath: packageInfoPath,
                  packagePath: packagePath,
                  fileSystem: fileSystem
              ),
              let data = try? await fileSystem.readFile(at: packageInfoPath),
              let packageInfo = try? JSONDecoder().decode(PackageInfo.self, from: data)
        else {
            return nil
        }

        return CachedPackageInfo(packagePath: packagePath, packageInfo: packageInfo)
    }

    private static func isFreshPackageInfo(
        kind: String,
        packageInfoPath: AbsolutePath,
        packagePath: AbsolutePath,
        fileSystem: FileSysteming
    ) async -> Bool {
        do {
            guard let packageInfoDate = try await fileSystem.fileMetadata(at: packageInfoPath)?.lastModificationDate
            else {
                return false
            }

            guard let manifestDate = try await fileSystem.fileMetadata(
                at: packagePath.appending(component: "Package.swift")
            )?.lastModificationDate
            else {
                return kind == "registry"
            }

            return packageInfoDate >= manifestDate
        } catch {
            return false
        }
    }

    private static func absolutePath(_ path: String, scratchDirectory: AbsolutePath) -> AbsolutePath? {
        try? AbsolutePath(
            validating: normalizedPackagePath(path),
            relativeTo: scratchDirectory
        )
    }

    private static func normalizedPackagePath(_ path: String) -> String {
        path.replacingOccurrences(of: "/private/var", with: "/var")
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
