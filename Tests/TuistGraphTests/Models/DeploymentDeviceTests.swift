import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DeploymentDeviceTests: TuistUnitTestCase {
    func test_codable_iphone() {
        // Given
        let subject = DeploymentDevice.iphone

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_mac() {
        // Given
        let subject = DeploymentDevice.mac

        // Then
        XCTAssertCodable(subject)
    }
}
