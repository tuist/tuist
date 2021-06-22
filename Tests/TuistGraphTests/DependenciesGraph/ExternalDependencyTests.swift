import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ExternalDependencyTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = ExternalDependency.testXCFramework(
            architectures: [.arm64, .i386, .arm6432]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
