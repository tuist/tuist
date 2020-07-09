import Foundation
import TSCBasic
import TuistCore

@testable import TuistLoader

final class MockRome: Romeaging {
    var downloadStub: (([Platform], String?) throws -> Void)?
    var downloadCallCount: UInt = 0
    var missingStub: (([Platform], String?) throws -> String?)?
    var missingCallCount: UInt = 0

    func download(platforms: [Platform], cachePrefix: String?) throws {
        downloadCallCount += 1
        try downloadStub?(platforms, cachePrefix)
    }

    func missing(platforms: [Platform], cachePrefix: String?) throws -> String? {
        missingCallCount += 1
        return try missingStub?(platforms, cachePrefix)
    }
}
