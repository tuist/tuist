import Foundation
import XCTest

@testable import TuistGenerator

final class DotGraphNodeAttributeTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(DotGraphNodeAttribute.label("test").description, "label=\"test\"")
        XCTAssertEqual(DotGraphNodeAttribute.shape(.box).description, "shape=\"box\"")
    }
}
