import Basic
import Foundation
import TuistCore

class Project: Equatable {
    // MARK: - Attributes

    /// Path to the folder that contains the project manifest.
    let path: AbsolutePath

    /// Project name.
    let name: String

    /// Commands to configure the environment for the project.
    let up: [UpCommand]

    /// Project targets.
    let targets: [Target]

    /// Project settings.
    let settings: Settings?

    // MARK: - Init

    /// Initializes the project with its attributes.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - name: Project name.
    ///   - up: Commands to configure the environment for the project.
    ///   - targets: Project settings.
    init(path: AbsolutePath,
         name: String,
         up: [UpCommand] = [],
         settings: Settings? = nil,
         targets: [Target]) {
        self.path = path
        self.name = name
        self.up = up
        self.targets = targets
        self.settings = settings
    }

    // MARK: - Init

    /// Parses the project manifest at the given path and returns a Project instance with the representation.
    ///
    /// - Parameters:
    ///   - path: Path to the folder that contains the project manifest.
    ///   - cache: Cache instance to cache projects and dependencies.
    ///   - circularDetector: Utility to find circular dependencies between targets.
    /// - Returns: Initialized project.
    /// - Throws: An error if the project has an invalid format.
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
        let json = try manifestLoader.load(.project, path: path)
        self.path = path
        name = try json.get("name")
        let targetsJSONs: [JSON] = try json.get("targets")
        targets = try targetsJSONs.map({ try Target(dictionary: $0, projectPath: path, fileHandler: fileHandler) })
        let upJSONs: [JSON] = try json.get("up")
        up = try upJSONs.compactMap({ try UpCommand.with(dictionary: $0, projectPath: path, fileHandler: fileHandler) })
        let settingsJSON: JSON? = try? json.get("settings")
        settings = try settingsJSON.map({ try Settings(dictionary: $0, projectPath: path, fileHandler: fileHandler) })
    }

    // MARK: - Equatable

    static func == (lhs: Project, rhs: Project) -> Bool {
        return lhs.path == rhs.path &&
            lhs.name == rhs.name &&
            lhs.targets == rhs.targets &&
            lhs.settings == rhs.settings
    }
}
