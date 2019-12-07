import Foundation
import XCTest
import TuistCoreTesting
import TuistCore

@testable import TuistKit


final class GraphContentHasherTests: XCTestCase {
    func test_contentHashes() {
        let graph = Graph.test()
        let sut = GraphContentHasher()
        let result = sut.contentHashes(for: graph)
        XCTAssertEqual(result, Dictionary())
    }
}
