import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             xcodeProjPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) throws -> (Project, Graph)
}

final class ProjectEditorMapper: ProjectEditorMapping {
    // swiftlint:disable:next function_body_length
    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             xcodeProjPath: AbsolutePath,
             manifests: [AbsolutePath],
             helpers: [AbsolutePath],
             templates: [AbsolutePath],
             projectDescriptionPath: AbsolutePath) throws -> (Project, Graph)
    {
        // Settings
        let projectSettings = Settings(base: [:],
                                       configurations: Settings.default.configurations,
                                       defaultSettings: .recommended)

        let swiftVersion = try System.shared.swiftVersion()
        let targetSettings = Settings(base: settings(projectDescriptionPath: projectDescriptionPath, swiftVersion: swiftVersion),
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

        let manifestsTargets = named(manifests: manifests).map { name, manifest in
            Target(name: name,
                   platform: .macOS,
                   product: .staticFramework,
                   productName: name,
                   bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
                   settings: targetSettings,
                   sources: [(path: manifest, compilerFlags: nil)],
                   filesGroup: .group(name: "Manifests"),
                   dependencies: manifestsDependencies)
        }

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
        targets.append(contentsOf: manifestsTargets)
        if let helpersTarget = helpersTarget { targets.append(helpersTarget) }
        if let templatesTarget = templatesTarget { targets.append(templatesTarget) }

        // Run Scheme
        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: sourceRootPath, name: $0.name) })
        let arguments = Arguments(launch: ["generate --path \(sourceRootPath)": true])
        let runAction = RunAction(configurationName: "Debug", executable: nil, filePath: tuistPath, arguments: arguments, diagnosticsOptions: Set())
        let scheme = Scheme(name: "Manifests", shared: true, buildAction: buildAction, runAction: runAction)

        // Project
        let project = Project(path: sourceRootPath,
                              sourceRootPath: sourceRootPath,
                              xcodeProjPath: xcodeProjPath,
                              name: "Manifests",
                              organizationName: nil,
                              settings: projectSettings,
                              filesGroup: .group(name: "Manifests"),
                              targets: targets,
                              packages: [],
                              schemes: [scheme],
                              additionalFiles: [])

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

        let manifestTargetNodes = manifestsTargets.map { TargetNode(project: project, target: $0, dependencies: dependencies) }

        let graph = Graph(name: "Manifests",
                          entryPath: sourceRootPath,
                          entryNodes: manifestTargetNodes,
                          projects: [project],
                          cocoapods: [],
                          packages: [],
                          precompiled: [],
                          targets: [sourceRootPath: manifestTargetNodes + dependencies])

        // Project
        return (project, graph)
    }

    /// It returns the build settings that should be used in the manifests target.
    /// - Parameter projectDescriptionPath: Path to the ProjectDescription framework.
    /// - Parameter swiftVersion: The system's Swift version.
    fileprivate func settings(projectDescriptionPath: AbsolutePath, swiftVersion: String) -> SettingsDictionary {
        let frameworkParentDirectory = projectDescriptionPath.parentDirectory
        var buildSettings = SettingsDictionary()
        buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["LIBRARY_SEARCH_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_INCLUDE_PATHS"] = .string(frameworkParentDirectory.pathString)
        buildSettings["SWIFT_VERSION"] = .string(swiftVersion)
        return buildSettings
    }

    /// It returns a dictionary with unique name as key for each Manifest file
    /// - Parameter manifests: Manifest files to assign an unique name
    /// - Returns: Dictionary composed by unique name as key and Manifest file as value.
    fileprivate func named(manifests: [AbsolutePath]) -> [String: AbsolutePath] {
        manifests.reduce(into: [String: AbsolutePath]()) { result, manifest in
            var name = "\(manifest.parentDirectory.basename)Manifests"
            while result[name] != nil {
                name = "_\(name)"
            }
            result[name] = manifest
        }
    }
}

private extension Target {
    /// Target for edit project
    static func editorHelperTarget(name: String,
                                   targetSettings: Settings,
                                   sourcePaths: [AbsolutePath]) -> Target
    {
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
