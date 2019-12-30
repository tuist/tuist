import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

public enum GeneratorModelLoaderError: Error, Equatable, FatalError {
    case missingFile(AbsolutePath)
    public var type: ErrorType {
        switch self {
        case .missingFile:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .missingFile(path):
            return "Couldn't find file at path '\(path.pathString)'"
        }
    }
}

public class GeneratorModelLoader: GeneratorModelLoading {
    private let manifestLoader: ManifestLoading
    private let manifestLinter: ManifestLinting

    public init(manifestLoader: ManifestLoading,
                manifestLinter: ManifestLinting) {
        self.manifestLoader = manifestLoader
        self.manifestLinter = manifestLinter
    }

    /// Load a Project model at the specified path
    ///
    /// - Parameters:
    ///   - path: The absolute path for the project model to load.
    /// - Returns: The Project loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing project)
    public func loadProject(at path: AbsolutePath) throws -> TuistCore.Project {
        let manifest = try manifestLoader.loadProject(at: path)
        let tuistConfig = try loadTuistConfig(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)

        try manifestLinter.lint(project: manifest)
            .printAndThrowIfNeeded()

        let project = try TuistCore.Project.from(manifest: manifest,
                                                 path: path,
                                                 generatorPaths: generatorPaths)

        return try enriched(model: project, with: tuistConfig)
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> TuistCore.Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try TuistCore.Workspace.from(manifest: manifest,
                                                     path: path,
                                                     generatorPaths: generatorPaths,
                                                     manifestLoader: manifestLoader)
        return workspace
    }

    public func loadTuistConfig(at path: AbsolutePath) throws -> TuistCore.TuistConfig {
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        guard let tuistConfigPath = FileHandler.shared.locateDirectoryTraversingParents(from: path, path: Manifest.tuistConfig.fileName) else {
            return TuistCore.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistCore.TuistConfig(manifest: manifest, generatorPaths: generatorPaths)
    }

    private func enriched(model: TuistCore.Project,
                          with config: TuistCore.TuistConfig) throws -> TuistCore.Project {
        var enrichedModel = model

        // Xcode project file name
        let xcodeFileName = xcodeFileNameOverride(from: config, for: model)
        enrichedModel = enrichedModel.replacing(fileName: xcodeFileName)

        return enrichedModel
    }

    private func xcodeFileNameOverride(from config: TuistCore.TuistConfig,
                                       for model: TuistCore.Project) -> String? {
        var xcodeFileName = config.generationOptions.compactMap { item -> String? in
            switch item {
            case let .xcodeProjectName(projectName):
                return projectName.description
            }
        }.first

        let projectNameTemplate = TemplateString.Token.projectName.rawValue
        xcodeFileName = xcodeFileName?.replacingOccurrences(of: projectNameTemplate,
                                                            with: model.name)

        return xcodeFileName
    }
}

extension TuistCore.Workspace {
    static func from(manifest: ProjectDescription.Workspace,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     manifestLoader: ManifestLoading) throws -> TuistCore.Workspace {
        func globProjects(_ path: Path) throws -> [AbsolutePath] {
            let resolvedPath = try generatorPaths.resolve(path: path)
            let projects = FileHandler.shared.glob(AbsolutePath("/"), glob: String(resolvedPath.pathString.dropFirst()))
                .lazy
                .filter(FileHandler.shared.isFolder)
                .filter {
                    manifestLoader.manifests(at: $0).contains(.project)
                }

            if projects.isEmpty {
                Printer.shared.print(warning: "No projects found at: \(path.pathString)")
            }

            return Array(projects)
        }

        let additionalFiles = try manifest.additionalFiles.flatMap {
            try TuistCore.FileElement.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme.from(manifest: $0, workspacePath: path, generatorPaths: generatorPaths) }

        return TuistCore.Workspace(path: path,
                                   name: manifest.name,
                                   projects: try manifest.projects.flatMap(globProjects),
                                   schemes: schemes,
                                   additionalFiles: additionalFiles)
    }
}

extension TuistCore.FileElement {
    static func from(manifest: ProjectDescription.FileElement,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }) throws -> [TuistCore.FileElement] {
        func globFiles(_ path: AbsolutePath) -> [AbsolutePath] {
            let files = FileHandler.shared.glob(AbsolutePath("/"), glob: String(path.pathString.dropFirst()))
                .filter(includeFiles)

            if files.isEmpty {
                if FileHandler.shared.isFolder(path) {
                    Printer.shared.print(warning: "'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files")
                } else {
                    Printer.shared.print(warning: "No files found at: \(path.pathString)")
                }
            }

            return files
        }

        func folderReferences(_ path: AbsolutePath) -> [AbsolutePath] {
            guard FileHandler.shared.exists(path) else {
                Printer.shared.print(warning: "\(path.pathString) does not exist")
                return []
            }

            guard FileHandler.shared.isFolder(path) else {
                Printer.shared.print(warning: "\(path.pathString) is not a directory - folder reference paths need to point to directories")
                return []
            }

            return [path]
        }

        switch manifest {
        case let .glob(pattern: pattern):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return globFiles(resolvedPath).map(FileElement.file)
        case let .folderReference(path: folderReferencePath):
            let resolvedPath = try generatorPaths.resolve(path: folderReferencePath)
            return folderReferences(resolvedPath).map(FileElement.folderReference)
        }
    }
}

extension TuistCore.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Project {
        let name = manifest.name

        let settings = try manifest.settings.map { try TuistCore.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map {
            try TuistCore.Target.from(manifest: $0,
                                      path: path,
                                      generatorPaths: generatorPaths)
        }

        let schemes = try manifest.schemes.map { try TuistCore.Scheme.from(manifest: $0, projectPath: path, generatorPaths: generatorPaths) }

        let additionalFiles = try manifest.additionalFiles.flatMap {
            try TuistCore.FileElement.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths)
        }

        let packages = try manifest.packages.map { package in
            try TuistCore.Package(manifest: package, generatorPaths: generatorPaths)
        }

        return Project(path: path,
                       name: name,
                       settings: settings ?? .default,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
                       packages: packages,
                       schemes: schemes,
                       additionalFiles: additionalFiles)
    }

    func adding(target: TuistCore.Target) -> TuistCore.Project {
        Project(path: path,
                name: name,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets + [target],
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }

    func replacing(fileName: String?) -> TuistCore.Project {
        Project(path: path,
                name: name,
                fileName: fileName,
                settings: settings,
                filesGroup: filesGroup,
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: additionalFiles)
    }
}

extension TuistCore.Target {
    // swiftlint:disable:next function_body_length
    static func from(manifest: ProjectDescription.Target,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Target {
        let name = manifest.name
        let platform = try TuistCore.Platform(manifest: manifest.platform, generatorPaths: generatorPaths)
        let product = try TuistCore.Product(manifest: manifest.product, generatorPaths: generatorPaths)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = try manifest.deploymentTarget.map { try TuistCore.DeploymentTarget(manifest: $0, generatorPaths: generatorPaths) }

        let dependencies = try manifest.dependencies.map { try TuistCore.Dependency(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = try TuistCore.InfoPlist(manifest: manifest.infoPlist, generatorPaths: generatorPaths)
        let entitlements = try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }

        let settings = try manifest.settings.map { try TuistCore.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let sources = try TuistCore.Target.sources(projectPath: path, sources: manifest.sources?.globs.map {
            let glob = try generatorPaths.resolve(path: $0.glob).pathString
            let excluding = try $0.excluding.map { try generatorPaths.resolve(path: $0).pathString }
            return (glob: glob, excluding: excluding, compilerFlags: $0.compilerFlags)
        } ?? [])

        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistCore.Target.isResource(path: path)
        }
        let resources = try (manifest.resources ?? []).flatMap {
            try TuistCore.FileElement.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths,
                                           includeFiles: resourceFilter)
        }

        let headers = try manifest.headers.map { try TuistCore.Headers(manifest: $0, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistCore.CoreDataModel(manifest: $0, generatorPaths: generatorPaths)
        }

        let actions = try manifest.actions.map { try TuistCore.TargetAction(manifest: $0, generatorPaths: generatorPaths) }
        let environment = manifest.environment

        return TuistCore.Target(name: name,
                                platform: platform,
                                product: product,
                                productName: productName,
                                bundleId: bundleId,
                                deploymentTarget: deploymentTarget,
                                infoPlist: infoPlist,
                                entitlements: entitlements,
                                settings: settings,
                                sources: sources,
                                resources: resources,
                                headers: headers,
                                coreDataModels: coreDataModels,
                                actions: actions,
                                environment: environment,
                                filesGroup: .group(name: "Project"),
                                dependencies: dependencies)
    }
}

extension TuistCore.Settings {
    typealias BuildConfigurationTuple = (TuistCore.BuildConfiguration, TuistCore.Configuration?)

    static func from(manifest: ProjectDescription.Settings, path _: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Settings {
        let base = try manifest.base.mapValues { try TuistCore.SettingValue(manifest: $0, generatorPaths: generatorPaths) }
        let configurations = try manifest.configurations
            .reduce([TuistCore.BuildConfiguration: TuistCore.Configuration?]()) { acc, val in
                var result = acc
                let variant = try TuistCore.BuildConfiguration(manifest: val, generatorPaths: generatorPaths)
                if let configuration = val.configuration {
                    result[variant] = try TuistCore.Configuration(manifest: configuration, generatorPaths: generatorPaths)
                }
                return result
            }
        let defaultSettings = try TuistCore.DefaultSettings(manifest: manifest.defaultSettings, generatorPaths: generatorPaths)
        return TuistCore.Settings(base: base,
                                  configurations: configurations,
                                  defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path _: AbsolutePath,
                                                generatorPaths: GeneratorPaths) throws -> BuildConfigurationTuple {
        let buildConfiguration = try TuistCore.BuildConfiguration(manifest: customConfiguration, generatorPaths: generatorPaths)
        let configuration = try customConfiguration.configuration.flatMap {
            try TuistCore.Configuration(manifest: $0, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}

extension TuistCore.Scheme {
    static func from(manifest: ProjectDescription.Scheme, projectPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction(manifest: $0, generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0, projectPath: projectPath, generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction(manifest: $0, generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction(manifest: $0, generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }

    static func from(manifest: ProjectDescription.Scheme, workspacePath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction(manifest: $0, generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0, projectPath: workspacePath, generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction(manifest: $0, generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction(manifest: $0, generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }
}

extension TuistCore.TestAction {
    static func from(manifest: ProjectDescription.TestAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestAction {
        let targets = try manifest.targets.map { try TuistCore.TestableTarget(manifest: $0, generatorPaths: generatorPaths) }
        let arguments = try manifest.arguments.map { try TuistCore.Arguments(manifest: $0, generatorPaths: generatorPaths) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let codeCoverageTargets = try manifest.codeCoverageTargets.map { TuistCore.TargetReference(projectPath: try resolveProjectPath(projectPath: $0.projectPath,
                                                                                                                                       defaultPath: projectPath,
                                                                                                                                       generatorPaths: generatorPaths),
                                                                                                   name: $0.targetName) }
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction(manifest: $0, generatorPaths: generatorPaths) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions)
    }
}

private func resolveProjectPath(projectPath: Path?, defaultPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> AbsolutePath {
    if let projectPath = projectPath { return try generatorPaths.resolve(path: projectPath) }
    return defaultPath
}
