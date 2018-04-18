import Basic
import Foundation

class Config {
    let path: AbsolutePath
    init(path: AbsolutePath) {
        self.path = path
    }
}

extension Config {
    static func read(path: AbsolutePath, context: GraphLoaderContexting) throws -> Config {
        if let config = context.cache.config(path) { return config }
        let config = try Config(path: path, context: context)
        context.cache.add(config: config)
        return config
    }

    fileprivate convenience init(path: AbsolutePath, context: GraphLoaderContexting) throws {
        let configPath = path.appending(RelativePath("Config.swift"))
        if !context.fileHandler.exists(configPath) {
            throw GraphLoadingError.missingFile(configPath)
        }
        let json = try context.manifestLoader.load(path: configPath, context: context)
        self.init(path: path)
    }
}
