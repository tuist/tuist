import Foundation
import Path
import Testing
@testable import XcodeGraph

struct PackageTests {
    @Test func test_codable_local() throws {
        // Given
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/workspace"))

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Package.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_codable_remote() throws {
        // Given
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Package.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_is_remote_local() throws {
        // Given
        let subject = Package.local(path: try AbsolutePath(validating: "/path/to/package"))

        // Then
        #expect(!subject.isRemote)
    }

    @Test func test_is_remote_remote() {
        // Given
        let subject = Package.remote(
            url: "/url/to/package",
            requirement: .branch("branch")
        )

        // Then
        #expect(subject.isRemote)
    }
}
