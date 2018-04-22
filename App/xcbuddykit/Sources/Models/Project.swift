import Basic
import Foundation

/// Class that represents an Xcode project.
class Project: Equatable {
    /// Path where the project is defined. The path points to the folder where the Project.swift file is.
    let path: AbsolutePath

    /// Project name.
    let name: String

    /// Project schemes.
    let schemes: [Scheme]

    /// Project targets.
    let targets: [Target]

    /// Project build settings.
    let settings: Settings?

    /// Project configuration.
    let config: Config?

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: path to the folder where the manifest is.
    ///   - name: project name.
    ///   - config: project configuration.
    ///   - schemes: project schemes.
    ///   - settings: project build settings.
    ///   - targets: project targets.
    init(path: AbsolutePath,
         name: String,
         config: Config? = nil,
         schemes: [Scheme],
         settings: Settings? = nil,
         targets: [Target]) {
        self.path = path
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
        self.config = config
    }

    /// Tries to fetch the Project from the cache and if if doesn't exist it parses it and stores it in the cache.
    ///
    /// - Parameters:
    ///   - path: path to the folder where the Project.swift file is.
    ///   - context: graph loader context.
    /// - Returns: initialized Project or the copy from the graph loader cache if it exists.
    /// - Throws: an error if the project cannot be parsed.
    static func at(_ path: AbsolutePath, context: GraphLoaderContexting) throws -> Project {
        if let project = context.cache.project(path) {
            return project
        } else {
            let project = try Project(path: path, context: context)
            context.cache.add(project: project)
            return project
        }
    }

    /// Parses the Project from the manifest Project.swift.
    ///
    /// - Parameters:
    ///   - path: path to the folder where the Project.swift file is.
    ///   - context: grah loader context.
    /// - Throws: an error if the project  cannot be parsed.
    init(path: AbsolutePath, context: GraphLoaderContexting) throws {
        let projectPath = path.appending(component: Constants.Manifest.project)
        if !context.fileHandler.exists(projectPath) { throw GraphLoadingError.missingFile(projectPath) }
        let json = try context.manifestLoader.load(path: projectPath, context: context)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(json: $0, projectPath: path, context: context) })
        schemes = try json.get("schemes")
        if let configStringPath: String = json.get("config") {
            let configPath = RelativePath(configStringPath)
            let path = projectPath.appending(configPath)
            config = try Config.at(path, context: context)
        } else {
            config = nil
        }
        let settingsJSON: JSON? = try? json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, projectPath: path, context: context) })
    }

    /// Compares two instances of a project.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.schemes == rhs.schemes &&
            lhs.targets == rhs.targets &&
            lhs.settings == rhs.settings &&
            lhs.config == rhs.config
    }
}
