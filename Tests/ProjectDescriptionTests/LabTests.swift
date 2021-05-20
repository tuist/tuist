import Foundation
import XCTest
@testable import ProjectDescription

final class LabTests: XCTestCase {
    func test_config_toJSON() throws {
        let cloud = Lab(url: "https://lab.tuist.io", projectId: "123", options: [.insights])
        XCTAssertCodable(cloud)
    }
}
