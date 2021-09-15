import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class ConfigurationNameTests: XCTestCase {
    func test_codable() {
        XCTAssertCodable(ConfigurationName.debug)
        XCTAssertCodable(ConfigurationName.release)
    }
}
