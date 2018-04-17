import Foundation
import Basic

protocol GraphLoaderContexting: AnyObject {
    var manifestLoader: GraphManifestLoading { get }
    var cache: GraphLoaderCaching { get }
    var projectPath: AbsolutePath { get }
    var fileHandler: FileHandling { get }
    func with(projectPath: AbsolutePath) -> GraphLoaderContexting
}

class GraphLoaderContext: GraphLoaderContexting {
    let manifestLoader: GraphManifestLoading
    let cache: GraphLoaderCaching
    let projectPath: AbsolutePath
    let fileHandler: FileHandling

    init(manifestLoader: GraphManifestLoading,
         cache: GraphLoaderCaching,
         projectPath: AbsolutePath,
         fileHandler: FileHandling = FileHandler()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.projectPath = projectPath
        self.fileHandler = fileHandler
    }

    func with(projectPath: AbsolutePath) -> GraphLoaderContexting {
        return GraphLoaderContext(manifestLoader: manifestLoader,
                                  cache: cache,
                                  projectPath: projectPath,
                                  fileHandler: fileHandler)
    }
}
