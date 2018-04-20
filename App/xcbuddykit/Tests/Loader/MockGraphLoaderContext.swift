import Basic
import Foundation
@testable import xcbuddykit

final class MockGraphLoaderContext: GraphLoaderContexting {
    var manifestLoader: GraphManifestLoading { return mockManifestLoader }
    let mockManifestLoader: MockGraphManifestLoader
    var cache: GraphLoaderCaching { return mockCache }
    let mockCache: MockGraphLoaderCache
    var fileHandler: FileHandling { return mockFileHandler }
    let mockFileHandler: MockFileHandler

    init(manifestLoader: MockGraphManifestLoader = MockGraphManifestLoader(),
         cache: MockGraphLoaderCache = MockGraphLoaderCache(),
         fileHandler: MockFileHandler = MockFileHandler()) {
        mockManifestLoader = manifestLoader
        mockCache = cache
        mockFileHandler = fileHandler
    }
}
