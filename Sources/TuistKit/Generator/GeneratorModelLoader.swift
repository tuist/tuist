import Basic
import Foundation
import TuistCore
import TuistGenerator

enum GeneratorModelLoaderError: Error, Equatable, FatalError {
    case malformedManifest(String)
    
    var type: ErrorType {
        switch self {
        case .malformedManifest:
            return .abort
        }
    }
    
    var description: String {
        switch self {
        case .malformedManifest(let details):
            return "The Project manifest appears to be malformed: \(details)"
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
        let json = try manifestLoader.load(.project, path: path)
        let project = try TuistKit.Project.from(json: json, path: path, fileHandler: fileHandler)
        return project
    }
    
    func loadWorkspace(at path: AbsolutePath) throws -> Workspace {
        let json = try manifestLoader.load(.workspace, path: path)
        let workspace = try TuistKit.Workspace.from(json: json, path: path)
        return workspace
    }
}

extension TuistKit.Workspace {
    static func from(json: JSON, path: AbsolutePath) throws -> TuistKit.Workspace {
        let projectsStrings: [String] = try json.get("projects")
        let name: String = try json.get("name")
        let projectsRelativePaths: [RelativePath] = projectsStrings.map { RelativePath($0) }
        let projects = projectsRelativePaths.map { path.appending($0) }
        return Workspace(name: name, projects: projects)
    }
}

extension TuistKit.Project {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Project {
        let name: String = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        let targets = try targetsJSONs.map { try TuistKit.Target.from(json: $0, path: path, fileHandler: fileHandler) }
        let settingsJSON: JSON? = try? json.get("settings")
        let settings = try settingsJSON.map { try TuistKit.Settings.from(json: $0, path: path, fileHandler: fileHandler) }
        
        return Project(path: path,
                       name: name,
                       settings: settings,
                       targets: targets)
    }
}

extension TuistKit.Target {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Target {
        let name: String = try json.get("name")
        let platformString: String = try json.get("platform")
        guard let platform = TuistKit.Platform(rawValue: platformString) else {
            throw GeneratorModelLoaderError.malformedManifest("unrecognized platform '\(platformString)'")
        }
        let productString: String = try json.get("product")
        guard let product = TuistKit.Product(rawValue: productString) else {
            throw GeneratorModelLoaderError.malformedManifest("unrecognized product '\(productString)'")
        }
        let bundleId: String = try json.get("bundle_id")
        let dependenciesJSON: [JSON] = try json.get("dependencies")
        let dependencies = try dependenciesJSON.map { try TuistKit.Dependency.from(json: $0, path: path, fileHandler: fileHandler) }
        
        // Info.plist
        let infoPlistPath: String = try json.get("info_plist")
        let infoPlist = path.appending(RelativePath(infoPlistPath))
        
        // Entitlements
        let entitlementsPath: String? = try? json.get("entitlements")
        let entitlements = entitlementsPath.map { path.appending(RelativePath($0)) }
        
        // Settings
        let settingsDictionary: [String: JSONSerializable]? = try? json.get("settings")
        let settings = try settingsDictionary.map { try TuistKit.Settings.from(json: JSON($0), path: path, fileHandler: fileHandler) }
        
        // Sources
        let sourcesString: String = try json.get("sources")
        let sources = try TuistKit.Target.sources(projectPath: path, sources: sourcesString, fileHandler: fileHandler)
        
        // Resources
        let resourcesString: String? = try? json.get("resources")
        let resources = try resourcesString.map {
            try TuistKit.Target.resources(projectPath: path, resources: $0, fileHandler: fileHandler) } ?? []
        
        // Headers
        let headersJSON: JSON? = try? json.get("headers")
        let headers = try headersJSON.map { try TuistKit.Headers.from(json: $0, path: path, fileHandler: fileHandler) }
        
        // Core Data Models
        let coreDataModelsJSON: [JSON] = (try? json.get("core_data_models")) ?? []
        let coreDataModels = try coreDataModelsJSON.map { try TuistKit.CoreDataModel.from(json: $0, path: path, fileHandler: fileHandler) }
        
        // Actions
        let actionsJSON: [JSON] = (try? json.get("actions")) ?? []
        let actions = try actionsJSON.map { try TuistKit.TargetAction.from(json: $0, path: path, fileHandler: fileHandler) }
        
        // Environment
        let environment: [String: String] = (try? json.get("environment")) ?? [:]
        
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
                      dependencies: dependencies)
    }
}

extension TuistKit.Settings {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Settings {
        let base: [String: String] = try json.get("base")
        let debugJSON: JSON? = try? json.get("debug")
        let debug = try debugJSON.flatMap { try TuistKit.Configuration.from(json: $0, path: path, fileHandler: fileHandler) }
        let releaseJSON: JSON? = try? json.get("release")
        let release = try releaseJSON.flatMap { try TuistKit.Configuration.from(json: $0, path: path, fileHandler: fileHandler) }
        return Settings(base: base, debug: debug, release: release)
    }
}

extension TuistKit.Configuration {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Configuration {
        let settings: [String: String] = try json.get("settings")
        let xcconfigString: String? = json.get("xcconfig")
        let xcconfig = xcconfigString.flatMap({ path.appending(RelativePath($0)) })
        return Configuration(settings: settings, xcconfig: xcconfig)
    }
}

extension TuistKit.TargetAction {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.TargetAction {
        let name: String = try json.get("name")
        let tool: String? = try? json.get("tool")
        let order = TuistKit.TargetAction.Order(rawValue: try json.get("order"))!
        let pathString: String? = try? json.get("path")
        let path = pathString.map { AbsolutePath($0, relativeTo: path) }
        let arguments: [String] = try json.get("arguments")
        return TargetAction(name: name, order: order, tool: tool, path: path, arguments: arguments)
    }
}

extension TuistKit.CoreDataModel {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.CoreDataModel {
        let pathString: String = try json.get("path")
        let modelPath = path.appending(RelativePath(pathString))
        if !fileHandler.exists(modelPath) {
            throw GraphLoadingError.missingFile(modelPath)
        }
        let versions: [AbsolutePath] = path.glob("*.xcdatamodel")
        let currentVersion: String = try json.get("current_version")
        return CoreDataModel(path: modelPath, versions: versions, currentVersion: currentVersion)
    }
}

extension TuistKit.Headers {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Headers {
        let publicString: String? = try? json.get("public")
        let `public` = publicString.map { path.glob($0) } ?? []
        let privateString: String? = try? json.get("private")
        let `private` = privateString.map { path.glob($0) } ?? []
        let projectString: String? = try? json.get("project")
        let project = projectString.map { path.glob($0) } ?? []
        return Headers(public: `public`, private: `private`, project: project)
    }
}

extension TuistKit.Dependency {
    static func from(json: JSON, path: AbsolutePath, fileHandler: FileHandling) throws -> TuistKit.Dependency {
        let type: String = try json.get("type")
        switch type {
        case "target":
            return .target(name: try json.get("name"))
        case "project":
            let target: String = try json.get("target")
            let path: String = try json.get("path")
            return .project(target: target, path: RelativePath(path))
        case "framework":
            let path: String = try json.get("path")
            return .framework(path: RelativePath(path))
        case "library":
            let path: String = try json.get("path")
            let publicHeaders: String = try json.get("public_headers")
            let swiftModuleMap: RelativePath? = json.get("swift_module_map").map { RelativePath($0) }
            return .library(path: RelativePath(path),
                            publicHeaders: RelativePath(publicHeaders),
                            swiftModuleMap: swiftModuleMap)
        default:
            throw GeneratorModelLoaderError.malformedManifest("unrecognized dependency type '\(type)'")
        }
    }
}

extension TuistKit.Scheme {
    static func from(json: JSON) throws -> TuistKit.Scheme {
        let name: String = try json.get("name")
        let shared: Bool = try json.get("shared")
        let buildActionJson: JSON? = try? json.get("build_action")
        let buildAction = try buildActionJson.map { try TuistKit.BuildAction.from(json: $0) }
        let testActionJson: JSON? = try? json.get("test_action")
        let testAction = try testActionJson.map { try TuistKit.TestAction.from(json: $0) }
        let runActionJson: JSON? = try? json.get("run_action")
        let runAction = try runActionJson.map { try TuistKit.RunAction.from(json: $0) }
        
        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction)
    }

}

extension TuistKit.BuildAction {
    static func from(json: JSON) throws -> TuistKit.BuildAction {
        return BuildAction(targets: try json.get("targets"))
    }
}

extension TuistKit.TestAction {
    static func from(json: JSON) throws -> TuistKit.TestAction {
        let targets: [String] = try json.get("targets")
        let argumentsJson: JSON? = try? json.get("arguments")
        let arguments = try argumentsJson.map { try TuistKit.Arguments.from(json: $0) }
        
        let configString: String = try json.get("config")
        let config = try BuildConfiguration.from(string: configString)
        
        let coverage: Bool = try json.get("coverage")
        return TestAction(targets: targets,
                          arguments: arguments,
                          config: config,
                          coverage: coverage)
    }
}

extension TuistKit.RunAction {
    static func from(json: JSON) throws -> TuistKit.RunAction {
        let configString: String = try json.get("config")
        let config = try BuildConfiguration.from(string: configString)
        let executable: String? = try? json.get("executable")
        let argumentsJson: JSON? = try? json.get("arguments")
        let arguments = try argumentsJson.map { try TuistKit.Arguments.from(json: $0) }
        
        return RunAction(config: config,
                         executable: executable,
                         arguments: arguments)
    }

}

extension TuistKit.Arguments {
    static func from(json: JSON) throws -> TuistKit.Arguments {
        return Arguments(environment: try json.get("environment"),
                         launch: try json.get("launch"))
    }
}

extension TuistKit.BuildConfiguration {
    static func from(string: String) throws -> TuistKit.BuildConfiguration  {
        guard let config = BuildConfiguration(rawValue: string) else {
            throw GeneratorModelLoaderError.malformedManifest("unrecognized configuration '\(string)'")
        }
        return config
    }
}
