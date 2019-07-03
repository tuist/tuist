import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class PlatformTests: XCTestCase {
    func test_toJSON() {
        XCTAssertCodableEqualToJson([Platform.iOS], "[1]")
        XCTAssertCodableEqualToJson([Platform.macOS], "[2]")
        XCTAssertCodableEqualToJson([Platform.watchOS], "[4]")
        XCTAssertCodableEqualToJson([Platform.tvOS], "[8]")
    }
}
