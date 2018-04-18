import Foundation
import Basic

@testable import xcbuddykit

extension GraphLoaderContext {
    static func test(manifestLoading: GraphManifestLoading = MockGraphManifestLoader(),
                     cache: GraphLoaderCaching = MockGraphLoaderCache(),
                     projectPath: AbsolutePath = AbsolutePath("/test"),
                     fileHandler: FileHandling = MockFileHandler()) -> GraphLoaderContext {
        return GraphLoaderContext(manifestLoader: manifestLoading,
                                  cache: cache,
                                  projectPath: projectPath,
                                  fileHandler: fileHandler)
    }
}
