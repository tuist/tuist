import Foundation
import XCTest
@testable import ProjectDescription

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
