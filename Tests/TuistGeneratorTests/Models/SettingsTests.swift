import Basic
import Foundation
import XCTest
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

    // MARK: - Helpers

    private func emptyConfiguration() -> Configuration {
        return Configuration(settings: [:], xcconfig: nil)
    }
}
