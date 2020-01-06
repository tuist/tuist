import Basic
import Foundation
import TuistCore
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(sourceRootPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) -> (Project, Graph)
}

final class ProjectEditorMapper: ProjectEditorMapping {
    // swiftlint:disable:next function_body_length
    func map(sourceRootPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) -> (Project, Graph) {
        // Settings
        let projectSettings = Settings(base: [:],
                                       configurations: Settings.default.configurations,
                                       defaultSettings: .recommended)

        let targetSettings = Settings(base: settings(projectDescriptionPath: projectDescriptionPath),
                                      configurations: Settings.default.configurations,
                                      defaultSettings: .recommended)

        // Targets
        var manifestsDependencies: [Dependency] = []
        if !helpers.isEmpty {
            manifestsDependencies = [.target(name: "ProjectDescriptionHelpers")]
        }
        let manifestsTarget = Target(name: "Manifests",
                                     platform: .macOS,
                                     product: .staticFramework,
                                     productName: "Manifests",
                                     bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
                                     settings: targetSettings,
                                     sources: manifests.map { (path: $0, compilerFlags: nil) },
                                     filesGroup: .group(name: "Manifests"),
                                     dependencies: manifestsDependencies)
        var helpersTarget: Target?
        if !helpers.isEmpty {
            helpersTarget = Target(name: "ProjectDescriptionHelpers",
                                   platform: .macOS,
                                   product: .staticFramework,
                                   productName: "ProjectDescriptionHelpers",
                                   bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
                                   settings: targetSettings,
                                   sources: helpers.map { (path: $0, compilerFlags: nil) },
                                   filesGroup: .group(name: "Manifests"))
        }
        var targets: [Target] = []
        targets.append(manifestsTarget)
        if let helpersTarget = helpersTarget { targets.append(helpersTarget) }

        // Project
        let project = Project(path: sourceRootPath,
                              name: "Manifests",
                              settings: projectSettings,
                              filesGroup: .group(name: "Manifests"),
                              targets: targets)

        // Graph
        let cache = GraphLoaderCache()
        let graph = Graph(name: "Manifests", entryPath: sourceRootPath, cache: cache)
        var dependencies: [TargetNode] = []

        if let helpersTarget = helpersTarget {
            let helpersNode = TargetNode(project: project, target: helpersTarget, dependencies: [])
            cache.add(targetNode: helpersNode)
            dependencies.append(helpersNode)
        }
        cache.add(targetNode: TargetNode(project: project, target: manifestsTarget, dependencies: dependencies))

        // Project
        return (project, graph)
    }

    /// It returns the build settings that should be used in the manifests target.
    /// - Parameter projectDescriptionPath: Path to the ProjectDescription framework.
    fileprivate func settings(projectDescriptionPath: AbsolutePath) -> [String: SettingValue] {
        let frameworkParentDirectory = projectDescriptionPath.parentDirectory
        var buildSettings = [String: SettingValue]()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["LIBRARY_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_INCLUDE_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_VERSION"] = .string(Constants.swiftVersion)
        return buildSettings
    }
}
