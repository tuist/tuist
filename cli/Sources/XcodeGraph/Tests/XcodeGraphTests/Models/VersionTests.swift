import Foundation
import Testing
import XcodeGraph

struct VersionTests {
    @Test func test_xcodeStringValue() {
        // Given
        let version = Version(stringLiteral: "1.2.3")

        // When
        let got = version.xcodeStringValue

        // Then
        #expect(got == "123")
    }

    @Test func codable() throws {
        // Given
        let version = Version(stringLiteral: "1.2.3")

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(version)
        let decoded = try decoder.decode(Version.self, from: data)
        #expect(version == decoded)
    }
}
