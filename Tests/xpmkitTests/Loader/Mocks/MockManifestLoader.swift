import Basic
import Foundation
@testable import xpmkit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadStub: ((AbsolutePath, GraphLoaderContexting) throws -> JSON)?

    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        return try loadStub?(path, context) ?? JSON.dictionary([:])
    }
}
