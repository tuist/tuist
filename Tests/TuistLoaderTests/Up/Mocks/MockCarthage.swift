import Basic
import Foundation
import TuistCore

@testable import TuistLoader

final class MockCarthage: Carthaging {
    var outdatedStub: ((AbsolutePath) throws -> [String]?)?
    var outdatedCallCount: UInt = 0
    var updateStub: ((AbsolutePath, [Platform], [String]) throws -> Void)?
    var updateCallCount: UInt = 0

    func outdated(path: AbsolutePath) throws -> [String]? {
        outdatedCallCount += 1
        return try outdatedStub?(path) ?? nil
    }

    func update(path: AbsolutePath, platforms: [Platform], dependencies: [String]) throws {
        updateCallCount += 1
        try updateStub?(path, platforms, dependencies)
    }
}
