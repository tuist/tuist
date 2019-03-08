import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistGenerator

enum GeneratorModelLoaderError: Error, Equatable, FatalError {
    case featureNotYetSupported(String)
    var type: ErrorType {
        switch self {
        case .featureNotYetSupported:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .featureNotYetSupported(details):
            return "\(details) is not yet supported"
        }
    }
}

class GeneratorModelLoader: GeneratorModelLoading {
    private let fileHandler: FileHandling
    private let manifestLoader: GraphManifestLoading

    init(fileHandler: FileHandling, manifestLoader: GraphManifestLoading) {
        self.fileHandler = fileHandler
        self.manifestLoader = manifestLoader
    }

    func loadProject(at path: AbsolutePath) throws -> Project {
        let manifest = try manifestLoader.loadProject(at: path)
        let project = try TuistKit.Project.from(manifest: manifest, path: path, fileHandler: fileHandler)
        return project
    }

    func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        let manifest = try manifestLoader.loadWorkspace(at: path)
        let workspace = try TuistKit.Workspace.from(manifest: manifest, path: path)
        return workspace
    }
}

extension TuistKit.Workspace {
    static func from(manifest: ProjectDescription.Workspace,
                     path: AbsolutePath) throws -> TuistKit.Workspace {
        return Workspace(name: manifest.name,
                         projects: manifest.projects.map { path.appending(RelativePath($0)) })
    }
}

extension TuistKit.Project {
    static func from(manifest: ProjectDescription.Project,
                     path: AbsolutePath,
                     fileHandler: FileHandling) throws -> TuistKit.Project {
        let name = manifest.name
        let settings = manifest.settings.map { TuistKit.Settings.from(manifest: $0, path: path) }
        let targets = try manifest.targets.map { try TuistKit.Target.from(manifest: $0, path: path, fileHandler: fileHandler) }

        return Project(path: path,
                       name: name,
                       settings: settings,
                       filesGroup: .group(name: "Project"),
                       targets: targets)
    }
}

extension TuistKit.Target {
    static func from(manifest: ProjectDescription.Target, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Target {
        let name = manifest.name
        let platform = try TuistKit.Platform.from(manifest: manifest.platform)
        let product = TuistKit.Product.from(manifest: manifest.product)

        let bundleId = manifest.bundleId
        let dependencies = manifest.dependencies.map { TuistKit.Dependency.from(manifest: $0) }

        let infoPlist = path.appending(RelativePath(manifest.infoPlist))
        let entitlements = manifest.entitlements.map { path.appending(RelativePath($0)) }

        let settings = manifest.settings.map { TuistKit.Settings.from(manifest: $0, path: path) }

        let sources = try TuistKit.Target.sources(projectPath: path, sources: manifest.sources, fileHandler: fileHandler)
        let resources = try manifest.resources.map {
            try TuistKit.Target.resources(projectPath: path, resources: $0, fileHandler: fileHandler)
        } ?? []
        let headers = manifest.headers.map { TuistKit.Headers.from(manifest: $0, path: path, fileHandler: fileHandler) }

        let coreDataModels = try manifest.coreDataModels.map { try TuistKit.CoreDataModel.from(manifest: $0, path: path, fileHandler: fileHandler) }

        let actions = manifest.actions.map { TuistKit.TargetAction.from(manifest: $0, path: path) }
        let environment = manifest.environment

        return Target(name: name,
                      platform: platform,
                      product: product,
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

extension TuistKit.Settings {
    static func from(manifest: ProjectDescription.Settings, path: AbsolutePath) -> TuistKit.Settings {
        let base = manifest.base
        let debug = manifest.debug.flatMap { TuistKit.Configuration.from(manifest: $0, path: path) }
        let release = manifest.release.flatMap { TuistKit.Configuration.from(manifest: $0, path: path) }
        return Settings(base: base, debug: debug, release: release)
    }
}

extension TuistKit.Configuration {
    static func from(manifest: ProjectDescription.Configuration, path: AbsolutePath) -> TuistKit.Configuration {
        let settings = manifest.settings
        let xcconfig = manifest.xcconfig.flatMap({ path.appending(RelativePath($0)) })
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistKit.TargetAction {
    static func from(manifest: ProjectDescription.TargetAction, path: AbsolutePath) -> TuistKit.TargetAction {
        let name = manifest.name
        let tool = manifest.tool
        let order = TuistKit.TargetAction.Order.from(manifest: manifest.order)
        let path = manifest.path.map { AbsolutePath($0, relativeTo: path) }
        let arguments = manifest.arguments
        return TargetAction(name: name, order: order, tool: tool, path: path, arguments: arguments)
    }
}

extension TuistKit.TargetAction.Order {
    static func from(manifest: ProjectDescription.TargetAction.Order) -> TuistKit.TargetAction.Order {
        switch manifest {
        case .pre:
            return .pre
        case .post:
            return .post
        }
    }
}

extension TuistKit.CoreDataModel {
    static func from(manifest: ProjectDescription.CoreDataModel, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.CoreDataModel {
        let modelPath = path.appending(RelativePath(manifest.path))
        if !fileHandler.exists(modelPath) {
            throw GraphLoadingError.missingFile(modelPath)
        }
        let versions = fileHandler.glob(modelPath, glob: "*.xcdatamodel")
        let currentVersion = manifest.currentVersion
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistKit.Headers {
    static func from(manifest: ProjectDescription.Headers, path: AbsolutePath, fileHandler: FileHandling) -> TuistKit.Headers {
        let `public` = manifest.public.map { fileHandler.glob(path, glob: $0) } ?? []
        let `private` = manifest.private.map { fileHandler.glob(path, glob: $0) } ?? []
        let project = manifest.project.map { fileHandler.glob(path, glob: $0) } ?? []
        return Headers(public: `public`, private: `private`, project: project)
    }
}

extension TuistKit.Dependency {
    static func from(manifest: ProjectDescription.TargetDependency) -> TuistKit.Dependency {
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
        }
    }
}

extension TuistKit.Scheme {
    static func from(manifest: ProjectDescription.Scheme) -> TuistKit.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = manifest.buildAction.map { TuistKit.BuildAction.from(manifest: $0) }
        let testAction = manifest.testAction.map { TuistKit.TestAction.from(manifest: $0) }
        let runAction = manifest.runAction.map { TuistKit.RunAction.from(manifest: $0) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }
}

extension TuistKit.BuildAction {
    static func from(manifest: ProjectDescription.BuildAction) -> TuistKit.BuildAction {
        return BuildAction(targets: manifest.targets)
    }
}

extension TuistKit.TestAction {
    static func from(manifest: ProjectDescription.TestAction) -> TuistKit.TestAction {
        let targets = manifest.targets
        let arguments = manifest.arguments.map { TuistKit.Arguments.from(manifest: $0) }
        let config = BuildConfiguration.from(manifest: manifest.config)
        let coverage = manifest.coverage
        return TestAction(targets: targets,
                          arguments: arguments,
                          config: config,
                          coverage: coverage)
    }
}

extension TuistKit.RunAction {
    static func from(manifest: ProjectDescription.RunAction) -> TuistKit.RunAction {
        let config = BuildConfiguration.from(manifest: manifest.config)
        let executable = manifest.executable
        let arguments = manifest.arguments.map { TuistKit.Arguments.from(manifest: $0) }

        return RunAction(config: config,
                         executable: executable,
                         arguments: arguments)
    }
}

extension TuistKit.Arguments {
    static func from(manifest: ProjectDescription.Arguments) -> TuistKit.Arguments {
        return Arguments(environment: manifest.environment,
                         launch: manifest.launch)
    }
}

extension TuistKit.BuildConfiguration {
    static func from(manifest: ProjectDescription.BuildConfiguration) -> TuistKit.BuildConfiguration {
        switch manifest {
        case .debug:
            return .debug
        case .release:
            return .release
        }
    }
}

extension TuistKit.Product {
    static func from(manifest: ProjectDescription.Product) -> TuistKit.Product {
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

extension TuistKit.Platform {
    static func from(manifest: ProjectDescription.Platform) throws -> TuistKit.Platform {
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
