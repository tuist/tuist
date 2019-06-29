import Foundation
import XCTest

@testable import TuistGenerator

final class DotGraphNodeTests: XCTestCase {
    func test_description() {
        let subject = DotGraphNode(name: "node",
                                   attributes: Set(arrayLiteral: .label("carthage framework")))
        XCTAssertEqual(subject.description, "node [label=\"carthage framework\"]")
    }
}
