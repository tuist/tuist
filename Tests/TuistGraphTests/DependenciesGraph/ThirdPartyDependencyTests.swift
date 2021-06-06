import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class ThirdPartyDependencyTests: TuistUnitTestCase {
    func test_codable_xcframework() {
        // Given
        let subject = ThirdPartyDependency.testXCFramework(
            architectures: [.arm64, .i386, .arm6432]
        )

        // Then
        XCTAssertCodable(subject)
    }
}
