import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class SettingsTests: XCTestCase {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    func test_codable_release_debug() throws {
        // Given
        let debug: Configuration = .debug(
            name: .debug,
            settings: ["debug": .string("debug")],
            xcconfig: "/path/debug.xcconfig"
        )
        let release: Configuration = .release(
            name: .release,
            settings: ["release": .string("release")],
            xcconfig: "/path/release"
        )
        let subject: Settings = .settings(
            base: ["base": .string("base")],
            configurations: [
                debug,
                release,
            ]
        )

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

    func test_codable_config_with_exclusions() throws {
        // Given
        let recommendedSubject = Settings(
            base: [:],
            configurations: [],
            defaultSettings: .recommended(excluding: ["someRecommendedKey", "anotherKey"])
        )
        let essentialSubject = Settings(
            base: [:],
            configurations: [],
            defaultSettings: .essential(excluding: ["someEssentialKey", "anotherKey"])
        )

        // Then
        XCTAssertCodable(recommendedSubject)
        XCTAssertCodable(essentialSubject)
    }

    func test_codable_multi_configs() throws {
        // Given
        let configurations: [Configuration] = [
            .debug(name: .debug),
            .debug(name: "CustomDebug", settings: ["CUSTOM_FLAG": .string("Debug")], xcconfig: "debug.xcconfig"),
            .release(name: .release),
            .release(name: "CustomRelease", settings: ["CUSTOM_FLAG": .string("Release")], xcconfig: "release.xcconfig"),
        ]
        let subject: Settings = .settings(
            base: ["base": .string("base")],
            configurations: configurations
        )

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

    func test_settingsDictionary_chainingMultipleValues() {
        /// Given / When
        let settings = SettingsDictionary()
            .codeSignIdentityAppleDevelopment()
            .currentProjectVersion("999")
            .marketingVersion("1.0.0")
            .automaticCodeSigning(devTeam: "123ABC")
            .appleGenericVersioningSystem()
            .versionInfo("NLR", prefix: "A_Prefix", suffix: "A_Suffix")
            .swiftVersion("5.2.1")
            .otherSwiftFlags("first", "second", "third")
            .bitcodeEnabled(true)
            .debugInformationFormat(.dwarf)
            .swiftActiveCompilationConditions("FIRST", "SECOND", "THIRD")
            .swiftObjcBridgingHeaderPath("/my/bridging/header/path.h")
            .otherCFlags(["$(inherited)", "-my-c-flag"])
            .otherLinkerFlags(["$(inherited)", "-my-linker-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "CODE_SIGN_IDENTITY": "Apple Development",
            "CURRENT_PROJECT_VERSION": "999",
            "MARKETING_VERSION": "1.0.0",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": "123ABC",
            "VERSIONING_SYSTEM": "apple-generic",
            "VERSION_INFO_STRING": "NLR",
            "VERSION_INFO_PREFIX": "A_Prefix",
            "VERSION_INFO_SUFFIX": "A_Suffix",
            "SWIFT_VERSION": "5.2.1",
            "OTHER_SWIFT_FLAGS": "first second third",
            "ENABLE_BITCODE": "YES",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "FIRST SECOND THIRD",
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    func test_settingsDictionary_codeSignManual() {
        /// Given/When
        let settings = SettingsDictionary()
            .manualCodeSigning(identity: "Apple Distribution", provisioningProfileSpecifier: "ABC")

        /// Then
        XCTAssertEqual(settings, [
            "CODE_SIGN_STYLE": "Manual",
            "CODE_SIGN_IDENTITY": "Apple Distribution",
            "PROVISIONING_PROFILE_SPECIFIER": "ABC",
        ])
    }

    func test_settingsDictionary_swiftActiveCompilationConditions() {
        /// Given/When
        let settings = SettingsDictionary()
            .swiftActiveCompilationConditions("FIRST", "SECOND", "THIRD")

        /// Then
        XCTAssertEqual(settings, [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "FIRST SECOND THIRD",
        ])
    }

    func test_settingsDictionary_SwiftCompilationMode() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftCompilationMode(.singlefile)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_COMPILATION_MODE": "singlefile",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftCompilationMode(.wholemodule)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_COMPILATION_MODE": "wholemodule",
        ])
    }

    func test_settingsDictionary_SwiftOptimizationLevel() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizationLevel(.o)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizationLevel(.oNone)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        ])

        /// Given/When
        let settings3 = SettingsDictionary()
            .swiftOptimizationLevel(.oSize)

        /// Then
        XCTAssertEqual(settings3, [
            "SWIFT_OPTIMIZATION_LEVEL": "-Osize",
        ])
    }

    func test_settingsDictionary_swiftObjcBridgingHeaderPath() {
        /// Given/When
        let settings = SettingsDictionary()
            .swiftObjcBridgingHeaderPath("/my/bridging/header/path.h")

        /// Then
        XCTAssertEqual(settings, [
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
        ])
    }

    func test_settingsDictionary_otherCFlags() {
        /// Given/When
        let settings = SettingsDictionary()
            .otherCFlags(["$(inherited)", "-my-c-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
        ])
    }

    func test_settingsDictionary_otherLinkerFlags() {
        /// Given/When
        let settings = SettingsDictionary()
            .otherLinkerFlags(["$(inherited)", "-my-linker-flag"])

        /// Then
        XCTAssertEqual(settings, [
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    func test_settingsDictionary_SwiftOptimizeObjectLifetimes() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(true)

        /// Then
        XCTAssertEqual(settings1, [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "YES",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(false)

        /// Then
        XCTAssertEqual(settings2, [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "NO",
        ])
    }

    func test_settingsDictionary_marketingVersion() {
        /// Given/When
        let settings = SettingsDictionary()
            .marketingVersion("1.0.0")

        /// Then
        XCTAssertEqual(settings, [
            "MARKETING_VERSION": "1.0.0",
        ])
    }

    func test_settingsDictionary_debugInformationFormat() {
        /// Given/When
        let settings1 = SettingsDictionary()
            .debugInformationFormat(.dwarf)

        /// Then
        XCTAssertEqual(settings1, [
            "DEBUG_INFORMATION_FORMAT": "dwarf",
        ])

        /// Given/When
        let settings2 = SettingsDictionary()
            .debugInformationFormat(.dwarfWithDsym)

        /// Then
        XCTAssertEqual(settings2, [
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        ])
    }
}
