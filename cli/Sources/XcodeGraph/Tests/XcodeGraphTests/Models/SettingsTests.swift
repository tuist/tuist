import Foundation
import Path
import Testing
@testable import XcodeGraph

struct SettingsTests {
    @Test func test_codable() throws {
        // Given
        let subject = Settings.default

        // Then
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subject)
        let decoded = try decoder.decode(Settings.self, from: data)
        #expect(subject == decoded)
    }

    @Test func testXcconfigs() throws {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            BuildConfiguration(name: "D", variant: .debug): Configuration(
                settings: [:],
                xcconfig: try AbsolutePath(validating: "/D")
            ),
            .release("C"): nil,
            .debug("A"): Configuration(settings: [:], xcconfig: try AbsolutePath(validating: "/A")),
            .release("B"): Configuration(settings: [:], xcconfig: try AbsolutePath(validating: "/B")),
        ]

        // When
        let got = configurations.xcconfigs()

        // Then
        #expect(got.map(\.pathString) == ["/A", "/B", "/D"])
    }

    @Test func testSortedByBuildConfigurationName() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            BuildConfiguration(name: "D", variant: .debug): emptyConfiguration(),
            .release("C"): nil,
            .debug("A"): nil,
            .release("B"): emptyConfiguration(),
        ]

        // When
        let got = configurations.sortedByBuildConfigurationName()

        // Then
        #expect(got.map(\.0.name) == ["A", "B", "C", "D"])
    }

    @Test func testDefaultDebugConfigurationWhenDefaultExists() {
        // Given
        // .debug (i.e. name: "Debug", variant: .debug) is the default debug
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .debug("A"): nil,
            .release("B"): nil,
            .debug: nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultDebugBuildConfiguration()

        // Then
        #expect(got == .debug)
    }

    @Test func testDefaultDebugConfigurationWhenDefaultDoesNotExist() {
        // Given
        // .debug (i.e. name: "Debug", variant: .debug) is the default debug
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .debug("A"): nil,
            .release("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultDebugBuildConfiguration()

        // Then
        #expect(got == .debug("A"))
    }

    @Test func testDefaultDebugConfigurationWhenNoDebugConfigurationsExist() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .release("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultDebugBuildConfiguration()

        // Then
        #expect(got == nil)
    }

    @Test func testDefaultReleaseConfigurationWhenDefaultExist() {
        // Given
        // .release (i.e. name: "Release", variant: .release) is the default release
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .debug("A"): nil,
            .release("B"): nil,
            .release: nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultReleaseBuildConfiguration()

        // Then
        #expect(got == .release)
    }

    @Test func testDefaultReleaseConfigurationWhenDefaultDoesNotExist() {
        // Given
        // .release (i.e. name: "Release", variant: .release) is the default release
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .debug("A"): nil,
            .release("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultReleaseBuildConfiguration()

        // Then
        #expect(got == .release("B"))
    }

    @Test func testDefaultReleaseConfigurationWhenNoReleaseConfigurationsExist() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug("A"): nil,
            .debug("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultReleaseBuildConfiguration()

        // Then
        #expect(got == nil)
    }

    // MARK: - Helpers

    private func emptyConfiguration() -> Configuration {
        Configuration(settings: [:], xcconfig: nil)
    }
}
