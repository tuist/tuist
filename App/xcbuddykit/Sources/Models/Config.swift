import Foundation
import PathKit
import Unbox

class Config {
    let path: Path
    init(path: Path) {
        self.path = path
    }
}

extension Config {
    static func read(path: Path,
                     manifestLoader: GraphManifestLoading,
                     cache: GraphLoaderCaching,
                     fileHandler: FileHandling = FileHandler()) throws -> Config {
        if let config = cache.config(path) { return config }
        let config = try Config(path: path,
                                manifestLoader: manifestLoader,
                                cache: cache,
                                fileHandler: fileHandler)
        cache.add(config: config)
        return config
    }

    fileprivate convenience init(path: Path,
                                 manifestLoader: GraphManifestLoading,
                                 cache _: GraphLoaderCaching,
                                 fileHandler: FileHandling = FileHandler()) throws {
        let configPath = path + "Config.swift"
        if !fileHandler.exists(configPath) {
            throw GraphLoadingError.missingFile(configPath)
        }
        let json = try manifestLoader.load(path: configPath)
        _ = try Unboxer(data: json)
        self.init(path: path)
    }
}
