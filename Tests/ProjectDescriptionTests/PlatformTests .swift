import Foundation
import XCTest
@testable import ProjectDescription

final class PlatformTests: XCTestCase {
    func test_toJSON() {
        assertCodableEqualToJson([Platform.iOS], "[\"ios\"]")
        assertCodableEqualToJson([Platform.macOS], "[\"macos\"]")
        assertCodableEqualToJson([Platform.watchOS], "[\"watchos\"]")
        assertCodableEqualToJson([Platform.tvOS], "[\"tvos\"]")
    }
}
