import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class PackageTests: XCTestCase {
    private enum LegacyPackage: Codable {
        case remote(url: String, requirement: Requirement)
        case local(path: AbsolutePath)
    }

    func test_codable_local() throws {
        // Given
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/workspace"))

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_local_with_traits() throws {
        let subject = Package.local(
            path: try AbsolutePath(validating: "/path/to/workspace"),
            traits: ["Feature"]
        )

        XCTAssertCodable(subject)
    }

    func test_codable_remote() {
        // Given
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_remote_with_traits() {
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch"),
            traits: ["Feature"]
        )

        XCTAssertCodable(subject)
    }

    func test_codable_without_traits_preserves_legacy_representation() throws {
        let path = try AbsolutePath(validating: "/path/to/workspace")
        let encoder = JSONEncoder()
        let packageData = try encoder.encode(Package.local(path: path))
        let legacyData = try encoder.encode(LegacyPackage.local(path: path))

        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: packageData) as? NSDictionary,
            try JSONSerialization.jsonObject(with: legacyData) as? NSDictionary
        )
        XCTAssertEqual(try JSONDecoder().decode(Package.self, from: legacyData), .local(path: path))
    }

    func test_identity_is_normalized() throws {
        XCTAssertEqual(
            Package.local(path: try AbsolutePath(validating: "/path/to/Package")).identity,
            "package"
        )
        XCTAssertEqual(
            Package.remote(url: "https://example.com/Package.git", requirement: .branch("main")).identity,
            "package"
        )
    }

    func test_is_remote_local() throws {
        // Given
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/package"))

        // Then
        XCTAssertFalse(subject.isRemote)
    }

    func test_is_remote_remote() {
        // Given
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        // Then
        XCTAssertTrue(subject.isRemote)
    }
}
