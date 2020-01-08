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
        guard let tuistConfigPath = FileHandler.shared.locateDirectoryTraversingParents(from: path, path: Manifest.tuistConfig.fileName) else {
            return TuistCore.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistCore.TuistConfig.from(manifest: manifest, path: path)
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

extension TuistCore.TuistConfig {
    static func from(manifest: ProjectDescription.TuistConfig,
                     path: AbsolutePath) throws -> TuistCore.TuistConfig {
        let generationOptions = try manifest.generationOptions.map { try TuistCore.TuistConfig.GenerationOption.from(manifest: $0, path: path) }
        let compatibleXcodeVersions = TuistCore.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)

        return TuistCore.TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                                     generationOptions: generationOptions)
    }
}

extension TuistCore.TuistConfig.GenerationOption {
    static func from(manifest: ProjectDescription.TuistConfig.GenerationOptions,
                     path _: AbsolutePath) throws -> TuistCore.TuistConfig.GenerationOption {
        switch manifest {
        case let .xcodeProjectName(templateString):
            return .xcodeProjectName(templateString.description)
        }
    }
}

extension TuistCore.CompatibleXcodeVersions {
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistCore.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .list(versions):
            return .list(versions)
        }
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
            try TuistCore.Package.from(manifest: package, path: path, generatorPaths: generatorPaths)
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
        let platform = try TuistCore.Platform.from(manifest: manifest.platform)
        let product = TuistCore.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistCore.DeploymentTarget.from(manifest: $0) }

        let dependencies = try manifest.dependencies.map { try TuistCore.Dependency.from(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = try TuistCore.InfoPlist.from(manifest: manifest.infoPlist, path: path, generatorPaths: generatorPaths)
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

        let headers = try manifest.headers.map { try TuistCore.Headers.from(manifest: $0, path: path, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistCore.CoreDataModel.from(manifest: $0, path: path, generatorPaths: generatorPaths)
        }

        let actions = try manifest.actions.map { try TuistCore.TargetAction.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
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

extension TuistCore.InfoPlist {
    static func from(manifest: ProjectDescription.InfoPlist, path _: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: try generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(with:
                dictionary.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) })
        }
    }
}

extension TuistCore.InfoPlist.Value {
    static func from(manifest: ProjectDescription.InfoPlist.Value) -> TuistCore.InfoPlist.Value {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .boolean(value):
            return .boolean(value)
        case let .integer(value):
            return .integer(value)
        case let .array(value):
            return .array(value.map { TuistCore.InfoPlist.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistCore.InfoPlist.Value.from(manifest: $0) })
        }
    }
}

extension TuistCore.Settings {
    typealias BuildConfigurationTuple = (TuistCore.BuildConfiguration, TuistCore.Configuration?)

    static func from(manifest: ProjectDescription.Settings, path: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Settings {
        let base = manifest.base.mapValues(TuistCore.SettingValue.from)
        let configurations = try manifest.configurations
            .reduce([TuistCore.BuildConfiguration: TuistCore.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistCore.BuildConfiguration.from(manifest: val)
                result[variant] = try TuistCore.Configuration.from(manifest: val.configuration, path: path, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistCore.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistCore.Settings(base: base,
                                  configurations: configurations,
                                  defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path: AbsolutePath,
                                                generatorPaths: GeneratorPaths) throws -> BuildConfigurationTuple {
        let buildConfiguration = TuistCore.BuildConfiguration.from(manifest: customConfiguration)
        let configuration = try customConfiguration.configuration.flatMap {
            try TuistCore.Configuration.from(manifest: $0, path: path, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}

extension TuistCore.DefaultSettings {
    static func from(manifest: ProjectDescription.DefaultSettings) -> TuistCore.DefaultSettings {
        switch manifest {
        case .recommended:
            return .recommended
        case .essential:
            return .essential
        case .none:
            return .none
        }
    }
}

extension TuistCore.SettingValue {
    static func from(manifest: ProjectDescription.SettingValue) -> TuistCore.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}

extension TuistCore.Configuration {
    static func from(manifest: ProjectDescription.Configuration?,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Configuration? {
        guard let manifest = manifest else {
            return nil
        }
        let settings = manifest.settings.mapValues(TuistCore.SettingValue.from)
        let xcconfig = try manifest.xcconfig.flatMap { try generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistCore.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistCore.TargetAction.Order.from(manifest: manifest.order)
        let arguments = manifest.arguments
        let inputPaths = try manifest.inputPaths.map { try generatorPaths.resolve(path: $0) }
        let inputFileListPaths = try manifest.inputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let outputPaths = try manifest.outputPaths.map { try generatorPaths.resolve(path: $0) }
        let outputFileListPaths = try manifest.outputFileListPaths.map { try generatorPaths.resolve(path: $0) }
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        return TargetAction(name: name,
                            order: order,
                            tool: tool,
                            path: path,
                            arguments: arguments,
                            inputPaths: inputPaths,
                            inputFileListPaths: inputFileListPaths,
                            outputPaths: outputPaths,
                            outputFileListPaths: outputFileListPaths)
    }
}

extension TuistCore.TargetAction.Order {
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistCore.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}

extension TuistCore.CoreDataModel {
    static func from(manifest: ProjectDescription.CoreDataModel,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.CoreDataModel {
        let modelPath = try generatorPaths.resolve(path: manifest.path)
        if !FileHandler.shared.exists(modelPath) {
            throw GeneratorModelLoaderError.missingFile(modelPath)
        }
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistCore.Headers {
    static func from(manifest: ProjectDescription.Headers,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Headers {
        let `public` = try manifest.public?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let `private` = try manifest.private?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        let project = try manifest.project?.globs.flatMap {
            headerFiles(try generatorPaths.resolve(path: $0))
        } ?? []

        return Headers(public: `public`, private: `private`, project: project)
    }

    private static func headerFiles(_ path: AbsolutePath) -> [AbsolutePath] {
        FileHandler.shared.glob(AbsolutePath("/"), glob: String(path.pathString.dropFirst())).filter {
            if let `extension` = $0.extension, Headers.extensions.contains(".\(`extension`)") {
                return true
            }
            return false
        }
    }
}

extension TuistCore.Package {
    static func from(manifest: ProjectDescription.Package,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Package {
        switch manifest {
        case let .local(path: local):
            return .local(path: try generatorPaths.resolve(path: local))
        case let .remote(url: url, requirement: version):
            return .remote(url: url, requirement: .from(manifest: version))
        }
    }
}

extension TuistCore.Package.Requirement {
    static func from(manifest: ProjectDescription.Package.Requirement) -> TuistCore.Package.Requirement {
        switch manifest {
        case let .branch(branch):
            return .branch(branch)
        case let .exact(version):
            return .exact(version.description)
        case let .range(from, to):
            return .range(from: from.description, to: to.description)
        case let .revision(revision):
            return .revision(revision)
        case let .upToNextMajor(version):
            return .upToNextMajor(version.description)
        case let .upToNextMinor(version):
            return .upToNextMinor(version.description)
        }
    }
}

extension TuistCore.Dependency {
    static func from(manifest: ProjectDescription.TargetDependency, generatorPaths: GeneratorPaths) throws -> TuistCore.Dependency {
        switch manifest {
        case let .target(name):
            return .target(name: name)
        case let .project(target, projectPath):
            return .project(target: target, path: try generatorPaths.resolve(path: projectPath))
        case let .framework(frameworkPath):
            return .framework(path: try generatorPaths.resolve(path: frameworkPath))
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return .library(path: try generatorPaths.resolve(path: libraryPath),
                            publicHeaders: try generatorPaths.resolve(path: publicHeaders),
                            swiftModuleMap: try swiftModuleMap.map { try generatorPaths.resolve(path: $0) })
        case let .package(product):
            return .package(product: product)

        case let .sdk(name, status):
            return .sdk(name: name,
                        status: .from(manifest: status))
        case let .cocoapods(path):
            return .cocoapods(path: try generatorPaths.resolve(path: path))
        case let .xcFramework(path):
            return .xcFramework(path: try generatorPaths.resolve(path: path))
        }
    }
}

extension TuistCore.Scheme {
    static func from(manifest: ProjectDescription.Scheme, projectPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction.from(manifest: $0,
                                                                                        projectPath: projectPath,
                                                                                        generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0,
                                                                                     projectPath: projectPath,
                                                                                     generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction.from(manifest: $0,
                                                                                  projectPath: projectPath,
                                                                                  generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction.from(manifest: $0,
                                                                                              projectPath: projectPath,
                                                                                              generatorPaths: generatorPaths) }

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
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction.from(manifest: $0,
                                                                                        projectPath: workspacePath,
                                                                                        generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0,
                                                                                     projectPath: workspacePath,
                                                                                     generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction.from(manifest: $0,
                                                                                  projectPath: workspacePath,
                                                                                  generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction.from(manifest: $0,
                                                                                              projectPath: workspacePath,
                                                                                              generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }
}

extension TuistCore.BuildAction {
    static func from(manifest: ProjectDescription.BuildAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.BuildAction {
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                          projectPath: projectPath,
                                                                                          generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                            projectPath: projectPath,
                                                                                            generatorPaths: generatorPaths) }
        let targets: [TuistCore.TargetReference] = try manifest.targets.map {
            .init(projectPath: try resolveProjectPath(projectPath: $0.projectPath,
                                                      defaultPath: projectPath,
                                                      generatorPaths: generatorPaths),
                  name: $0.targetName)
        }
        return TuistCore.BuildAction(targets: targets, preActions: preActions, postActions: postActions)
    }
}

extension TuistCore.TestAction {
    static func from(manifest: ProjectDescription.TestAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestAction {
        let targets = try manifest.targets.map { try TuistCore.TestableTarget.from(manifest: $0,
                                                                                   projectPath: projectPath,
                                                                                   generatorPaths: generatorPaths) }
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let codeCoverageTargets = try manifest.codeCoverageTargets.map {
            TuistCore.TargetReference(projectPath: try resolveProjectPath(projectPath: $0.projectPath,
                                                                          defaultPath: projectPath,
                                                                          generatorPaths: generatorPaths),
                                      name: $0.targetName)
        }
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                          projectPath: projectPath,
                                                                                          generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                            projectPath: projectPath,
                                                                                            generatorPaths: generatorPaths) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions)
    }
}

extension TuistCore.TestableTarget {
    static func from(manifest: ProjectDescription.TestableTarget,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestableTarget {
        TestableTarget(target: TuistCore.TargetReference(projectPath: try resolveProjectPath(projectPath: manifest.target.projectPath,
                                                                                             defaultPath: projectPath,
                                                                                             generatorPaths: generatorPaths),
                                                         name: manifest.target.targetName),
                       skipped: manifest.isSkipped,
                       parallelizable: manifest.isParallelizable,
                       randomExecutionOrdering: manifest.isRandomExecutionOrdering)
    }
}

extension TuistCore.RunAction {
    static func from(manifest: ProjectDescription.RunAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.RunAction {
        let configurationName = manifest.configurationName
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }

        var executableResolved: TuistCore.TargetReference?
        if let executable = manifest.executable {
            executableResolved = TargetReference(projectPath: try resolveProjectPath(projectPath: executable.projectPath,
                                                                                     defaultPath: projectPath,
                                                                                     generatorPaths: generatorPaths),
                                                 name: executable.targetName)
        }

        return RunAction(configurationName: configurationName,
                         executable: executableResolved,
                         arguments: arguments)
    }
}

extension TuistCore.ArchiveAction {
    static func from(manifest: ProjectDescription.ArchiveAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.ArchiveAction {
        let configurationName = manifest.configurationName
        let revealArchiveInOrganizer = manifest.revealArchiveInOrganizer
        let customArchiveName = manifest.customArchiveName
        let preActions = try manifest.preActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                          projectPath: projectPath,
                                                                                          generatorPaths: generatorPaths) }
        let postActions = try manifest.postActions.map { try TuistCore.ExecutionAction.from(manifest: $0,
                                                                                            projectPath: projectPath,
                                                                                            generatorPaths: generatorPaths) }

        return TuistCore.ArchiveAction(configurationName: configurationName,
                                       revealArchiveInOrganizer: revealArchiveInOrganizer,
                                       customArchiveName: customArchiveName,
                                       preActions: preActions,
                                       postActions: postActions)
    }
}

extension TuistCore.ExecutionAction {
    static func from(manifest: ProjectDescription.ExecutionAction,
                     projectPath: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.ExecutionAction {
        let targetReference: TuistCore.TargetReference? = try manifest.target.map {
            .init(projectPath: try resolveProjectPath(projectPath: $0.projectPath,
                                                      defaultPath: projectPath,
                                                      generatorPaths: generatorPaths),
                  name: $0.targetName)
        }
        return ExecutionAction(title: manifest.title, scriptText: manifest.scriptText, target: targetReference)
    }
}

extension TuistCore.Arguments {
    static func from(manifest: ProjectDescription.Arguments) -> TuistCore.Arguments {
        Arguments(environment: manifest.environment,
                  launch: manifest.launch)
    }
}

extension TuistCore.BuildConfiguration {
    static func from(manifest: ProjectDescription.CustomConfiguration) -> TuistCore.BuildConfiguration {
        let variant: TuistCore.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return TuistCore.BuildConfiguration(name: manifest.name, variant: variant)
    }
}

extension TuistCore.Product {
    static func from(manifest: ProjectDescription.Product) -> TuistCore.Product {
        switch manifest {
        case .app:
            return .app
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .framework:
            return .framework
        case .staticFramework:
            return .staticFramework
        case .unitTests:
            return .unitTests
        case .uiTests:
            return .uiTests
        case .bundle:
            return .bundle
        case .appExtension:
            return .appExtension
        case .stickerPackExtension:
            return .stickerPackExtension
        case .watch2App:
            return .watch2App
        case .watch2Extension:
            return .watch2Extension
        }
    }
}

extension TuistCore.Platform {
    static func from(manifest: ProjectDescription.Platform) throws -> TuistCore.Platform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        }
    }
}

extension TuistCore.SDKStatus {
    static func from(manifest: ProjectDescription.SDKStatus) -> TuistCore.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}

extension TuistCore.DeploymentTarget {
    static func from(manifest: ProjectDescription.DeploymentTarget) -> TuistCore.DeploymentTarget {
        switch manifest {
        case let .iOS(version, devices):
            return .iOS(version, DeploymentDevice(rawValue: devices.rawValue))
        case let .macOS(version):
            return .macOS(version)
        }
    }
}

private func resolveProjectPath(projectPath: Path?, defaultPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> AbsolutePath {
    if let projectPath = projectPath { return try generatorPaths.resolve(path: projectPath) }
    return defaultPath
}
