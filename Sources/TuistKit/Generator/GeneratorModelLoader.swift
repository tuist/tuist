import Basic
import Foundation
import ProjectDescription
import TuistSupport
import TuistGenerator

enum GeneratorModelLoaderError: Error, Equatable, FatalError {
    case featureNotYetSupported(String)
    case missingFile(AbsolutePath)
    var type: ErrorType {
        switch self {
        case .featureNotYetSupported:
            return .abort
        case .missingFile:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .featureNotYetSupported(details):
            return "\(details) is not yet supported"
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
    func loadProject(at path: AbsolutePath) throws -> TuistGenerator.Project {
        let manifest = try manifestLoader.loadProject(at: path)
        let tuistConfig = try loadTuistConfig(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)

        try manifestLinter.lint(project: manifest)
            .printAndThrowIfNeeded()

        let project = try TuistGenerator.Project.from(manifest: manifest,
                                                      path: path,
                                                      generatorPaths: generatorPaths)

        return try enriched(model: project, with: tuistConfig)
    }

    func loadWorkspace(at path: AbsolutePath) throws -> TuistGenerator.Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let workspace = try TuistGenerator.Workspace.from(manifest: manifest,
                                                          path: path,
                                                          generatorPaths: generatorPaths,
                                                          manifestLoader: manifestLoader)
        return workspace
    }

    /// Load a TusitConfig model at the specified path
    ///
    /// - Parameter path: The absolute path for the tuistconfig model to load
    /// - Returns: The tuistconfig loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing tuistconfig)
    func loadTuistConfig(at path: AbsolutePath) throws -> TuistGenerator.TuistConfig {
        guard let tuistConfigPath = locateDirectoryTraversingParents(from: path, path: "TuistConfig.swift") else {
            return TuistGenerator.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistGenerator.TuistConfig.from(manifest: manifest, path: path)
    }

    /// Traverses the parent directories until the given path is found.
    ///
    /// - Parameters:
    ///   - from: A path to a directory from which search the TuistConfig.swift.
    /// - Returns: The found path.
    fileprivate func locateDirectoryTraversingParents(from: AbsolutePath, path: String) -> AbsolutePath? {
        let tuistConfigPath = from.appending(component: path)

        if FileHandler.shared.exists(tuistConfigPath) {
            return tuistConfigPath
        } else if from == AbsolutePath("/") {
            return nil
        } else {
            return locateDirectoryTraversingParents(from: from.parentDirectory, path: path)
        }
    }

    private func enriched(model: TuistGenerator.Project,
                          with config: TuistGenerator.TuistConfig) throws -> TuistGenerator.Project {
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

    private func xcodeFileNameOverride(from config: TuistGenerator.TuistConfig,
                                       for model: TuistGenerator.Project) -> String? {
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

extension TuistGenerator.TuistConfig {
    static func from(manifest: ProjectDescription.TuistConfig,
                     path: AbsolutePath) throws -> TuistGenerator.TuistConfig {
        let generationOptions = try manifest.generationOptions.map { try TuistGenerator.TuistConfig.GenerationOption.from(manifest: $0, path: path) }
        let compatibleXcodeVersions = TuistGenerator.CompatibleXcodeVersions.from(manifest: manifest.compatibleXcodeVersions)

        return TuistGenerator.TuistConfig(compatibleXcodeVersions: compatibleXcodeVersions,
                                          generationOptions: generationOptions)
    }
}

extension TuistGenerator.TuistConfig.GenerationOption {
    static func from(manifest: ProjectDescription.TuistConfig.GenerationOptions,
                     path _: AbsolutePath) throws -> TuistGenerator.TuistConfig.GenerationOption {
        switch manifest {
        case .generateManifest:
            return .generateManifest
        case let .xcodeProjectName(templateString):
            return .xcodeProjectName(templateString.description)
        }
    }
}

extension TuistGenerator.CompatibleXcodeVersions {
    static func from(manifest: ProjectDescription.CompatibleXcodeVersions) -> TuistGenerator.CompatibleXcodeVersions {
        switch manifest {
        case .all:
            return .all
        case let .list(versions):
            return .list(versions)
        }
    }
}

extension TuistGenerator.Workspace {
    static func from(manifest: ProjectDescription.Workspace,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     manifestLoader: GraphManifestLoading) throws -> TuistGenerator.Workspace {
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
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            generatorPaths: generatorPaths)
        }

        return TuistGenerator.Workspace(name: manifest.name,
                                        projects: manifest.projects.flatMap(globProjects),
                                        additionalFiles: additionalFiles)
    }
}

extension TuistGenerator.FileElement {
    static func from(manifest: ProjectDescription.FileElement,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths,
                     includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }) -> [TuistGenerator.FileElement] {
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

extension TuistGenerator.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistGenerator.Project {
        let name = manifest.name
        let settings = manifest.settings.map { TuistGenerator.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let targets = try manifest.targets.map {
            try TuistGenerator.Target.from(manifest: $0,
                                           path: path,
                                           generatorPaths: generatorPaths)
        }

        let schemes = manifest.schemes.map { TuistGenerator.Scheme.from(manifest: $0) }

        let additionalFiles = manifest.additionalFiles.flatMap {
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            generatorPaths: generatorPaths)
        }

        let packages = manifest.packages.map { package in
            TuistGenerator.Package.from(manifest: package, path: path, generatorPaths: generatorPaths)
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

    func adding(target: TuistGenerator.Target) -> TuistGenerator.Project {
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

    func replacing(fileName: String?) -> TuistGenerator.Project {
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

extension TuistGenerator.Target {
    static func from(manifest: ProjectDescription.Target,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistGenerator.Target {
        let name = manifest.name
        let platform = try TuistGenerator.Platform.from(manifest: manifest.platform)
        let product = TuistGenerator.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName
        let deploymentTarget = manifest.deploymentTarget.map { TuistGenerator.DeploymentTarget.from(manifest: $0) }

        let dependencies = manifest.dependencies.map { TuistGenerator.Dependency.from(manifest: $0, generatorPaths: generatorPaths) }

        let infoPlist = TuistGenerator.InfoPlist.from(manifest: manifest.infoPlist, path: path, generatorPaths: generatorPaths)
        let entitlements = manifest.entitlements.map { generatorPaths.resolve(path: $0) }

        let settings = manifest.settings.map { TuistGenerator.Settings.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let sources = try TuistGenerator.Target.sources(projectPath: path, sources: manifest.sources?.globs.map {
            (glob: generatorPaths.resolve(path: $0.glob).pathString, compilerFlags: $0.compilerFlags)
        } ?? [])

        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistGenerator.Target.isResource(path: path)
        }
        let resources = (manifest.resources ?? []).flatMap {
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            generatorPaths: generatorPaths,
                                            includeFiles: resourceFilter)
        }

        let headers = manifest.headers.map { TuistGenerator.Headers.from(manifest: $0, path: path, generatorPaths: generatorPaths) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistGenerator.CoreDataModel.from(manifest: $0, path: path, generatorPaths: generatorPaths)
        }

        let actions = manifest.actions.map { TuistGenerator.TargetAction.from(manifest: $0, path: path, generatorPaths: generatorPaths) }
        let environment = manifest.environment

        return TuistGenerator.Target(name: name,
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

extension TuistGenerator.InfoPlist {
    static func from(manifest: ProjectDescription.InfoPlist, path _: AbsolutePath, generatorPaths: GeneratorPaths) -> TuistGenerator.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: generatorPaths.resolve(path: infoplistPath))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGenerator.InfoPlist.Value.from(manifest: $0) }
            )
        case let .extendingDefault(dictionary):
            return .extendingDefault(with:
                dictionary.mapValues { TuistGenerator.InfoPlist.Value.from(manifest: $0) })
        }
    }
}

extension TuistGenerator.InfoPlist.Value {
    static func from(manifest: ProjectDescription.InfoPlist.Value) -> TuistGenerator.InfoPlist.Value {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .boolean(value):
            return .boolean(value)
        case let .integer(value):
            return .integer(value)
        case let .array(value):
            return .array(value.map { TuistGenerator.InfoPlist.Value.from(manifest: $0) })
        case let .dictionary(value):
            return .dictionary(value.mapValues { TuistGenerator.InfoPlist.Value.from(manifest: $0) })
        }
    }
}

extension TuistGenerator.Settings {
    typealias BuildConfigurationTuple = (TuistGenerator.BuildConfiguration, TuistGenerator.Configuration?)

    static func from(manifest: ProjectDescription.Settings, path: AbsolutePath, generatorPaths: GeneratorPaths) -> TuistGenerator.Settings {
        let base = manifest.base.mapValues(TuistGenerator.SettingValue.from)
        let configurations = manifest.configurations
            .reduce([TuistGenerator.BuildConfiguration: TuistGenerator.Configuration?]()) { acc, val in
                var result = acc
                let variant = TuistGenerator.BuildConfiguration.from(manifest: val)
                result[variant] = TuistGenerator.Configuration.from(manifest: val.configuration, path: path, generatorPaths: generatorPaths)
                return result
            }
        let defaultSettings = TuistGenerator.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistGenerator.Settings(base: base,
                                       configurations: configurations,
                                       defaultSettings: defaultSettings)
    }

    private static func buildConfigurationTuple(from customConfiguration: CustomConfiguration,
                                                path: AbsolutePath,
                                                generatorPaths: GeneratorPaths) -> BuildConfigurationTuple {
        let buildConfiguration = TuistGenerator.BuildConfiguration.from(manifest: customConfiguration)
        let configuration = customConfiguration.configuration.flatMap {
            TuistGenerator.Configuration.from(manifest: $0, path: path, generatorPaths: generatorPaths)
        }
        return (buildConfiguration, configuration)
    }
}

extension TuistGenerator.DefaultSettings {
    static func from(manifest: ProjectDescription.DefaultSettings) -> TuistGenerator.DefaultSettings {
        switch manifest {
        case .recommended:
            return .recommended
        case .essential:
            return .essential
        }
    }
}

extension TuistGenerator.SettingValue {
    static func from(manifest: ProjectDescription.SettingValue) -> TuistGenerator.SettingValue {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .array(value):
            return .array(value)
        }
    }
}

extension TuistGenerator.Configuration {
    static func from(manifest: ProjectDescription.Configuration?,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) -> TuistGenerator.Configuration? {
        guard let manifest = manifest else {
            return nil
        }
        let settings = manifest.settings.mapValues(TuistGenerator.SettingValue.from)
        let xcconfig = manifest.xcconfig.flatMap { generatorPaths.resolve(path: $0) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistGenerator.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction,
                     path: AbsolutePath,
                     generatorPaths: GeneratorPaths) -> TuistGenerator.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistGenerator.TargetAction.Order.from(manifest: manifest.order)
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

extension TuistGenerator.TargetAction.Order {
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistGenerator.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}

extension TuistGenerator.CoreDataModel {
    static func from(manifest: ProjectDescription.CoreDataModel,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) throws -> TuistGenerator.CoreDataModel {
        let modelPath = generatorPaths.resolve(path: manifest.path)
        if !FileHandler.shared.exists(modelPath) {
            throw GeneratorModelLoaderError.missingFile(modelPath)
        }
        let versions = FileHandler.shared.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistGenerator.Headers {
    static func from(manifest: ProjectDescription.Headers,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) -> TuistGenerator.Headers {
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

extension TuistGenerator.Package {
    static func from(manifest: ProjectDescription.Package,
                     path _: AbsolutePath,
                     generatorPaths: GeneratorPaths) -> TuistGenerator.Package {
        switch manifest {
        case let .local(path: local):
            return .local(path: generatorPaths.resolve(path: local))
        case let .remote(url: url, requirement: version):
            return .remote(url: url, requirement: .from(manifest: version))
        }
    }
}

extension TuistGenerator.Package.Requirement {
    static func from(manifest: ProjectDescription.Package.Requirement) -> TuistGenerator.Package.Requirement {
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

extension TuistGenerator.Dependency {
    static func from(manifest: ProjectDescription.TargetDependency, generatorPaths: GeneratorPaths) -> TuistGenerator.Dependency {
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

extension TuistGenerator.Scheme {
    static func from(manifest: ProjectDescription.Scheme) -> TuistGenerator.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = manifest.buildAction.map { TuistGenerator.BuildAction.from(manifest: $0) }
        let testAction = manifest.testAction.map { TuistGenerator.TestAction.from(manifest: $0) }
        let runAction = manifest.runAction.map { TuistGenerator.RunAction.from(manifest: $0) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }
}

extension TuistGenerator.BuildAction {
    static func from(manifest: ProjectDescription.BuildAction) -> TuistGenerator.BuildAction {
        let preActions = manifest.preActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }
        let postActions = manifest.postActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }

        return BuildAction(targets: manifest.targets, preActions: preActions, postActions: postActions)
    }
}

extension TuistGenerator.TestAction {
    static func from(manifest: ProjectDescription.TestAction) -> TuistGenerator.TestAction {
        let targets = manifest.targets
        let arguments = manifest.arguments.map { TuistGenerator.Arguments.from(manifest: $0) }
        let configurationName = manifest.configurationName
        let coverage = manifest.coverage
        let preActions = manifest.preActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }
        let postActions = manifest.postActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          configurationName: configurationName,
                          coverage: coverage,
                          preActions: preActions,
                          postActions: postActions)
    }
}

extension TuistGenerator.RunAction {
    static func from(manifest: ProjectDescription.RunAction) -> TuistGenerator.RunAction {
        let configurationName = manifest.configurationName
        let executable = manifest.executable
        let arguments = manifest.arguments.map { TuistGenerator.Arguments.from(manifest: $0) }

        return RunAction(configurationName: configurationName,
                         executable: executable,
                         arguments: arguments)
    }
}

extension TuistGenerator.ExecutionAction {
    static func from(manifest: ProjectDescription.ExecutionAction) -> TuistGenerator.ExecutionAction {
        return ExecutionAction(title: manifest.title, scriptText: manifest.scriptText, target: manifest.target)
    }
}

extension TuistGenerator.Arguments {
    static func from(manifest: ProjectDescription.Arguments) -> TuistGenerator.Arguments {
        return Arguments(environment: manifest.environment,
                         launch: manifest.launch)
    }
}

extension TuistGenerator.BuildConfiguration {
    static func from(manifest: ProjectDescription.CustomConfiguration) -> TuistGenerator.BuildConfiguration {
        let variant: TuistGenerator.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return TuistGenerator.BuildConfiguration(name: manifest.name, variant: variant)
    }
}

extension TuistGenerator.Product {
    static func from(manifest: ProjectDescription.Product) -> TuistGenerator.Product {
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
        }
    }
}

extension TuistGenerator.Platform {
    static func from(manifest: ProjectDescription.Platform) throws -> TuistGenerator.Platform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            throw GeneratorModelLoaderError.featureNotYetSupported("watchOS platform")
        }
    }
}

extension TuistGenerator.SDKStatus {
    static func from(manifest: ProjectDescription.SDKStatus) -> TuistGenerator.SDKStatus {
        switch manifest {
        case .required:
            return .required
        case .optional:
            return .optional
        }
    }
}

extension TuistGenerator.DeploymentTarget {
    static func from(manifest: ProjectDescription.DeploymentTarget) -> TuistGenerator.DeploymentTarget {
        switch manifest {
        case let .iOS(version, devices):
            return .iOS(version, DeploymentDevice(rawValue: devices.rawValue))
        case let .macOS(version):
            return .macOS(version)
        }
    }
}
