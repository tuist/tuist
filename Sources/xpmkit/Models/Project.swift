import Basic
import Foundation
import xpmcore

/// Class that represents an Xcode project.
class Project: Equatable {

    // MARK: - Attributes

    let path: AbsolutePath
    let name: String
    let schemes: [Scheme]
    let targets: [Target]
    let settings: Settings?

    // MARK: - Init

    init(path: AbsolutePath,
         name: String,
         schemes: [Scheme],
         settings: Settings? = nil,
         targets: [Target]) {
        self.path = path
        self.name = name
        self.schemes = schemes
        self.targets = targets
        self.settings = settings
    }

    // MARK: - Init

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching) throws -> Project {
        if let project = cache.project(path) {
            return project
        } else {
            let project = try Project(path: path)
            cache.add(project: project)
            return project
        }
    }

    init(path: AbsolutePath,
         fileHandler: FileHandling = FileHandler(),
         manifestLoader: GraphManifestLoading = GraphManifestLoader()) throws {
        let projectPath = path.appending(component: Constants.Manifest.project)
        if !fileHandler.exists(projectPath) { throw GraphLoadingError.missingFile(projectPath) }
        let json = try manifestLoader.load(path: projectPath)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(json: $0, projectPath: path, fileHandler: fileHandler) })
        schemes = try json.get("schemes")
        let settingsJSON: JSON? = try? json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, projectPath: path, fileHandler: fileHandler) })
    }

    // MARK: - Equatable

    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.schemes == rhs.schemes &&
            lhs.targets == rhs.targets &&
            lhs.settings == rhs.settings
    }
}
