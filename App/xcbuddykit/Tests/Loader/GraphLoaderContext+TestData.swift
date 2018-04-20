import Basic
import Foundation
@testable import xcbuddykit

extension GraphLoaderContext {
    static func test(manifestLoading: GraphManifestLoading = MockGraphManifestLoader(),
                     cache: GraphLoaderCaching = MockGraphLoaderCache(),
                     path: AbsolutePath = AbsolutePath("/test"),
                     fileHandler: FileHandling = MockFileHandler()) -> GraphLoaderContext {
        return GraphLoaderContext(manifestLoader: manifestLoading,
                                  cache: cache,
                                  path: path,
                                  fileHandler: fileHandler)
    }
}
