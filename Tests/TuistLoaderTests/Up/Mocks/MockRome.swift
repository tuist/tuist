import Foundation
import TSCBasic
import TuistCore

@testable import TuistLoader

final class MockRome: Romeaging {
    var downloadStub: (([Platform], String?) throws -> Void)?
    var downloadCallCount: UInt = 0

    func download(platforms: [Platform], cachePrefix: String?) throws {
        downloadCallCount += 1
        try downloadStub?(platforms, cachePrefix)
    }
}
