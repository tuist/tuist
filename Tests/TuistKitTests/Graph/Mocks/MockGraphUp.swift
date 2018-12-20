import Foundation
import XCTest

@testable import TuistKit

final class MockGraphUp: GraphUpping {
    var isMetStub: ((Graph) throws -> Bool)?
    var isMetCallCount: UInt = 0
    var meetStub: ((Graph) throws -> Void)?
    var meetCallCount: UInt = 0

    func isMet(graph: Graph) throws -> Bool {
        isMetCallCount += 1
        return try isMetStub?(graph) ?? false
    }

    func meet(graph: Graph) throws {
        meetCallCount += 1
        try meetStub?(graph)
    }
}
