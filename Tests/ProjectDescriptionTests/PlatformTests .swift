import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON() {
        XCTAssertEqual(Platform.iOS.toJSON().toString(), "\"iOS\"")
        XCTAssertEqual(Platform.macOS.toJSON().toString(), "\"macOS\"")
        XCTAssertEqual(Platform.watchOS.toJSON().toString(), "\"watchOS\"")
        XCTAssertEqual(Platform.tvOS.toJSON().toString(), "\"tvOS\"")
    }
}
