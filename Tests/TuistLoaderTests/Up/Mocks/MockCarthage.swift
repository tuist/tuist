import Foundation
import TSCBasic
import TuistCore
import TuistGraph

@testable import TuistLoader

final class MockCarthage: Carthaging {
    var outdatedStub: ((AbsolutePath) throws -> [String]?)?
    var outdatedCallCount: UInt = 0
    var bootstrapStub: ((AbsolutePath, [Platform], Bool,  [String]) throws -> Void)?
    var bootstrapCallCount: UInt = 0

    func outdated(path: AbsolutePath) throws -> [String]? {
        outdatedCallCount += 1
        return try outdatedStub?(path) ?? nil
    }

    func bootstrap(
        path: AbsolutePath,
        platforms: [Platform],
        useXCFrameworks: Bool,
        dependencies: [String]
    ) throws {
        bootstrapCallCount += 1
        try bootstrapStub?(path, platforms, useXCFrameworks, dependencies)
    }
}
