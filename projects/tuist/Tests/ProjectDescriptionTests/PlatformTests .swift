import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class PlatformTests: XCTestCase {
    func test_toJSON() {
        XCTAssertCodableEqualToJson([Platform.iOS], "[\"ios\"]")
        XCTAssertCodableEqualToJson([Platform.macOS], "[\"macos\"]")
        XCTAssertCodableEqualToJson([Platform.watchOS], "[\"watchos\"]")
        XCTAssertCodableEqualToJson([Platform.tvOS], "[\"tvos\"]")
    }
}
