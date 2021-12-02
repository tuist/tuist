import Foundation
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class SimulatorRuntimeVersionTests: TuistUnitTestCase {
    func test_description_when_only_major() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2)

        // Then
        XCTAssertEqual(version.description, "2")
    }

    func test_description_when_major_and_minor() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2, minor: 3)

        // Then
        XCTAssertEqual(version.description, "2.3")
    }

    func test_description_when_major_minor_and_patch() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2, minor: 3, patch: 4)

        // Then
        XCTAssertEqual(version.description, "2.3.4")
    }

    func test_equal_when_they_are_equal() {
        // Given
        let first = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        let second = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)

        // Then
        XCTAssertEqual(first, second)
    }

    func test_equal_when_they_are_not_equal() {
        // Given
        let first = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        let second = SimulatorRuntimeVersion(major: 3, minor: 3, patch: 1)

        // Then
        XCTAssertNotEqual(first, second)
    }

    func test_expressible_by_string_literal() {
        // Given
        let first: SimulatorRuntimeVersion = "3.2.1"
        let second = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)

        // Then
        XCTAssertEqual(first, second)
    }

    func test_flattened() {
        // Given
        let version: SimulatorRuntimeVersion = "3"

        // Then
        XCTAssertNil(version.minor)
        XCTAssertNil(version.patch)
        XCTAssertEqual(version.flattened().minor, 0)
        XCTAssertEqual(version.flattened().patch, 0)
    }

    func test_comparable() {
        XCTAssertTrue(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        XCTAssertTrue(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <=
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        XCTAssertTrue(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <=
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        )
        XCTAssertTrue(
            SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) >
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        XCTAssertTrue(
            SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) >
                SimulatorRuntimeVersion(major: 4, minor: 1, patch: 2)
        )
        XCTAssertFalse(
            SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) <
                SimulatorRuntimeVersion(major: 4, minor: 1, patch: 2)
        )
    }
}
