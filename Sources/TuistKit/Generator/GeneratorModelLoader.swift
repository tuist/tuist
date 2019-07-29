import Basic
import Foundation
import ProjectDescription
import TuistCore
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
    private let fileHandler: FileHandling
    private let manifestLoader: GraphManifestLoading
    private let manifestTargetGenerator: ManifestTargetGenerating?
    private let printer: Printing

    init(fileHandler: FileHandling,
         manifestLoader: GraphManifestLoading,
         manifestTargetGenerator: ManifestTargetGenerating? = nil,
         printer: Printing = Printer()) {
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
        self.manifestTargetGenerator = manifestTargetGenerator
        self.printer = printer
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
        
        let project = try TuistGenerator.Project.from(manifest: manifest,
                                                      path: path,
                                                      fileHandler: fileHandler,
                                                      printer: printer,
                                                      tuistConfig: tuistConfig)
        

        if let manifestTargetGenerator = manifestTargetGenerator, tuistConfig.generationOptions.contains(.generateManifest) {
            let manifestTarget = try manifestTargetGenerator.generateManifestTarget(for: project.name,
                                                                                    at: path)
            return project.adding(target: manifestTarget)

        } else {
            return project
        }
    }

    func loadWorkspace(at path: AbsolutePath) throws -> TuistGenerator.Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let workspace = try TuistGenerator.Workspace.from(manifest: manifest,
                                                          path: path,
                                                          fileHandler: fileHandler,
                                                          manifestLoader: manifestLoader,
                                                          printer: printer)
        return workspace
    }

    /// Load a TusitConfig model at the specified path
    ///
    /// - Parameter path: The absolute path for the tuistconfig model to load
    /// - Returns: The tuistconfig loaded from the specified path
    /// - Throws: Error encountered during the loading process (e.g. Missing tuistconfig)
    func loadTuistConfig(at path: AbsolutePath) throws -> TuistGenerator.TuistConfig {
        guard let tuistConfigPath = locateDirectoryTraversingParents(from: path, path: "TuistConfig.swift", fileHandler: fileHandler) else {
            return TuistGenerator.TuistConfig.default
        }

        let manifest = try manifestLoader.loadTuistConfig(at: tuistConfigPath.parentDirectory)
        return try TuistGenerator.TuistConfig.from(manifest: manifest, path: path)
    }

    /// Traverses the parent directories until the given path is found.
    ///
    /// - Parameters:
    ///   - from: A path to a directory from which search the TuistConfig.swift.
    ///   - fileHandler: An instance to interact with the file system.
    /// - Returns: The found path.
    fileprivate func locateDirectoryTraversingParents(from: AbsolutePath, path: String, fileHandler: FileHandling) -> AbsolutePath? {
        let tuistConfigPath = from.appending(component: path)

        if fileHandler.exists(tuistConfigPath) {
            return tuistConfigPath
        } else if from == AbsolutePath("/") {
            return nil
        } else {
            return locateDirectoryTraversingParents(from: from.parentDirectory, path: path, fileHandler: fileHandler)
        }
    }
}

extension TuistGenerator.TuistConfig {
    static func from(manifest: ProjectDescription.TuistConfig,
                     path: AbsolutePath) throws -> TuistGenerator.TuistConfig {
        let generationOptions = try manifest.generationOptions.map { try TuistGenerator.TuistConfig.GenerationOption.from(manifest: $0, path: path) }
        return TuistGenerator.TuistConfig(generationOptions: generationOptions)
    }
}

extension TuistGenerator.TuistConfig.GenerationOption {
    static func from(manifest: ProjectDescription.TuistConfig.GenerationOption,
                     path _: AbsolutePath) throws -> TuistGenerator.TuistConfig.GenerationOption {
        switch manifest {
        case .generateManifest:
            return .generateManifest
        case let .suffixProjectNames(suffixRaw):
            return .suffixProjectNames(with: suffixRaw)
        case let .prefixProjectNames(prefixRaw):
            return .prefixProjectNames(with: prefixRaw)
        }
    }
}

extension TuistGenerator.Workspace {
    static func from(manifest: ProjectDescription.Workspace,
                     path: AbsolutePath,
                     fileHandler: FileHandling,
                     manifestLoader: GraphManifestLoading,
                     printer: Printing) throws -> TuistGenerator.Workspace {
        func globProjects(_ string: String) -> [AbsolutePath] {
            let projects = fileHandler.glob(path, glob: string)
                .lazy
                .filter(fileHandler.isFolder)
                .filter {
                    manifestLoader.manifests(at: $0).contains(.project)
                }

            if projects.isEmpty {
                printer.print(warning: "No projects found at: \(string)")
            }

            return Array(projects)
        }

        let additionalFiles = manifest.additionalFiles.flatMap {
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            fileHandler: fileHandler,
                                            printer: printer)
        }

        return TuistGenerator.Workspace(name: manifest.name,
                                        projects: manifest.projects.flatMap(globProjects),
                                        additionalFiles: additionalFiles)
    }
}

extension TuistGenerator.FileElement {
    static func from(manifest: ProjectDescription.FileElement,
                     path: AbsolutePath,
                     fileHandler: FileHandling,
                     printer: Printing,
                     includeFiles: @escaping (AbsolutePath) -> Bool = { _ in true }) -> [TuistGenerator.FileElement] {
        func globFiles(_ string: String) -> [AbsolutePath] {
            let files = fileHandler.glob(path, glob: string)
                .filter(includeFiles)

            if files.isEmpty {
                if fileHandler.isFolder(path.appending(RelativePath(string))) {
                    printer.print(warning: "'\(string)' is a directory, try using: '\(string)/**' to list its files")
                } else {
                    printer.print(warning: "No files found at: \(string)")
                }
            }

            return files
        }

        func folderReferences(_ relativePath: String) -> [AbsolutePath] {
            let folderReferencePath = path.appending(RelativePath(relativePath))

            guard fileHandler.exists(folderReferencePath) else {
                printer.print(warning: "\(relativePath) does not exist")
                return []
            }

            guard fileHandler.isFolder(folderReferencePath) else {
                printer.print(warning: "\(relativePath) is not a directory - folder reference paths need to point to directories")
                return []
            }

            return [folderReferencePath]
        }

        switch manifest {
        case let .glob(pattern: pattern):
            return globFiles(pattern).map(FileElement.file)
        case let .folderReference(path: folderReferencePath):
            return folderReferences(folderReferencePath).map(FileElement.folderReference)
        }
    }
}

extension TuistGenerator.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     fileHandler: FileHandling,
                     printer: Printing,
                     tuistConfig: TuistGenerator.TuistConfig) throws -> TuistGenerator.Project {
        let name = manifest.name
        let settings = manifest.settings.map { TuistGenerator.Settings.from(manifest: $0, path: path) }
        let targets = try manifest.targets.map {
            try TuistGenerator.Target.from(manifest: $0,
                                           path: path,
                                           fileHandler: fileHandler,
                                           printer: printer)
        }

        let schemes = manifest.schemes.map { TuistGenerator.Scheme.from(manifest: $0) }

        let additionalFiles = manifest.additionalFiles.flatMap {
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            fileHandler: fileHandler,
                                            printer: printer)
        }
        
        let xcodeProjFileName = tuistConfig.generationOptions.reduce(name, { acc, item  in
            if case .prefixProjectNames(let prefixRaw) = item {
                return prefixRaw + acc
            }
            if case .suffixProjectNames(let suffixRaw) = item {
                return acc + suffixRaw
            }
            return acc
        })

        return Project(path: path,
                       name: name,
                       fileName: xcodeProjFileName,
                       settings: settings ?? .default,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
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
                       schemes: schemes,
                       additionalFiles: additionalFiles)
    }
}

extension TuistGenerator.Target {
    static func from(manifest: ProjectDescription.Target,
                     path: AbsolutePath,
                     fileHandler: FileHandling,
                     printer: Printing) throws -> TuistGenerator.Target {
        let name = manifest.name
        let platform = try TuistGenerator.Platform.from(manifest: manifest.platform)
        let product = TuistGenerator.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let productName = manifest.productName

        let dependencies = manifest.dependencies.map { TuistGenerator.Dependency.from(manifest: $0) }

        let infoPlist = TuistGenerator.InfoPlist.from(manifest: manifest.infoPlist, path: path)
        let entitlements = manifest.entitlements.map { path.appending(RelativePath($0)) }

        let settings = manifest.settings.map { TuistGenerator.Settings.from(manifest: $0, path: path) }
        let sources = try TuistGenerator.Target.sources(projectPath: path, sources: manifest.sources?.globs.map {
            (glob: $0.glob, compilerFlags: $0.compilerFlags)
        } ?? [])

        let resourceFilter = { (path: AbsolutePath) -> Bool in
            TuistGenerator.Target.isResource(path: path, fileHandler: fileHandler)
        }
        let resources = (manifest.resources ?? []).flatMap {
            TuistGenerator.FileElement.from(manifest: $0,
                                            path: path,
                                            fileHandler: fileHandler,
                                            printer: printer,
                                            includeFiles: resourceFilter)
        }

        let headers = manifest.headers.map { TuistGenerator.Headers.from(manifest: $0, path: path, fileHandler: fileHandler) }

        let coreDataModels = try manifest.coreDataModels.map {
            try TuistGenerator.CoreDataModel.from(manifest: $0, path: path, fileHandler: fileHandler)
        }

        let actions = manifest.actions.map { TuistGenerator.TargetAction.from(manifest: $0, path: path) }
        let environment = manifest.environment

        return TuistGenerator.Target(name: name,
                                     platform: platform,
                                     product: product,
                                     productName: productName,
                                     bundleId: bundleId,
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
    static func from(manifest: ProjectDescription.InfoPlist, path: AbsolutePath) -> TuistGenerator.InfoPlist {
        switch manifest {
        case let .file(infoplistPath):
            return .file(path: path.appending(RelativePath(infoplistPath)))
        case let .dictionary(dictionary):
            return .dictionary(
                dictionary.mapValues { TuistGenerator.InfoPlist.Value.from(manifest: $0) }
            )
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
    static func from(manifest: ProjectDescription.Settings, path: AbsolutePath) -> TuistGenerator.Settings {
        let base = manifest.base
        let debug = manifest.debug.flatMap { TuistGenerator.Configuration.from(manifest: $0, path: path) }
        let release = manifest.release.flatMap { TuistGenerator.Configuration.from(manifest: $0, path: path) }
        let defaultSettings = TuistGenerator.DefaultSettings.from(manifest: manifest.defaultSettings)
        return TuistGenerator.Settings(base: base,
                                       configurations: [.debug: debug, .release: release],
                                       defaultSettings: defaultSettings)
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

extension TuistGenerator.Configuration {
    static func from(manifest: ProjectDescription.Configuration, path: AbsolutePath) -> TuistGenerator.Configuration {
        let settings = manifest.settings
        let xcconfig = manifest.xcconfig.flatMap { path.appending(RelativePath($0)) }
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistGenerator.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction, path: AbsolutePath) -> TuistGenerator.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistGenerator.TargetAction.Order.from(manifest: manifest.order)
        let path = manifest.path.map { AbsolutePath($0, relativeTo: path) }
        let arguments = manifest.arguments
        let inputPaths = manifest.inputPaths
        let inputFileListPaths = manifest.inputFileListPaths
        let outputPaths = manifest.outputPaths
        let outputFileListPaths = manifest.outputFileListPaths
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
                     path: AbsolutePath,
                     fileHandler: FileHandling) throws -> TuistGenerator.CoreDataModel {
        let modelPath = path.appending(RelativePath(manifest.path))
        if !fileHandler.exists(modelPath) {
            throw GeneratorModelLoaderError.missingFile(modelPath)
        }
        let versions = fileHandler.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistGenerator.Headers {
    static func from(manifest: ProjectDescription.Headers, path: AbsolutePath, fileHandler: FileHandling) -> TuistGenerator.Headers {
        let `public` = manifest.public?.globs.flatMap {
            headerFiles(path: path, glob: $0, fileHandler: fileHandler)
        } ?? []

        let `private` = manifest.private?.globs.flatMap {
            headerFiles(path: path, glob: $0, fileHandler: fileHandler)
        } ?? []

        let project = manifest.project?.globs.flatMap {
            headerFiles(path: path, glob: $0, fileHandler: fileHandler)
        } ?? []

        return Headers(public: `public`, private: `private`, project: project)
    }

    private static func headerFiles(path: AbsolutePath,
                                    glob: String,
                                    fileHandler: FileHandling) -> [AbsolutePath] {
        return fileHandler.glob(path, glob: glob).filter {
            if let `extension` = $0.extension, Headers.extensions.contains(".\(`extension`)") {
                return true
            }
            return false
        }
    }
}

extension TuistGenerator.Dependency {
    static func from(manifest: ProjectDescription.TargetDependency) -> TuistGenerator.Dependency {
        switch manifest {
        case let .target(name):
            return .target(name: name)
        case let .project(target, projectPath):
            return .project(target: target, path: RelativePath(projectPath))
        case let .framework(frameworkPath):
            return .framework(path: RelativePath(frameworkPath))
        case let .library(libraryPath, publicHeaders, swiftModuleMap):
            return .library(path: RelativePath(libraryPath),
                            publicHeaders: RelativePath(publicHeaders),
                            swiftModuleMap: swiftModuleMap.map { RelativePath($0) })
        case let .sdk(name, status):
            return .sdk(name: name,
                        status: .from(manifest: status))
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
        let config = BuildConfiguration.from(manifest: manifest.config)
        let coverage = manifest.coverage
        let preActions = manifest.preActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }
        let postActions = manifest.postActions.map { TuistGenerator.ExecutionAction.from(manifest: $0) }

        return TestAction(targets: targets,
                          arguments: arguments,
                          config: config,
                          coverage: coverage,
                          preActions: preActions,
                          postActions: postActions)
    }
}

extension TuistGenerator.RunAction {
    static func from(manifest: ProjectDescription.RunAction) -> TuistGenerator.RunAction {
        let config = BuildConfiguration.from(manifest: manifest.config)
        let executable = manifest.executable
        let arguments = manifest.arguments.map { TuistGenerator.Arguments.from(manifest: $0) }

        return RunAction(config: config,
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
    static func from(manifest: ProjectDescription.BuildConfiguration) -> TuistGenerator.BuildConfiguration {
        switch manifest {
        case .debug:
            return .debug
        case .release:
            return .release
        }
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
