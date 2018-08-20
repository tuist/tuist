import Basic
import Foundation
import TuistCore

class Project: Equatable {

    // MARK: - Attributes

    let path: AbsolutePath
    let name: String
    let targets: [Target]
    let settings: Settings?

    // MARK: - Init

    init(path: AbsolutePath,
         name: String,
         settings: Settings? = nil,
         targets: [Target]) {
        self.path = path
        self.name = name
        self.targets = targets
        self.settings = settings
    }

    // MARK: - Init

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, circularDetector: GraphCircularDetecting) throws -> Project {
        if let project = cache.project(path) {
            return project
        } else {
            let project = try Project(path: path, cache: cache)
            cache.add(project: project)

            for target in project.targets {
                if cache.targetNode(path, name: target.name) != nil { continue }
                _ = try TargetNode.read(name: target.name, path: path, cache: cache, circularDetector: circularDetector)
            }

            return project
        }
    }

    init(path: AbsolutePath,
         cache _: GraphLoaderCaching,
         fileHandler: FileHandling = FileHandler(),
         manifestLoader: GraphManifestLoading = GraphManifestLoader()) throws {
        let projectPath = path.appending(component: Constants.Manifest.project)
        if !fileHandler.exists(projectPath) { throw GraphLoadingError.missingFile(projectPath) }
        let json = try manifestLoader.load(path: projectPath)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(json: $0, projectPath: path, fileHandler: fileHandler) })
        let settingsJSON: JSON? = try? json.get("settings")
        settings = try settingsJSON.map({ try Settings(json: $0, projectPath: path, fileHandler: fileHandler) })
    }

    // MARK: - Equatable

    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.targets == rhs.targets &&
            lhs.settings == rhs.settings
    }
}
