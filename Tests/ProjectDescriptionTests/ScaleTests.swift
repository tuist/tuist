import Foundation
import XCTest
@testable import ProjectDescription

final class ScaleTests: XCTestCase {
    func test_config_toJSON() throws {
        let scale = Scale(url: "https://tuist.io", projectId: "123", options: [.insights])
        XCTAssertCodable(scale)
    }
}
