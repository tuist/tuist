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
    /// Generates the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
    /// - Parameter path: The path to the directory that contains the `checkouts` directory where `SwiftPackageManager` installed
    /// dependencies.
    func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings
    ) async throws -> TuistLoader.DependenciesGraph
}

public final class SwiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping
    private let manifestLoader: ManifestLoading
    private let fileSystem: FileSysteming

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
    }

    // swiftlint:disable:next function_body_length
    public func load(
        packagePath: AbsolutePath,
        packageSettings: TuistCore.PackageSettings
    ) async throws -> TuistLoader.DependenciesGraph {
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

        try await validatePackageResolved(at: packagePath.parentDirectory)

        let packageInfos: [
            // swiftlint:disable:next large_tuple
            (
                id: String,
                name: String,
                folder: AbsolutePath,
                targetToArtifactPaths: [String: AbsolutePath],
                info: PackageInfo,
                hash: String?
            )
        ]
        packageInfos = try await workspaceState.object.dependencies.concurrentMap { dependency in
            let name = dependency.packageRef.name
            let packageFolder: AbsolutePath
            switch dependency.packageRef.kind {
            case "remote", "remoteSourceControl":
                packageFolder = checkoutsFolder.appending(component: dependency.subpath)
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
            case "registry":
                let registryFolder = path.appending(try RelativePath(validating: "registry/downloads"))
                packageFolder = registryFolder.appending(try RelativePath(validating: dependency.subpath))
            default:
                throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
            }

            let packageInfo = try await self.manifestLoader.loadPackage(at: packageFolder)
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
                hash: dependency.state?.checkoutState?.revision
            )
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

        let externalDependencies = try packageInfoMapper.resolveExternalDependencies(
            packageInfos: packageInfoDictionary,
            packageToFolder: packageToFolder,
            packageToTargetsToArtifactPaths: packageToTargetsToArtifactPaths,
            packageModuleAliases: mutablePackageModuleAliases
        )

        let packageModuleAliases = mutablePackageModuleAliases
        let mappedPackageInfos = try await packageInfos.concurrentMap { packageInfo in
            (
                packageInfo: packageInfo,
                hash: packageInfo.hash,
                projectManifest: try await self.packageInfoMapper.map(
                    packageInfo: packageInfo.info,
                    path: packageInfo.folder,
                    packageType: .external(artifactPaths: packageToTargetsToArtifactPaths[packageInfo.name] ?? [:]),
                    packageSettings: packageSettings,
                    packageModuleAliases: packageModuleAliases
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

        return DependenciesGraph(
            externalDependencies: externalDependencies,
            externalProjects: externalProjects
        )
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
            logger.warning("We detected outdated dependencies. Please run \"tuist install\" to update them.")
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
