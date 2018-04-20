import Basic
import Foundation
@testable import xcbuddykit

final class MockGraphLoaderContext: GraphLoaderContexting {
    var manifestLoader: GraphManifestLoading { return mockManifestLoader }
    let mockManifestLoader: MockGraphManifestLoader
    var cache: GraphLoaderCaching { return mockCache }
    let mockCache: MockGraphLoaderCache
    let path: AbsolutePath
    var fileHandler: FileHandling { return mockFileHandler }
    let mockFileHandler: MockFileHandler

    func with(path: AbsolutePath) -> GraphLoaderContexting {
        return GraphLoaderContext(manifestLoader: manifestLoader,
                                  cache: cache,
                                  path: path,
                                  fileHandler: fileHandler)
    }

    init(manifestLoader: MockGraphManifestLoader = MockGraphManifestLoader(),
         cache: MockGraphLoaderCache = MockGraphLoaderCache(),
         path: AbsolutePath = AbsolutePath("/test"),
         fileHandler: MockFileHandler = MockFileHandler()) {
        mockManifestLoader = manifestLoader
        mockCache = cache
        self.path = path
        mockFileHandler = fileHandler
    }
}
