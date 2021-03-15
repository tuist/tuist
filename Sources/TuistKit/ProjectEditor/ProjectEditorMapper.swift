import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

protocol ProjectEditorMapping: AnyObject {
    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> ValueGraph
}

final class ProjectEditorMapper: ProjectEditorMapping {
    func map(
        name: String,
        tuistPath: AbsolutePath,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        projectManifests: [AbsolutePath],
        editablePluginManifests: [EditablePluginManifest],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule],
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        projectDescriptionPath: AbsolutePath
    ) throws -> ValueGraph {
        let swiftVersion = try System.shared.swiftVersion()

        let pluginsProject = mapPluginsProject(
            pluginManifests: editablePluginManifests,
            projectDescriptionPath: projectDescriptionPath,
            swiftVersion: swiftVersion,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
            tuistPath: tuistPath
        )

        let manifestsProject = mapManifestsProject(
            projectManifests: projectManifests,
            projectDescriptionPath: projectDescriptionPath,
            swiftVersion: swiftVersion,
            sourceRootPath: sourceRootPath,
            destinationDirectory: destinationDirectory,
            tuistPath: tuistPath,
            helpers: helpers,
            templates: templates,
            setupPath: setupPath,
            configPath: configPath,
            dependenciesPath: dependenciesPath,
            editablePluginTargets: editablePluginManifests.map(\.name),
            pluginProjectDescriptionHelpersModule: pluginProjectDescriptionHelpersModule
        )

        let projects = [pluginsProject, manifestsProject].compactMap { $0 }

        let workspace = Workspace(
            path: sourceRootPath,
            xcWorkspacePath: destinationDirectory.appending(component: "\(name).xcworkspace"),
            name: name,
            projects: projects.map(\.path)
        )

        let graphProjects = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })

        let graphTargets = projects
            .lazy
            .map { ($0.path, $0.targets) }
            .map { path, targets in (path, Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })) }

        let graphDependencies = projects
            .lazy
            .flatMap { project -> [(ValueGraphDependency, Set<ValueGraphDependency>)] in
                let graphDependencies = project.targets.map(\.dependencies).lazy.map { dependencies in
                    dependencies.lazy.compactMap { dependency -> ValueGraphDependency? in
                        switch dependency {
                        case let .target(name):
                            if let pluginsProject = pluginsProject, editablePluginManifests.contains(where: { $0.name == name }) {
                                return .target(name: name, path: pluginsProject.path)
                            } else {
                                return .target(name: name, path: project.path)
                            }
                        default:
                            return nil
                        }
                    }
                }

                return zip(project.targets, graphDependencies).map { target, dependencies in
                    (ValueGraphDependency.target(name: target.name, path: project.path), Set(dependencies))
                }
            }

        return ValueGraph(
            name: name,
            path: sourceRootPath,
            workspace: workspace,
            projects: graphProjects,
            packages: [:],
            targets: Dictionary(uniqueKeysWithValues: graphTargets),
            dependencies: Dictionary(uniqueKeysWithValues: graphDependencies)
        )
    }

    private func mapManifestsProject(
        projectManifests: [AbsolutePath],
        projectDescriptionPath: AbsolutePath,
        swiftVersion: String,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        tuistPath: AbsolutePath,
        helpers: [AbsolutePath],
        templates: [AbsolutePath],
        setupPath: AbsolutePath?,
        configPath: AbsolutePath?,
        dependenciesPath: AbsolutePath?,
        editablePluginTargets: [String],
        pluginProjectDescriptionHelpersModule: [ProjectDescriptionHelpersModule]
    ) -> Project? {
        guard !projectManifests.isEmpty else { return nil }

        let projectName = "Manifests"
        let projectPath = sourceRootPath.appending(component: projectName)
        let manifestsFilesGroup = ProjectGroup.group(name: projectName)
        let baseTargetSettings = Settings(
            base: targetBaseSettings(for: [projectDescriptionPath], swiftVersion: swiftVersion),
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let helpersTarget: Target? = {
            guard !helpers.isEmpty else { return nil }
            return editorHelperTarget(
                name: Constants.helpersDirectoryName,
                filesGroup: manifestsFilesGroup,
                targetSettings: baseTargetSettings,
                sourcePaths: helpers
            )
        }()

        let templatesTarget: Target? = {
            guard !templates.isEmpty else { return nil }
            return editorHelperTarget(
                name: Constants.templatesDirectoryName,
                filesGroup: manifestsFilesGroup,
                targetSettings: baseTargetSettings,
                sourcePaths: templates
            )
        }()

        let setupTarget: Target? = {
            guard let setupPath = setupPath else { return nil }
            return editorHelperTarget(
                name: "Setup",
                filesGroup: manifestsFilesGroup,
                targetSettings: baseTargetSettings,
                sourcePaths: [setupPath]
            )
        }()

        let configTarget: Target? = {
            guard let configPath = configPath else { return nil }
            return editorHelperTarget(
                name: "Config",
                filesGroup: manifestsFilesGroup,
                targetSettings: baseTargetSettings,
                sourcePaths: [configPath]
            )
        }()

        let dependenciesTarget: Target? = {
            guard let dependenciesPath = dependenciesPath else { return nil }
            return editorHelperTarget(
                name: "Dependencies",
                filesGroup: manifestsFilesGroup,
                targetSettings: baseTargetSettings,
                sourcePaths: [dependenciesPath]
            )
        }()

        let manifestTargetSettings = Settings(
            base: targetBaseSettings(for: [projectDescriptionPath] + pluginProjectDescriptionHelpersModule.map(\.path), swiftVersion: swiftVersion),
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let manifestsTargets = namedManifests(projectManifests).map { name, projectManifestSourcePath -> Target in
            let helperDependencies = helpersTarget.map { [TargetDependency.target(name: $0.name)] } ?? []
            let editablePluginTargets = editablePluginTargets.map { TargetDependency.target(name: $0) }
            let dependencies = helperDependencies + editablePluginTargets

            return editorHelperTarget(
                name: name,
                filesGroup: manifestsFilesGroup,
                targetSettings: manifestTargetSettings,
                sourcePaths: [projectManifestSourcePath],
                dependencies: dependencies
            )
        }

        let targets = [
            helpersTarget,
            templatesTarget,
            setupTarget,
            configTarget,
            dependenciesTarget,
        ].compactMap { $0 } + manifestsTargets

        let buildAction = BuildAction(targets: targets.map { TargetReference(projectPath: projectPath, name: $0.name) })
        let arguments = Arguments(launchArguments: [LaunchArgument(name: "generate --path \(sourceRootPath)", isEnabled: true)])
        let runAction = RunAction(configurationName: "Debug", executable: nil, filePath: tuistPath, arguments: arguments, diagnosticsOptions: Set())
        let scheme = Scheme(name: projectName, shared: true, buildAction: buildAction, runAction: runAction)
        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64",
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        return Project(
            path: projectPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: destinationDirectory.appending(component: "\(projectName).xcodeproj"),
            name: projectName,
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: manifestsFilesGroup,
            targets: targets,
            packages: [],
            schemes: [scheme],
            ideTemplateMacros: nil,
            additionalFiles: []
        )
    }

    private func mapPluginsProject(
        pluginManifests: [EditablePluginManifest],
        projectDescriptionPath: AbsolutePath,
        swiftVersion: String,
        sourceRootPath: AbsolutePath,
        destinationDirectory: AbsolutePath,
        tuistPath _: AbsolutePath
    ) -> Project? {
        guard !pluginManifests.isEmpty else { return nil }

        let projectName = "Plugins"
        let projectPath = sourceRootPath.appending(component: projectName)
        let pluginsFilesGroup = ProjectGroup.group(name: projectName)
        let targetSettings = Settings(
            base: targetBaseSettings(for: [projectDescriptionPath], swiftVersion: swiftVersion),
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        let pluginTargets = pluginManifests.map { manifest -> Target in
            let pluginManifest = manifest.path.appending(component: "Plugin.swift")
            let pluginHelpersPath = manifest.path.appending(component: Constants.helpersDirectoryName)
            let sourcePaths = [pluginManifest] + FileHandler.shared.glob(pluginHelpersPath, glob: "**/*.swift")
            return editorHelperTarget(
                name: manifest.name,
                filesGroup: pluginsFilesGroup,
                targetSettings: targetSettings,
                sourcePaths: sourcePaths,
                dependencies: []
            )
        }

        let schemes = pluginTargets.map { target -> Scheme in
            let buildAction = BuildAction(targets: [TargetReference(projectPath: projectPath, name: target.name)])
            return Scheme(name: target.name, shared: true, buildAction: buildAction, runAction: nil)
        }

        let allPluginsScheme = Scheme(
            name: "Plugins",
            shared: true,
            buildAction: BuildAction(targets: pluginTargets.map { TargetReference(projectPath: projectPath, name: $0.name) }),
            runAction: nil
        )

        let allSchemes = schemes + [allPluginsScheme]

        let projectSettings = Settings(
            base: [
                "ONLY_ACTIVE_ARCH": "NO",
                "EXCLUDED_ARCHS": "arm64",
            ],
            configurations: Settings.default.configurations,
            defaultSettings: .recommended
        )

        return Project(
            path: projectPath,
            sourceRootPath: sourceRootPath,
            xcodeProjPath: destinationDirectory.appending(component: "\(projectName).xcodeproj"),
            name: projectName,
            organizationName: nil,
            developmentRegion: nil,
            settings: projectSettings,
            filesGroup: pluginsFilesGroup,
            targets: pluginTargets,
            packages: [],
            schemes: allSchemes,
            ideTemplateMacros: nil,
            additionalFiles: []
        )
    }

    /// Collects all targets into a dictionary where each key is a reference to a target
    /// which maps to a set of target references representing the target's dependencies.
    /// - Parameters:
    ///   - targets: The targets to map to their dependencies.
    ///   - projectPath: The path to the project where the targets are defined.
    /// - Returns: dictionary where each key is a reference to a target and value is the target's dependencies.
    private func mapTargetsToDependencies(
        targets: [Target],
        projectPath: AbsolutePath
    ) -> [TargetReference: Set<TargetReference>] {
        targets.reduce(into: [TargetReference: Set<TargetReference>]()) { result, target in
            let dependencyRefs = target.dependencies.lazy.compactMap { dependency -> TargetReference? in
                switch dependency {
                case let .target(name):
                    return TargetReference(projectPath: projectPath, name: name)
                default:
                    return nil
                }
            }
            result[TargetReference(projectPath: projectPath, name: target.name)] = Set(dependencyRefs)
        }
    }

    /// It returns a dictionary with unique name as key for each Manifest file
    /// - Parameter manifests: Manifest files to assign an unique name
    /// - Returns: Dictionary composed by unique name as key and Manifest file as value.
    private func namedManifests(_ manifests: [AbsolutePath]) -> [String: AbsolutePath] {
        manifests.reduce(into: [String: AbsolutePath]()) { result, manifest in
            var name = "\(manifest.parentDirectory.basename)Manifests"
            while result[name] != nil {
                name = "_\(name)"
            }
            result[name] = manifest
        }
    }

    /// It returns a target for edit project.
    /// - Parameters:
    ///   - name: Name for the target.
    ///   - filesGroup: File group for target.
    ///   - targetSettings: Target's settings.
    ///   - sourcePaths: Target's sources.
    ///   - dependencies: Target's dependencies.
    /// - Returns: Target for edit project.
    private func editorHelperTarget(
        name: String,
        filesGroup: ProjectGroup,
        targetSettings: Settings,
        sourcePaths: [AbsolutePath],
        dependencies: [TargetDependency] = []
    ) -> Target {
        Target(
            name: name,
            platform: .macOS,
            product: .staticFramework,
            productName: name,
            bundleId: "io.tuist.${PRODUCT_NAME:rfc1034identifier}",
            settings: targetSettings,
            sources: sourcePaths.map { SourceFile(path: $0, compilerFlags: nil) },
            filesGroup: filesGroup,
            dependencies: dependencies
        )
    }

    private func targetBaseSettings(for includes: [AbsolutePath], swiftVersion: String) -> SettingsDictionary {
        let includePaths = includes.map(\.parentDirectory.pathString)
        return [
            "FRAMEWORK_SEARCH_PATHS": .array(includePaths),
            "LIBRARY_SEARCH_PATHS": .array(includePaths),
            "SWIFT_INCLUDE_PATHS": .array(includePaths),
            "SWIFT_VERSION": .string(swiftVersion),
        ]
    }
}
