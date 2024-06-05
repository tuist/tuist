import Foundation
import XCTest

@testable import TuistSupportTesting
@testable import XcodeGraph

final class CoreDataModelTests: TuistUnitTestCase {
    func test_codable() {
        // Given
        let subject = CoreDataModel(
            path: "/path/to/model",
            versions: [
                "/path/to/version",
            ],
            currentVersion: "1.1.1"
        )

        // Then
        XCTAssertCodable(subject)
    }
}
