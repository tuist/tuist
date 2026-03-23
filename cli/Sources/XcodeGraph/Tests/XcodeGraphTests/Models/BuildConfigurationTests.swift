import Foundation
import Testing
@testable import XcodeGraph

struct BuildConfigurationTests {
    @Test func test_codable() throws {
        // Given
        let subject = BuildConfiguration(
            name: "Debug",
            variant: .debug
        )

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(BuildConfiguration.self, from: data)
        #expect(subject == decoded)
    }

    @Test func test_name_returnsTheRightValue_whenDebug() {
        #expect(BuildConfiguration.debug.name == "Debug")
    }

    @Test func test_name_returnsTheRightValue_whenRelease() {
        #expect(BuildConfiguration.release.name == "Release")
    }

    @Test func test_hashValue() {
        #expect(BuildConfiguration(name: "Debug", variant: .debug).hashValue == BuildConfiguration(name: "Debug", variant: .debug).hashValue)
        #expect(BuildConfiguration(name: "Debug", variant: .debug).hashValue == BuildConfiguration.debug.hashValue)
        #expect(BuildConfiguration(name: "debug", variant: .debug).hashValue == BuildConfiguration.debug.hashValue)
        #expect(BuildConfiguration(name: "Debug", variant: .debug).hashValue != BuildConfiguration.release.hashValue)
        #expect(BuildConfiguration(name: "debug", variant: .debug).hashValue != BuildConfiguration.release.hashValue)
    }
}
