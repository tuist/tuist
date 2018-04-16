import Foundation
import PathKit
@testable import xcbuddykit

final class MockGraphManifestLoader: GraphManifestLoading {
    var loadStub: ((Path) throws -> Data)?

    func load(path: Path) throws -> Data {
        return try loadStub?(path) ?? Data()
    }
}
