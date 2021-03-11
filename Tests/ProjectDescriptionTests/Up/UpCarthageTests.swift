import Foundation
import XCTest

@testable import ProjectDescription
@testable import TuistSupportTesting

final class UpCarthageTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = UpCarthage(platforms: [.iOS, .macOS], useXCFrameworks: true, noUseBinaries: true)

        // When / Then
        XCTAssertCodable(subject)
    }
}
