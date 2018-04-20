import Basic
import Foundation

class Project {
    let path: AbsolutePath
    let name: String
    let schemes: [Scheme]
    let targets: [Target]
    let settings: Settings?
    let config: Config?

    init(path: AbsolutePath,
         name: String,
         schemes: [Scheme],
         targets: [Target],
         settings: Settings? = nil,
         config: Config? = nil) {
        self.path = path
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
        self.config = config
    }

    static func read(path: AbsolutePath, context: GraphLoaderContexting) throws -> Project {
        if let project = context.cache.project(path) {
            return project
        } else {
            let project = try Project(path: path, context: context)
            context.cache.add(project: project)
            return project
        }
    }

    init(path: AbsolutePath, context: GraphLoaderContexting) throws {
        let projectPath = path.appending(component: Constants.Manifest.project)
        if !context.fileHandler.exists(projectPath) { throw GraphLoadingError.missingFile(projectPath) }
        let json = try context.manifestLoader.load(path: projectPath, context: context)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(json: $0, projectPath: path, context: context) })
        schemes = try json.get("schemes")
        config = try Project.config(json: json, projectPath: path, context: context)
        let settingsJSON: JSON? = try json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, projectPath: path, context: context) })
    }

    fileprivate static func config(json: JSON,
                                   projectPath: AbsolutePath,
                                   context: GraphLoaderContexting) throws -> Config? {
        guard let configStringPath: String = json.get("config") else { return nil }
        let configPath = RelativePath(configStringPath)
        let path = projectPath.appending(configPath)
        return try Config.read(path: path, context: context)
    }
}
