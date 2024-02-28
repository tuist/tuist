import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

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
        at path: AbsolutePath,
        plugins: Plugins
    ) throws -> TuistCore.DependenciesGraph
}

public final class SwiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping
    private let manifestLoader: ManifestLoading
    private let fileHandler: FileHandling
    private let packageSettingsLoader: PackageSettingsLoading
    private let manifestFilesLocator: ManifestFilesLocating

    public convenience init(
        manifestLoader: ManifestLoading
    ) {
        self.init(
            manifestLoader: manifestLoader,
            packageSettingsLoader: PackageSettingsLoader(manifestLoader: manifestLoader)
        )
    }

    init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        fileHandler: FileHandling = FileHandler.shared,
        packageSettingsLoader: PackageSettingsLoading = PackageSettingsLoader(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
        self.manifestLoader = manifestLoader
        self.fileHandler = fileHandler
        self.packageSettingsLoader = packageSettingsLoader
        self.manifestFilesLocator = manifestFilesLocator
    }

    // swiftlint:disable:next function_body_length
    public func load(
        at path: AbsolutePath,
        plugins: Plugins
    ) throws -> TuistCore.DependenciesGraph {
        guard let packagePath = manifestFilesLocator.locatePackageManifest(at: path)
        else {
            return .none
        }

        let packageSettings = try packageSettingsLoader.loadPackageSettings(at: packagePath.parentDirectory, with: plugins)

        let path = packagePath.parentDirectory.appending(
            component: Constants.SwiftPackageManager.packageBuildDirectoryName
        )
        let checkoutsFolder = path.appending(component: "checkouts")
        let workspacePath = path.appending(component: "workspace-state.json")

        if !fileHandler.exists(workspacePath) {
            throw SwiftPackageManagerGraphGeneratorError.installRequired
        }

        let workspaceState = try JSONDecoder()
            .decode(SwiftPackageManagerWorkspaceState.self, from: try fileHandler.readFile(workspacePath))
        let packageInfos: [
            // swiftlint:disable:next large_tuple
            (id: String, name: String, folder: AbsolutePath, targetToArtifactPaths: [String: AbsolutePath], info: PackageInfo)
        ]
        packageInfos = try workspaceState.object.dependencies.map(context: .concurrent) { dependency in
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
                packageFolder = try AbsolutePath(validating: path)
            case "registry":
                let registryFolder = path.appending(try RelativePath(validating: "registry/downloads"))
                packageFolder = registryFolder.appending(try RelativePath(validating: dependency.subpath))
            default:
                throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
            }

            let packageInfo = try manifestLoader.loadPackage(at: packageFolder)
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
                info: packageInfo
            )
        }

        let idToPackage: [String: String] = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.id, $0.name) })
        let packageToProject = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.folder) })
        let packageInfoDictionary = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.info) })
        let packageToFolder = Dictionary(uniqueKeysWithValues: packageInfos.map { ($0.name, $0.folder) })
        let packageToTargetsToArtifactPaths = Dictionary(uniqueKeysWithValues: packageInfos.map {
            ($0.name, $0.targetToArtifactPaths)
        })

        let preprocessInfo = try packageInfoMapper.preprocess(
            packageInfos: packageInfoDictionary,
            idToPackage: idToPackage,
            packageToFolder: packageToFolder,
            packageToTargetsToArtifactPaths: packageToTargetsToArtifactPaths
        )

        let externalProjects: [Path: ProjectDescription.Project] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            let manifest = try packageInfoMapper.map(
                packageInfo: packageInfo.info,
                path: packageInfo.folder,
                productTypes: packageSettings.productTypes,
                baseSettings: packageSettings.baseSettings,
                targetSettings: packageSettings.targetSettings,
                projectOptions: packageSettings.projectOptions[packageInfo.name],
                packageToProject: packageToProject,
                swiftToolsVersion: packageSettings.swiftToolsVersion
            )
            result[.path(packageInfo.folder.pathString)] = manifest
        }

        return DependenciesGraph(
            externalDependencies: preprocessInfo.productToExternalDependencies,
            externalProjects: externalProjects
        )
    }
}

extension ProjectDescription.Platform {
    /// Maps a TuistGraph.Platform instance into a  ProjectDescription.Platform instance.
    /// - Parameters:
    ///   - graph: Graph representation of platform model.
    static func from(graph: TuistGraph.Platform) -> ProjectDescription.Platform {
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
