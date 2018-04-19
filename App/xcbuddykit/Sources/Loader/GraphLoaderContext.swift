import Basic
import Foundation

protocol GraphLoaderContexting: AnyObject {
    var manifestLoader: GraphManifestLoading { get }
    var cache: GraphLoaderCaching { get }
    var path: AbsolutePath { get }
    var fileHandler: FileHandling { get }
    func with(path: AbsolutePath) -> GraphLoaderContexting
}

class GraphLoaderContext: GraphLoaderContexting {
    let manifestLoader: GraphManifestLoading
    let cache: GraphLoaderCaching
    let path: AbsolutePath
    let fileHandler: FileHandling

    init(manifestLoader: GraphManifestLoading,
         cache: GraphLoaderCaching,
         path: AbsolutePath,
         fileHandler: FileHandling = FileHandler()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.path = path
        self.fileHandler = fileHandler
    }

    init(projectPath: AbsolutePath) {
        manifestLoader = GraphManifestLoader()
        cache = GraphLoaderCache()
        path = projectPath
        fileHandler = FileHandler()
    }

    func with(path: AbsolutePath) -> GraphLoaderContexting {
        return GraphLoaderContext(manifestLoader: manifestLoader,
                                  cache: cache,
                                  path: path,
                                  fileHandler: fileHandler)
    }
}
