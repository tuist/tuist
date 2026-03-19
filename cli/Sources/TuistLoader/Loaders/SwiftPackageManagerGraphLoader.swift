import FileSystem
import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistConstants
import TuistCore
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
        disableSandbox: Bool
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue])
}

public struct SwiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping
    private let manifestLoader: ManifestLoading
    private let fileSystem: FileSysteming
    private let contentHasher: ContentHashing

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.contentHasher = contentHasher
    }

    // swiftlint:disable:next function_body_length
    public func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings,
        disableSandbox: Bool
    ) async throws -> (TuistLoader.DependenciesGraph, [LintingIssue]) {
        let path = packagePath.parentDirectory.appending(
            component: Constants.SwiftPackageManager.packageBuildDirectoryName
        )
        let checkoutsFolder = path.appending(component: "checkouts")
        let workspacePath = path.appending(component: "workspace-state.json")

        if try await !fileSystem.exists(workspacePath) {
            throw SwiftPackageManagerGraphGeneratorError.installRequired
        }

        let workspaceState = try JSONDecoder()
            .decode(SwiftPackageManagerWorkspaceState.self, from: try await fileSystem.readFile(at: workspacePath))

        let outdatedDependencyIssues = try await validatePackageResolved(at: packagePath.parentDirectory)

        let rootPackage = try await manifestLoader.loadPackage(at: packagePath.parentDirectory, disableSandbox: disableSandbox)

        var packageInfos: [
            // swiftlint:disable:next large_tuple
            (
                id: String,
                name: String,
                identityName: String,
                manifestName: String,
                folder: AbsolutePath,
                targetToArtifactPaths: [String: AbsolutePath],
                info: PackageInfo,
                hash: String?,
                kind: String
            )
        ] = try await workspaceState.object.dependencies.concurrentMap { dependency in
            let name = dependency.packageRef.name
            let packageFolder: AbsolutePath
            let hash: String?
            let identityName: String
            switch dependency.packageRef.kind {
            case "remote", "remoteSourceControl":
                packageFolder = checkoutsFolder.appending(component: dependency.subpath)
                hash = dependency.state?.checkoutState?.revision
                identityName = packageFolder.basename
            case "local", "fileSystem", "localSourceControl":
                // Depending on the swift version, the information is available either in `path` or in `location`
                guard let path = dependency.packageRef.path ?? dependency.packageRef.location else {
                    throw SwiftPackageManagerGraphGeneratorError.missingPathInLocalSwiftPackage(name)
                }
                // There's a bug in the `relative` implementation that produces the wrong path when using a symbolic link.
                // This leads to nonexisting path in the `ModuleMapMapper` that relies on that method.
                // To get around this, we're aligning paths from `workspace-state.json` with the /var temporary directory.
                packageFolder = try AbsolutePath(
                    validating: path.replacingOccurrences(of: "/private/var", with: "/var")
                )
                hash = nil
                identityName = packageFolder.basename
            case "registry":
                let registryFolder = path.appending(try RelativePath(validating: "registry/downloads"))
                packageFolder = registryFolder.appending(try RelativePath(validating: dependency.subpath))
                hash = try dependency.state?.version.map { try contentHasher.hash([dependency.packageRef.identity, $0]) }
                identityName = packageFolder.parentDirectory.basename
            default:
                throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
            }

            let loadedPackageInfo = try await manifestLoader.loadPackage(at: packageFolder, disableSandbox: disableSandbox)
            let packageInfo = PackageInfo(
                name: dependency.packageRef.name,
                products: loadedPackageInfo.products,
                targets: loadedPackageInfo.targets,
                traits: loadedPackageInfo.traits,
                dependencies: loadedPackageInfo.dependencies,
                platforms: loadedPackageInfo.platforms,
                cLanguageStandard: loadedPackageInfo.cLanguageStandard,
                cxxLanguageStandard: loadedPackageInfo.cxxLanguageStandard,
                swiftLanguageVersions: loadedPackageInfo.swiftLanguageVersions,
                toolsVersion: loadedPackageInfo.toolsVersion
            )
            let targetToArtifactPaths = try workspaceState.object.artifacts
                .filter { $0.packageRef.identity == dependency.packageRef.identity }
                .reduce(into: [:]) { result, artifact in
                    result[artifact.targetName] = try AbsolutePath(validating: artifact.path)
                }

            return (
                id: dependency.packageRef.identity.lowercased(),
                name: name,
                identityName: identityName,
                manifestName: loadedPackageInfo.name,
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
        packageInfos = Dictionary(grouping: packageInfos, by: \.id)
        .compactMap { _, groupedPackageInfos in
            if let localPackage = groupedPackageInfos.first(where: {
                ["local", "fileSystem", "localSourceControl"].contains($0.kind)
            }) {
                return localPackage
            } else if let registryPackage = groupedPackageInfos.first(where: { $0.kind == "registry" }) {
                return registryPackage
            } else {
                return groupedPackageInfos.first
            }
        }

        var packageReferenceNameByAlias: [String: String] = [:]
        for packageInfo in packageInfos {
            for alias in [
                packageInfo.id,
                packageInfo.name.lowercased(),
                packageInfo.identityName.lowercased(),
                packageInfo.manifestName.lowercased(),
            ] {
                packageReferenceNameByAlias[alias] = packageInfo.name
            }
        }

        packageInfos = packageInfos.map { packageInfo in
            let directDependencyReferenceNameByIdentity = Dictionary<String, String>(
                uniqueKeysWithValues: packageInfo.info.dependencies.compactMap { dependency in
                    guard let referenceName = packageReferenceNameByAlias[dependency.identity.lowercased()] else { return nil }
                    return (dependency.identity.lowercased(), referenceName)
                }
            )

            let normalizedTargets = packageInfo.info.targets.map { target in
                let normalizedDependencies = target.dependencies.map { dependency in
                    switch dependency {
                    case let .product(name, package, moduleAliases, condition):
                        return PackageInfo.Target.Dependency.product(
                            name: name,
                            package: directDependencyReferenceNameByIdentity[package.lowercased()] ?? package,
                            moduleAliases: moduleAliases,
                            condition: condition
                        )
                    case .byName, .target:
                        return dependency
                    }
                }

                return PackageInfo.Target(
                    name: target.name,
                    path: target.path,
                    url: target.url,
                    sources: target.sources,
                    resources: target.resources,
                    exclude: target.exclude,
                    dependencies: normalizedDependencies,
                    publicHeadersPath: target.publicHeadersPath,
                    type: target.type,
                    settings: target.settings,
                    checksum: target.checksum,
                    packageAccess: target.packageAccess
                )
            }

            let normalizedPackageInfo = PackageInfo(
                name: packageInfo.info.name,
                products: packageInfo.info.products,
                targets: normalizedTargets,
                traits: packageInfo.info.traits,
                dependencies: packageInfo.info.dependencies,
                platforms: packageInfo.info.platforms,
                cLanguageStandard: packageInfo.info.cLanguageStandard,
                cxxLanguageStandard: packageInfo.info.cxxLanguageStandard,
                swiftLanguageVersions: packageInfo.info.swiftLanguageVersions,
                toolsVersion: packageInfo.info.toolsVersion
            )

            return (
                id: packageInfo.id,
                name: packageInfo.name,
                identityName: packageInfo.identityName,
                manifestName: packageInfo.manifestName,
                folder: packageInfo.folder,
                targetToArtifactPaths: packageInfo.targetToArtifactPaths,
                info: normalizedPackageInfo,
                hash: packageInfo.hash,
                kind: packageInfo.kind
            )
        }

        let packageInfoDictionary = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.info) })
        let packageInfoDictionaryForExternalDependencies = Dictionary(uniqueKeysWithValues: packageInfos.map {
            (
                $0.name,
                PackageInfo(
                    name: $0.identityName,
                    products: $0.info.products,
                    targets: $0.info.targets,
                    traits: $0.info.traits,
                    dependencies: $0.info.dependencies,
                    platforms: $0.info.platforms,
                    cLanguageStandard: $0.info.cLanguageStandard,
                    cxxLanguageStandard: $0.info.cxxLanguageStandard,
                    swiftLanguageVersions: $0.info.swiftLanguageVersions,
                    toolsVersion: $0.info.toolsVersion
                )
            )
        })
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
            packageInfos: packageInfoDictionaryForExternalDependencies,
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

        return (
            DependenciesGraph(
                externalDependencies: externalDependencies,
                externalProjects: externalProjects
            ),
            outdatedDependencyIssues
        )
    }

    private func validatePackageResolved(at path: AbsolutePath) async throws -> [LintingIssue] {
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
            return [LintingIssue(
                reason: "We detected outdated dependencies. Run `tuist install` to update them.",
                severity: .warning,
                category: .outdatedDependencies
            )]
        }
        return []
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
