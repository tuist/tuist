import Foundation
import XCTest

@testable import TuistKit

final class MockGraphUp: GraphUpping {
    var isMetStub: ((Graph) throws -> Bool)?
    var meetStub: ((Graph) throws -> Void)?

    func isMet(graph: Graph) throws -> Bool {
        return try isMetStub?(graph) ?? false
    }

    func meet(graph: Graph) throws {
        try meetStub?(graph)
    }
}
