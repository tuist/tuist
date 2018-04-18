import Foundation
import Basic
@testable import xcbuddykit

final class MockGraphManifestLoader: GraphManifestLoading {
    
    var loadStub: ((AbsolutePath, GraphLoaderContexting) throws -> JSON)?

    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        return try loadStub?(path, context) ?? JSON.dictionary([:])
    }
}
