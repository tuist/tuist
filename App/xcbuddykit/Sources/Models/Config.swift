import Basic
import Foundation

/// xcbuddy configuration
class Config: Equatable {
    /// Path to the folder that contains the Config.swift file.
    let path: AbsolutePath

    /// Initializes Config with its properties.
    ///
    /// - Parameter path: path to the folder that contains the Config.swift file.
    init(path: AbsolutePath) {
        self.path = path
    }

    /// Static method that tries to fetch the config from the cache. If it doesn't exist, it creates and instance, adds it to the cache, and returns it.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the Config.swift file.
    ///   - context: graph loader context.
    /// - Returns: xcbuddy configuration.
    /// - Throws: an error if the configuration cannot be parsed.
    static func at(_ path: AbsolutePath, context: GraphLoaderContexting) throws -> Config {
        if let config = context.cache.config(path) { return config }
        let config = try Config(path: path, context: context)
        context.cache.add(config: config)
        return config
    }

    /// Initializes the configuration from the manifest Config.swift.
    ///
    /// - Parameters:
    ///   - path: path to the the folder that contains the Config.swift file.
    ///   - context: graph loader context.
    /// - Throws: an error if the configuration cannot be parsed.
    fileprivate convenience init(path: AbsolutePath, context: GraphLoaderContexting) throws {
        let configPath = path.appending(RelativePath("Config.swift"))
        if !context.fileHandler.exists(configPath) {
            throw GraphLoadingError.missingFile(configPath)
        }
        let json = try context.manifestLoader.load(path: configPath, context: context)
        self.init(path: path)
    }

    /// Compares two configurations.
    ///
    /// - Parameters:
    ///   - lhs: first configuration to be compared.
    ///   - rhs: second configuration to be compared.
    /// - Returns: true if the two configurations are the same.
    static func == (lhs: Config, rhs: Config) -> Bool {
        return lhs.path == rhs.path
    }
}
