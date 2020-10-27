import Foundation
import TSCBasic
import TuistCore
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(tuistPath: AbsolutePath,
             sourceRootPath: AbsolutePath,
             xcodeProjPath: AbsolutePath,
             setupPath: AbsolutePath?,
             configPath: AbsolutePath?,
             dependenciesPath: AbsolutePath?,
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
             setupPath: AbsolutePath?,
             configPath: AbsolutePath?,
             dependenciesPath: AbsolutePath?,
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
        var setupTarget: Target?
        if let setupPath = setupPath {
            setupTarget = Target.editorHelperTarget(name: "Setup",
                                                    targetSettings: targetSettings,
                                                    sourcePaths: [setupPath])
        }
        var configTarget: Target?
        if let configPath = configPath {
            configTarget = Target.editorHelperTarget(name: "Config",
                                                     targetSettings: targetSettings,
                                                     sourcePaths: [configPath])
        }
        var dependenciesTarget: Target?
        if let dependenciesPath = dependenciesPath {
            dependenciesTarget = Target.editorHelperTarget(name: "Dependencies",
                                                           targetSettings: targetSettings,
                                                           sourcePaths: [dependenciesPath])
        }

        var targets: [Target] = []
        targets.append(contentsOf: manifestsTargets)
        if let helpersTarget = helpersTarget { targets.append(helpersTarget) }
        if let templatesTarget = templatesTarget { targets.append(templatesTarget) }
        if let setupTarget = setupTarget { targets.append(setupTarget) }
        if let configTarget = configTarget { targets.append(configTarget) }
        if let dependenciesTarget = dependenciesTarget { targets.append(dependenciesTarget) }

        // Run Scheme
        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: sourceRootPath, name: $0.name) })
        let arguments = Arguments(launchArguments: ["generate --path \(sourceRootPath)": true])
        let runAction = RunAction(configurationName: "Debug", executable: nil, filePath: tuistPath, arguments: arguments, diagnosticsOptions: Set())
        let scheme = Scheme(name: "Manifests", shared: true, buildAction: buildAction, runAction: runAction)

        // Project
        let project = Project(path: sourceRootPath,
                              sourceRootPath: sourceRootPath,
                              xcodeProjPath: xcodeProjPath,
                              name: "Manifests",
                              organizationName: nil,
                              developmentRegion: nil,
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
        if let setupTarget = setupTarget {
            let setupNode = TargetNode(project: project, target: setupTarget, dependencies: [])
            dependencies.append(setupNode)
        }
        if let configTarget = configTarget {
            let configNode = TargetNode(project: project, target: configTarget, dependencies: [])
            dependencies.append(configNode)
        }
        if let dependenciesTarget = dependenciesTarget {
            let dependenciesNode = TargetNode(project: project, target: dependenciesTarget, dependencies: [])
            dependencies.append(dependenciesNode)
        }

        let manifestTargetNodes = manifestsTargets.map { TargetNode(project: project, target: $0, dependencies: dependencies) }
        let workspace = Workspace(path: project.path, name: "Manifests", projects: [project.path])

        let graph = Graph(
            name: "Manifests",
            entryPath: sourceRootPath,
            entryNodes: manifestTargetNodes,
            workspace: workspace,
            projects: [project],
            cocoapods: [],
            packages: [],
            precompiled: [],
            targets: [sourceRootPath: manifestTargetNodes + dependencies]
        )

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
