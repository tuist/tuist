import Foundation
@testable import ProjectDescription
import XCTest

final class TargetQueryTests: XCTestCase {
    func test_toJSON() throws {
        let queries: [TargetQuery] = [
            "A",
            .tagged("foo"),
            "tag:bar",
        ]
        XCTAssertCodable(queries)
    }
}
