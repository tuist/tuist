import Foundation
import Testing

@testable import TuistCore
@testable import TuistTesting

struct SimulatorRuntimeVersionTests {
    @Test func test_description_when_only_major() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2)

        // Then
        #expect(version.description == "2")
    }

    @Test func test_description_when_major_and_minor() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2, minor: 3)

        // Then
        #expect(version.description == "2.3")
    }

    @Test func test_description_when_major_minor_and_patch() {
        // Given
        let version = SimulatorRuntimeVersion(major: 2, minor: 3, patch: 4)

        // Then
        #expect(version.description == "2.3.4")
    }

    @Test func test_equal_when_they_are_equal() {
        // Given
        let first = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        let second = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)

        // Then
        #expect(first == second)
    }

    @Test func test_equal_when_they_are_not_equal() {
        // Given
        let first = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        let second = SimulatorRuntimeVersion(major: 3, minor: 3, patch: 1)

        // Then
        #expect(first != second)
    }

    @Test func test_expressible_by_string_literal() {
        // Given
        let first: SimulatorRuntimeVersion = "3.2.1"
        let second = SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)

        // Then
        #expect(first == second)
    }

    @Test func test_flattened() {
        // Given
        let version: SimulatorRuntimeVersion = "3"

        // Then
        #expect(version.minor == nil)
        #expect(version.patch == nil)
        #expect(version.flattened().minor == 0)
        #expect(version.flattened().patch == 0)
    }

    @Test func test_comparable() {
        #expect(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        #expect(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <=
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        #expect(
            SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1) <=
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 1)
        )
        #expect(
            SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) >
                SimulatorRuntimeVersion(major: 3, minor: 2, patch: 2)
        )
        #expect(
            SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) >
                SimulatorRuntimeVersion(major: 4, minor: 1, patch: 2)
        )
        #expect(
            !(SimulatorRuntimeVersion(major: 4, minor: 2, patch: 1) <
                SimulatorRuntimeVersion(major: 4, minor: 1, patch: 2))
        )
    }
}
