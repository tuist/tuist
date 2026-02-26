import Foundation
import Path
import XCTest
@testable import XcodeGraph

final class PackageTests: XCTestCase {
    func test_codable_local() throws {
        // Given
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/workspace"))

        // Then
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
