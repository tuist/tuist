import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON() {
        assertCodableEqualToJson([Platform.iOS], "[\"iOS\"]")
        assertCodableEqualToJson([Platform.macOS], "[\"macOS\"]")
        assertCodableEqualToJson([Platform.watchOS], "[\"watchOS\"]")
        assertCodableEqualToJson([Platform.tvOS], "[\"tvOS\"]")
    }
}
