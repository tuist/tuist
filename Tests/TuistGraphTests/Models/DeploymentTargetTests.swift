import Foundation
import XCTest

@testable import TuistGraph
@testable import TuistSupportTesting

final class DeploymentTargetTests: TuistUnitTestCase {
    func test_codable_iOS() {
        // Given
        let subject = DeploymentTargets.iOS("12.1")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_macOS() {
        // Given
        let subject = DeploymentTargets.macOS("10.6")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_watchOS() {
        // Given
        let subject = DeploymentTargets.watchOS("9.3")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_tvOS() {
        // Given
        let subject = DeploymentTargets.tvOS("13.2.1")

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_many_OS() {
        // Given
        let subject = DeploymentTargets(iOS: "12.1", macOS: "10.6", watchOS: "9.3", tvOS: "13.2.1")

        // Then
        XCTAssertCodable(subject)
    }
}
