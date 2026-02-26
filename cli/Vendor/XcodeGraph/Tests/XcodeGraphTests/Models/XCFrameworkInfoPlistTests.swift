import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class XCFrameworkInfoPlistTests: XCTestCase {
    func test_codable() {
        // Given
        let subject: XCFrameworkInfoPlist = .test()

        // Then
        XCTAssertCodable(subject)
    }
}
