import Foundation
import Basic

class Project {
    let path: AbsolutePath
    let name: String
    let schemes: [Scheme]
    let targets: [Target]
    let settings: Settings?
    let config: Config?

    init(path: Path,
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

    static func read(path: Path, manifestLoader: GraphManifestLoading, cache: GraphLoaderCaching) throws -> Project {
        if let project = cache.project(path) {
            return project
        } else {
            let project = try Project(path: path, manifestLoader: manifestLoader, cache: cache)
            cache.add(project: project)
            return project
        }
    }

    init(path: Path, manifestLoader: GraphManifestLoading, cache: GraphLoaderCaching) throws {
        let projectPath = path + Constants.Manifest.project
        if !projectPath.exists { throw GraphLoadingError.missingFile(projectPath) }
        let json = try manifestLoader.load(path: projectPath)
        let unboxer = try Unboxer(data: json)
        self.path = path
        name = try unboxer.unbox(key: "name")
        targets = try unboxer.unbox(key: "targets")
        schemes = try unboxer.unbox(key: "schemes")
        config = try Project.config(projectPath: path, unboxer: unboxer, manifestLoader: manifestLoader, cache: cache)
        settings = unboxer.unbox(key: "settings")
    }

    fileprivate static func config(projectPath: Path,
                                   unboxer: Unboxer,
                                   manifestLoader: GraphManifestLoading,
                                   cache: GraphLoaderCaching) throws -> Config? {
        guard let configStringPath: String = unboxer.unbox(key: "config") else { return nil }
        let configPath = Path(configStringPath)
        try configPath.assertRelative()
        let path = (projectPath + configPath).absolute()
        return try Config.read(path: path,
                               manifestLoader: manifestLoader,
                               cache: cache)
    }
}
