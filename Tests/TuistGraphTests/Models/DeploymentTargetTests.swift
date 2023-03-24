import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DeploymentTargetTests: TuistUnitTestCase {
    func test_codable_iOS() {
        // Given
        let subject = DeploymentTarget.iOS("12.1", [.iphone, .mac], supportsMacDesignedForIOS: true)

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_tvOS() {
        // Given
        let subject = DeploymentTarget.tvOS("13.2.1")

        // Then
        XCTAssertCodable(subject)
    }
}
