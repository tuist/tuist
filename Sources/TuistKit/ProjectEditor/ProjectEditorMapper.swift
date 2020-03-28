import Basic
import Foundation
import TuistCore
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) -> (Project, Graph)
}

final class ProjectEditorMapper: ProjectEditorMapping {
    // swiftlint:disable:next function_body_length
    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
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
        if !templates.isEmpty {
            manifestsDependencies.append(.target(name: "Templates"))
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
            helpersTarget = Target.editorHelperTarget(name: "ProjectDescriptionHelpers",
                                                      targetSettings: targetSettings,
                                                      sourcePaths: helpers)
        }
        var templatesTarget: Target?
        if !templates.isEmpty {
            templatesTarget = Target.editorHelperTarget(name: "Templates",
                                                        targetSettings: targetSettings,
                                                        sourcePaths: templates)
        }

        var targets: [Target] = []
        targets.append(manifestsTarget)
        if let helpersTarget = helpersTarget { targets.append(helpersTarget) }
        if let templatesTarget = templatesTarget { targets.append(templatesTarget) }

        // Run Scheme
        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: sourceRootPath, name: $0.name) })
        let arguments = Arguments(launch: ["generate --path \(sourceRootPath)": true])

        let runAction = RunAction(configurationName: "Debug", filePath: tuistPath, arguments: arguments)
        let scheme = Scheme(name: "Manifests", shared: true, buildAction: buildAction, runAction: runAction)

        // Project
        let project = Project(path: sourceRootPath,
                              name: "Manifests",
                              settings: projectSettings,
                              filesGroup: .group(name: "Manifests"),
                              targets: targets,
                              schemes: [scheme])

        // Graph
        var dependencies: [TargetNode] = []

        if let helpersTarget = helpersTarget {
            let helpersNode = TargetNode(project: project, target: helpersTarget, dependencies: [])
            dependencies.append(helpersNode)
        }
        if let templatesTarget = templatesTarget {
            let templatesNode = TargetNode(project: project, target: templatesTarget, dependencies: [])
            dependencies.append(templatesNode)
        }

        let manifestTargetNode = TargetNode(project: project, target: manifestsTarget, dependencies: dependencies)

        let graph = Graph(name: "Manifests",
                          entryPath: sourceRootPath,
                          entryNodes: [manifestTargetNode],
                          projects: [project],
                          cocoapods: [],
                          packages: [],
                          precompiled: [],
                          targets: [sourceRootPath: [manifestTargetNode] + dependencies])

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

private extension Target {
    /// Target for edit project
    static func editorHelperTarget(name: String,
                                   targetSettings: Settings,
                                   sourcePaths: [AbsolutePath]) -> Target {
        Target(name: name,
               platform: .macOS,
               product: .staticFramework,
               productName: name,
               bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
               settings: targetSettings,
               sources: sourcePaths.map { (path: $0, compilerFlags: nil) },
               filesGroup: .group(name: "Manifests"))
    }
}
