import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SettingsTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable_release_debug() throws {
        // Given
        let debug = Configuration(settings: ["debug": .string("debug")],
                                  xcconfig: "/path/debug.xcconfig")
        let release = Configuration(settings: ["release": .string("release")],
                                    xcconfig: "/path/release")
        let subject = Settings(base: ["base": .string("base")],
                               debug: debug,
                               release: release)

        // When
        let data = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Settings.self, from: data)
        XCTAssertEqual(decoded, subject)
        XCTAssertEqual(decoded.configurations.map(\.name), [
            "Debug",
            "Release",
        ])
    }

    func test_codable_multi_configs() throws {
        // Given
        let configurations: [CustomConfiguration] = [
            .debug(name: "Debug"),
            .debug(name: "CustomDebug", settings: ["CUSTOM_FLAG": .string("Debug")], xcconfig: "debug.xcconfig"),
            .release(name: "Release"),
            .release(name: "CustomRelease", settings: ["CUSTOM_FLAG": .string("Release")], xcconfig: "release.xcconfig"),
        ]
        let subject = Settings(base: ["base": .string("base")],
                               configurations: configurations)

        // When
        let data = try encoder.encode(subject)

        // Then
        let decoded = try decoder.decode(Settings.self, from: data)
        XCTAssertEqual(decoded, subject)
        XCTAssertEqual(decoded.configurations.map(\.name), [
            "Debug",
            "CustomDebug",
            "Release",
            "CustomRelease",
        ])
    }
}
