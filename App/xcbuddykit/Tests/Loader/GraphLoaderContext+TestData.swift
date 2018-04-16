import Foundation
import PathKit
@testable import xcbuddykit

extension GraphLoaderContext {
    static func test(manifestLoading: GraphManifestLoading = MockGraphManifestLoader(),
                     cache: GraphLoaderCaching = MockGraphLoaderCache(),
                     projectPath: Path = Path("/test"),
                     fileHandler: FileHandling = MockFileHandler()) -> GraphLoaderContext {
        return GraphLoaderContext(manifestLoader: manifestLoading,
                                  cache: cache,
                                  projectPath: projectPath,
                                  fileHandler: fileHandler)
    }
}
