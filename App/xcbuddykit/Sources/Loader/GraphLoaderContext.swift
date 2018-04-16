import Foundation
import PathKit

protocol GraphLoaderContexting: AnyObject {
    var manifestLoader: GraphManifestLoading { get }
    var cache: GraphLoaderCaching { get }
    var projectPath: Path { get }
    var fileHandler: FileHandling { get }
    func with(projectPath: Path) -> GraphLoaderContexting
}

class GraphLoaderContext: GraphLoaderContexting {
    let manifestLoader: GraphManifestLoading
    let cache: GraphLoaderCaching
    let projectPath: Path
    let fileHandler: FileHandling

    init(manifestLoader: GraphManifestLoading,
         cache: GraphLoaderCaching,
         projectPath: Path,
         fileHandler: FileHandling = FileHandler()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.projectPath = projectPath
        self.fileHandler = fileHandler
    }

    func with(projectPath: Path) -> GraphLoaderContexting {
        return GraphLoaderContext(manifestLoader: manifestLoader,
                                  cache: cache,
                                  projectPath: projectPath,
                                  fileHandler: fileHandler)
    }
}
