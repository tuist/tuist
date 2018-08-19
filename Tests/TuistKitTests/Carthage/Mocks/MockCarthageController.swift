import Foundation
@testable import TuistKit

final class MockCarthageController: CarthageControlling {
    var updateIfNecessaryCount: UInt = 0
    var updateIfNecessaryStub: ((Graphing) throws -> Void)?

    func updateIfNecessary(graph: Graphing) throws {
        updateIfNecessaryCount += 1
        try updateIfNecessaryStub?(graph)
    }
}
