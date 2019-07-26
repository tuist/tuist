import Basic
import Foundation
import XCTest
import TuistCoreTesting
@testable import TuistGenerator

final class ConfigurationTests: XCTestCase {
    func testEquals() {
        XCTAssertEqual(Configuration(settings: [:], xcconfig: nil),
                       Configuration(settings: [:], xcconfig: nil))

        XCTAssertEqual(Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A")),
                       Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A")))

        XCTAssertNotEqual(Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A")),
                          Configuration(settings: ["A": "A_new"], xcconfig: AbsolutePath("/A")))

        XCTAssertNotEqual(Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A")),
                          Configuration(settings: ["A": "A", "B": "B"], xcconfig: AbsolutePath("/A")))

        XCTAssertNotEqual(Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A")),
                          Configuration(settings: ["A": "A"], xcconfig: AbsolutePath("/A_new")))
    }
}

final class SettingsTests: XCTestCase {
    func testEquals() {
        XCTAssertEqual(Settings(base: [:], configurations: [:]),
                       Settings(base: [:], configurations: [:]))

        XCTAssertEqual(Settings(base: ["A": "A"],
                                configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]),
                       Settings(base: ["A": "A"],
                                configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]))

        XCTAssertNotEqual(Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]),
                          Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B_new"], xcconfig: AbsolutePath("/B"))]))

        XCTAssertNotEqual(Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]),
                          Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B_new"], xcconfig: AbsolutePath("/B"))]))

        XCTAssertNotEqual(Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]),
                          Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B_new"))]))

        XCTAssertNotEqual(Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B"))]),
                          Settings(base: ["A": "A"],
                                   configurations: [.debug: Configuration(settings: ["B": "B"], xcconfig: AbsolutePath("/B")),
                                                    .release: nil]))
    }

    func testXcconfigs() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            BuildConfiguration(name: "D", variant: .debug): Configuration(settings: [:], xcconfig: AbsolutePath("/D")),
            .release("C"): nil,
            .debug("A"): Configuration(settings: [:], xcconfig: AbsolutePath("/A")),
            .release("B"): Configuration(settings: [:], xcconfig: AbsolutePath("/B")),
        ]

        // When
        let got = configurations.xcconfigs()

        // Then
        XCTAssertEqual(got.map { $0.pathString }, ["/A", "/B", "/D"])
    }

    func testSortedByBuildConfigurationName() {
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
        XCTAssertEqual(got.map { $0.0.name }, ["A", "B", "C", "D"])
    }

    func testDefaultDebugConfigurationWhenDefaultExists() {
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
        XCTAssertEqual(got, .debug)
    }

    func testDefaultDebugConfigurationWhenDefaultDoesNotExist() {
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
        XCTAssertEqual(got, .debug("A"))
    }

    func testDefaultDebugConfigurationWhenNoDebugConfigurationsExist() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            .release("C"): nil,
            .release("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultDebugBuildConfiguration()

        // Then
        XCTAssertNil(got)
    }

    func testDefaultReleaseConfigurationWhenDefaultExist() {
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
        XCTAssertEqual(got, .release)
    }

    func testDefaultReleaseConfigurationWhenDefaultDoesNotExist() {
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
        XCTAssertEqual(got, .release("B"))
    }

    func testDefaultReleaseConfigurationWhenNoReleaseConfigurationsExist() {
        // Given
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug("A"): nil,
            .debug("B"): nil,
        ]
        let settings = Settings(configurations: configurations)

        // When
        let got = settings.defaultReleaseBuildConfiguration()

        // Then
        XCTAssertNil(got)
    }

    // MARK: - Helpers

    private func emptyConfiguration() -> Configuration {
        return Configuration(settings: [:], xcconfig: nil)
    }
}

final class ConfigurationValueTests: XCTestCase {

    func testToAny() {
        // Given
        let buildConfig: [String: Configuration.Value] = [
            "A": ["A_VALUE_1", "A_VALUE_2"],
            "B": "B_VALUE",
            "C": ["C_VALUE"]
        ]
        let expected: [String: Any] = [
            "A": ["A_VALUE_1", "A_VALUE_2"],
            "B": "B_VALUE",
            "C": ["C_VALUE"]
        ]

        // When
        let got = buildConfig.toAny()

        // Then
        XCTAssertEqualDictionaries(got, expected)
    }
}
