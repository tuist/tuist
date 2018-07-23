import Basic
import Foundation
@testable import TuistKit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadStub: ((AbsolutePath) throws -> JSON)?

    func load(path: AbsolutePath) throws -> JSON {
        return try loadStub?(path) ?? JSON.dictionary([:])
    }
}
