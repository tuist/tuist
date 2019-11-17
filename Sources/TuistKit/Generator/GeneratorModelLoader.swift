import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistGenerator
import TuistSupport

enum GeneratorModelLoaderError: Error, Equatable, FatalError {
    case missingFile(AbsolutePath)
    var type: ErrorType {
        switch self {
        case .missingFile:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .missingFile(path):
            return "Couldn't find file at path '\(path.pathString)'"
        }
    }
}

class GeneratorModelLoader: GeneratorModelLoading {
    private let manifestLoader: GraphManifestLoading
    private let manifestTargetGenerator: ManifestTargetGenerating?
    private let manifestLinter: ManifestLinting

    init(manifestLoader: GraphManifestLoading,
         manifestLinter: ManifestLinting,
         manifestTargetGenerator: ManifestTargetGenerating? = nil) {
        self.manifestLoader = manifestLoader
        self.manifestLinter = manifestLinter
        self.manifestTargetGenerator = manifestTargetGenerator
    }

    /// Load a Project model at the specified path
    ///
    /// - Parameters:
    ///   - path: The absolute path for the project model to load.
    /// - Returns: The Project loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing project)
    func loadProject(at path: AbsolutePath) throws -> TuistCore.Project {
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

    func loadWorkspace(at path: AbsolutePath) throws -> TuistCore.Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try TuistCore.Workspace.from(manifest: manifest,
                                                     path: path,
                                                     generatorPaths: generatorPaths,
                                                     manifestLoader: manifestLoader)
        return workspace
    }

    func loadTuistConfig(at path: AbsolutePath) throws -> TuistCore.TuistConfig {
        guard let tuistConfigPath = FileHandler.shared.locateDirectoryTraversingParents(from: path, path: Manifest.tuistConfig.fileName) else {
            return TuistCore.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistCore.TuistConfig.from(manifest: manifest, path: path)
    }

    private func enriched(model: TuistCore.Project,
                          with config: TuistCore.TuistConfig) throws -> TuistCore.Project {
        var enrichedModel = model

        // Manifest target
        if let manifestTargetGenerator = manifestTargetGenerator, config.generationOptions.contains(.generateManifest) {
            let manifestTarget = try manifestTargetGenerator.generateManifestTarget(for: enrichedModel.name,
                                                                                    at: enrichedModel.path)
            enrichedModel = enrichedModel.adding(target: manifestTarget)
        }

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
            default:
                return nil
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
        case .generateManifest:
            return .generateManifest
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
                     manifestLoader: GraphManifestLoading) throws -> TuistCore.Workspace {
        func globProjects(_ path: Path) -> [AbsolutePath] {
            let resolvedPath = generatorPaths.resolve(path: path)
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

        let additionalFiles = manifest.additionalFiles.flatMap {
            TuistCore.FileElement.from(manifest: $0,
                                       path: path,
                                       generatorPaths: generatorPaths)
        }

        return TuistCore.Workspace(name: manifest.name,
                                   projects: manifest.projects.flatMap(globProjects),
                                   additionalFiles: additionalFiles)
    }
}

extension TuistCore.FileElement {
    static func from(manifest: ProjectDescription.FileElement,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }) -> [TuistCore.FileElement] {
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
            let resolvedPath = generatorPaths.resolve(path: pattern)
            return globFiles(resolvedPath).map(FileElement.file)
        case let .folderReference(path: folderReferencePath):
            let resolvedPath = generatorPaths.resolve(path: folderReferencePath)
            return folderReferences(resolvedPath).map(FileElement.folderReference)
        }
    }
}

extension TuistCore.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Project {
        let name = manifest.name
        let settings = manifest.settings.map { TuistCore.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map {
            try TuistCore.Target.from(manifest: $0,
                                      path: path,
                                      generatorPaths: generatorPaths)
        }

        let schemes = manifest.schemes.map { TuistCore.Scheme.from(manifest: $0) }

        let additionalFiles = manifest.additionalFiles.flatMap {
            TuistCore.FileElement.from(manifest: $0,
                                       path: path,
                                       generatorPaths: generatorPaths)
        }

        let packages = manifest.packages.map { package in
            TuistCore.Package.from(manifest: package, path: path, generatorPaths: generatorPaths)
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
        return Project(path: path,
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
        return Project(path: path,
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
    static func from(manifest: ProjectDescription.Target,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Target {
        let name = manifest.name
        let platform = try TuistCore.Platform.from(manifest: manifest.platform)
        let product = TuistCore.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistCore.DeploymentTarget.from(manifest: $0) }

        let dependencies = manifest.dependencies.map { TuistCore.Dependency.from(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = TuistCore.InfoPlist.from(manifest: manifest.infoPlist, path: path, generatorPaths: generatorPaths)
        let entitlements = manifest.entitlements.map { generatorPaths.resolve(path: $0) }

        let settings = manifest.settings.map { TuistCore.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let sources = try TuistCore.Target.sources(projectPath: path, sources: manifest.sources?.globs.map {
            (glob: generatorPaths.resolve(path: $0.glob).pathString, compilerFlags: $0.compilerFlags)
        } ?? [])

        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistCore.Target.isResource(path: path)
        }
        let resources = (manifest.resources ?? []).flatMap {
            TuistCore.FileElement.from(manifest: $0,
                                       path: path,
                                       generatorPaths: generatorPaths,
                                       includeFiles: resourceFilter)
        }

        let headers = manifest.headers.map { TuistCore.Headers.from(manifest: $0, path: path, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistCore.CoreDataModel.from(manifest: $0, path: path, generatorPaths: generatorPaths)
        }

        let actions = manifest.actions.map { TuistCore.TargetAction.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
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
    static func from(manifest: ProjectDescription.InfoPlist, path _: AbsolutePath, generatorPaths: GeneratorPaths) -> TuistCore.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: generatorPaths.resolve(path: infoplistPath))
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

    static func from(manifest: ProjectDescription.Settings, path: AbsolutePath, generatorPaths: GeneratorPaths) -> TuistCore.Settings {
        let base = manifest.base.mapValues(TuistCore.SettingValue.from)
        let configurations = manifest.configurations
            .reduce([TuistCore.BuildConfiguration: TuistCore.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistCore.BuildConfiguration.from(manifest: val)
                result[variant] = TuistCore.Configuration.from(manifest: val.configuration, path: path, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistCore.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistCore.Settings(base: base,
                                  configurations: configurations,
                                  defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path: AbsolutePath,
                                                generatorPaths: GeneratorPaths) -> BuildConfigurationTuple {
        let buildConfiguration = TuistCore.BuildConfiguration.from(manifest: customConfiguration)
        let configuration = customConfiguration.configuration.flatMap {
            TuistCore.Configuration.from(manifest: $0, path: path, generatorPaths: generatorPaths)
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
                     generatorPaths: GeneratorPaths) -> TuistCore.Configuration? {
        guard let manifest = manifest else {
            return nil
        }
        let settings = manifest.settings.mapValues(TuistCore.SettingValue.from)
        let xcconfig = manifest.xcconfig.flatMap { generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistCore.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) -> TuistCore.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistCore.TargetAction.Order.from(manifest: manifest.order)
        let arguments = manifest.arguments
        let inputPaths = manifest.inputPaths.map { generatorPaths.resolve(path: $0) }
        let inputFileListPaths = manifest.inputFileListPaths.map { generatorPaths.resolve(path: $0) }
        let outputPaths = manifest.outputPaths.map { generatorPaths.resolve(path: $0) }
        let outputFileListPaths = manifest.outputFileListPaths.map { generatorPaths.resolve(path: $0) }
        let path = manifest.path.map { generatorPaths.resolve(path: $0) }
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
        let modelPath = generatorPaths.resolve(path: manifest.path)
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
                     generatorPaths: GeneratorPaths) -> TuistCore.Headers {
        let `public` = manifest.public?.globs.flatMap {
            headerFiles(generatorPaths.resolve(path: $0))
        } ?? []

        let `private` = manifest.private?.globs.flatMap {
            headerFiles(generatorPaths.resolve(path: $0))
        } ?? []

        let project = manifest.project?.globs.flatMap {
            headerFiles(generatorPaths.resolve(path: $0))
        } ?? []

        return Headers(public: `public`, private: `private`, project: project)
    }

    private static func headerFiles(_ path: AbsolutePath) -> [AbsolutePath] {
        return FileHandler.shared.glob(AbsolutePath("/"), glob: String(path.pathString.dropFirst())).filter {
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
                     generatorPaths: GeneratorPaths) -> TuistCore.Package {
        switch manifest {
        case let .local(path: local):
            return .local(path: generatorPaths.resolve(path: local))
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
    static func from(manifest: ProjectDescription.TargetDependency, generatorPaths: GeneratorPaths) -> TuistCore.Dependency {
        switch manifest {
        case let .target(name):
            return .target(name: name)
        case let .project(target, projectPath):
            return .project(target: target, path: generatorPaths.resolve(path: projectPath))
        case let .framework(frameworkPath):
            return .framework(path: generatorPaths.resolve(path: frameworkPath))
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return .library(path: generatorPaths.resolve(path: libraryPath),
                            publicHeaders: generatorPaths.resolve(path: publicHeaders),
                            swiftModuleMap: swiftModuleMap.map { generatorPaths.resolve(path: $0) })
        case let .package(product):
            return .package(product: product)

        case let .sdk(name, status):
            return .sdk(name: name,
                        status: .from(manifest: status))
        case let .cocoapods(path):
            return .cocoapods(path: generatorPaths.resolve(path: path))
        }
    }
}

extension TuistCore.Scheme {
    static func from(manifest: ProjectDescription.Scheme) -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = manifest.buildAction.map { TuistCore.BuildAction.from(manifest: $0) }
        let testAction = manifest.testAction.map { TuistCore.TestAction.from(manifest: $0) }
        let runAction = manifest.runAction.map { TuistCore.RunAction.from(manifest: $0) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }
}

extension TuistCore.BuildAction {
    static func from(manifest: ProjectDescription.BuildAction) -> TuistCore.BuildAction {
        let preActions = manifest.preActions.map { TuistCore.ExecutionAction.from(manifest: $0) }
        let postActions = manifest.postActions.map { TuistCore.ExecutionAction.from(manifest: $0) }

        return BuildAction(targets: manifest.targets, preActions: preActions, postActions: postActions)
    }
}

extension TuistCore.TestAction {
    static func from(manifest: ProjectDescription.TestAction) -> TuistCore.TestAction {
        let targets = manifest.targets
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let codeCoverageTargets = manifest.codeCoverageTargets
        let preActions = manifest.preActions.map { TuistCore.ExecutionAction.from(manifest: $0) }
        let postActions = manifest.postActions.map { TuistCore.ExecutionAction.from(manifest: $0) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          codeCoverageTargets: codeCoverageTargets,
                          preActions: preActions,
                          postActions: postActions)
    }
}

extension TuistCore.RunAction {
    static func from(manifest: ProjectDescription.RunAction) -> TuistCore.RunAction {
        let configurationName = manifest.configurationName
        let executable = manifest.executable
        let arguments = manifest.arguments.map { TuistCore.Arguments.from(manifest: $0) }

        return RunAction(configurationName: configurationName,
                         executable: executable,
                         arguments: arguments)
    }
}

extension TuistCore.ExecutionAction {
    static func from(manifest: ProjectDescription.ExecutionAction) -> TuistCore.ExecutionAction {
        return ExecutionAction(title: manifest.title, scriptText: manifest.scriptText, target: manifest.target)
    }
}

extension TuistCore.Arguments {
    static func from(manifest: ProjectDescription.Arguments) -> TuistCore.Arguments {
        return Arguments(environment: manifest.environment,
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
