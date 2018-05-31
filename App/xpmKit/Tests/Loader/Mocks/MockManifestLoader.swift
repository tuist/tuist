import Basic
import Foundation
@testable import xpmKit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadStub: ((AbsolutePath, GraphLoaderContexting) throws -> JSON)?

    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        return try loadStub?(path, context) ?? JSON.dictionary([:])
    }
}
