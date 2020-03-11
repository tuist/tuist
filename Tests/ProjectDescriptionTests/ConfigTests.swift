import Foundation
import XCTest
@testable import ProjectDescription

final class ConfigTests: XCTestCase {
    func test_config_toJSON() throws {
        let config = Config(generationOptions:
            [.xcodeProjectName("someprefix-\(.projectName)")])

        XCTAssertCodable(config)
    }
}
