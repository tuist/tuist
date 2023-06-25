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

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unsupportedDependencyKind, .missingPathInLocalSwiftPackage:
            return .bug
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .unsupportedDependencyKind(name):
            return "The dependency kind \(name) is not supported."
        case let .missingPathInLocalSwiftPackage(name):
            return "The local package \(name) does not contain the path in the generated `workspace-state.json` file."
        }
    }
}

// MARK: - Swift Package Manager Graph Generator

/// A protocol that defines an interface to generate the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
public protocol SwiftPackageManagerGraphGenerating {
    /// Generates the `DependenciesGraph` for the `SwiftPackageManager` dependencies.
    /// - Parameter path: The path to the directory that contains the `checkouts` directory where `SwiftPackageManager` installed dependencies.
    /// - Parameter productTypes: The custom `Product` types to be used for SPM targets.
    /// - Parameter platforms: The supported platforms.
    /// - Parameter baseSettings: base `Settings` for targets.
    /// - Parameter targetSettings: `SettingsDictionary` overrides for targets.
    /// - Parameter swiftToolsVersion: The version of Swift tools that will be used to generate dependencies.
    /// - Parameter projectOptions: The custom configurations for generated projects.
    func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        swiftToolsVersion: TSCUtility.Version?,
        projectOptions: [String: TuistGraph.Project.Options]
    ) throws -> TuistCore.DependenciesGraph
}

public final class SwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoMapper: PackageInfoMapping

    public init(
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        packageInfoMapper: PackageInfoMapping = PackageInfoMapper()
    ) {
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoMapper = packageInfoMapper
    }

    // swiftlint:disable:next function_body_length
    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        swiftToolsVersion: TSCUtility.Version?,
        projectOptions: [String: TuistGraph.Project.Options]
    ) throws -> TuistCore.DependenciesGraph {
        let checkoutsFolder = path.appending(component: "checkouts")
        let workspacePath = path.appending(component: "workspace-state.json")

        let workspaceState = try JSONDecoder()
            .decode(SwiftPackageManagerWorkspaceState.self, from: try FileHandler.shared.readFile(workspacePath))
        let packageInfos: [
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
            default:
                throw SwiftPackageManagerGraphGeneratorError.unsupportedDependencyKind(dependency.packageRef.kind)
            }

            let packageInfo = try swiftPackageManagerController.loadPackageInfo(at: packageFolder)
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
            packageToTargetsToArtifactPaths: packageToTargetsToArtifactPaths,
            platforms: platforms
        )

        let externalProjects: [Path: ProjectDescription.Project] = try packageInfos.reduce(into: [:]) { result, packageInfo in
            let manifest = try packageInfoMapper.map(
                packageInfo: packageInfo.info,
                packageInfos: packageInfoDictionary,
                name: packageInfo.name,
                path: packageInfo.folder,
                productTypes: productTypes,
                baseSettings: baseSettings,
                targetSettings: targetSettings,
                projectOptions: projectOptions[packageInfo.name],
                minDeploymentTargets: preprocessInfo.platformToMinDeploymentTarget,
                platforms: preprocessInfo.platforms,
                targetToProducts: preprocessInfo.targetToProducts,
                targetToResolvedDependencies: preprocessInfo.targetToResolvedDependencies,
                targetToModuleMap: preprocessInfo.targetToModuleMap,
                packageToProject: packageToProject,
                swiftToolsVersion: swiftToolsVersion
            )
            result[Path(packageInfo.folder.pathString)] = manifest
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
