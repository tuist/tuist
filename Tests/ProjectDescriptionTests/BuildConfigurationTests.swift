import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class BuildConfigurationTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_defaultDebug() {
        // Given
        let subject: BuildConfiguration = .debug

        // When / Then
        XCTAssertEqual(subject.name, "Debug")
        XCTAssertEqual(subject.variant, .debug)
    }

    func test_defaultRelease() {
        // Given
        let subject: BuildConfiguration = .release

        // When / Then
        XCTAssertEqual(subject.name, "Release")
        XCTAssertEqual(subject.variant, .release)
    }

    func test_customDebug() {
        // Given
        let subject: BuildConfiguration = .debug(name: "CustomDebug")

        // When / Then
        XCTAssertEqual(subject.name, "CustomDebug")
        XCTAssertEqual(subject.variant, .debug)
    }

    func test_customRelease() {
        // Given
        let subject: BuildConfiguration = .release(name: "CustomRelease")

        // When / Then
        XCTAssertEqual(subject.name, "CustomRelease")
        XCTAssertEqual(subject.variant, .release)
    }

    func test_codable() throws {
        // Given
        let subject: BuildConfiguration = .release(name: "CustomRelease")

        // When
        let data = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(BuildConfiguration.self, from: data)
        XCTAssertEqual(decoded, subject)
    }
}
