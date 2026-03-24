import Foundation
import Testing
import TuistTesting

@testable import ProjectDescription

struct SettingsTests {
    private var encoder = JSONEncoder()
    private var decoder = JSONDecoder()

    @Test func codable_release_debug() throws {
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
        #expect(decoded == subject)
        #expect(decoded.configurations.map(\.name) == [
            "Debug",
            "Release",
        ])
    }

    @Test func codable_config_with_exclusions() throws {
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
        #expect(try isCodableRoundTripable(recommendedSubject))
        #expect(try isCodableRoundTripable(essentialSubject))
    }

    @Test func codable_multi_configs() throws {
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
        #expect(decoded == subject)
        #expect(decoded.configurations.map(\.name) == [
            "Debug",
            "CustomDebug",
            "Release",
            "CustomRelease",
        ])
    }

    @Test func settingsDictionary_chainingMultipleValues() {
        // Given / When
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

        // Then
        #expect(settings == [
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
            "OTHER_SWIFT_FLAGS": ["first", "second", "third"],
            "ENABLE_BITCODE": "YES",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["FIRST", "SECOND", "THIRD"],
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    @Test func settingsDictionary_codeSignManual() {
        // Given/When
        let settings = SettingsDictionary()
            .manualCodeSigning(identity: "Apple Distribution", provisioningProfileSpecifier: "ABC")

        // Then
        #expect(settings == [
            "CODE_SIGN_STYLE": "Manual",
            "CODE_SIGN_IDENTITY": "Apple Distribution",
            "PROVISIONING_PROFILE_SPECIFIER": "ABC",
        ])
    }

    @Test func settingsDictionary_otherSwiftFlags() {
        // Given/When
        let settingsVariadic = SettingsDictionary()
            .otherSwiftFlags("FIRST", "SECOND", "THIRD")

        let settingsArray = SettingsDictionary()
            .otherSwiftFlags(["FIRST", "SECOND", "THIRD"])

        // Then
        #expect(settingsVariadic == [
            "OTHER_SWIFT_FLAGS": ["FIRST", "SECOND", "THIRD"],
        ])

        #expect(settingsArray == [
            "OTHER_SWIFT_FLAGS": ["FIRST", "SECOND", "THIRD"],
        ])

        #expect(settingsVariadic == settingsArray)
    }

    @Test func settingsDictionary_swiftActiveCompilationConditions() {
        // Given/When
        let settingsVariadic = SettingsDictionary()
            .swiftActiveCompilationConditions("FIRST", "SECOND", "THIRD")

        let settingsArray = SettingsDictionary()
            .swiftActiveCompilationConditions(["FIRST", "SECOND", "THIRD"])

        // Then
        #expect(settingsVariadic == [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["FIRST", "SECOND", "THIRD"],
        ])

        #expect(settingsArray == [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["FIRST", "SECOND", "THIRD"],
        ])

        #expect(settingsVariadic == settingsArray)
    }

    @Test func settingsDictionary_SwiftCompilationMode() {
        // Given/When
        let settings1 = SettingsDictionary()
            .swiftCompilationMode(.singlefile)

        // Then
        #expect(settings1 == [
            "SWIFT_COMPILATION_MODE": "singlefile",
        ])

        // Given/When
        let settings2 = SettingsDictionary()
            .swiftCompilationMode(.wholemodule)

        // Then
        #expect(settings2 == [
            "SWIFT_COMPILATION_MODE": "wholemodule",
        ])
    }

    @Test func settingsDictionary_SwiftOptimizationLevel() {
        // Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizationLevel(.o)

        // Then
        #expect(settings1 == [
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
        ])

        // Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizationLevel(.oNone)

        // Then
        #expect(settings2 == [
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        ])

        // Given/When
        let settings3 = SettingsDictionary()
            .swiftOptimizationLevel(.oSize)

        // Then
        #expect(settings3 == [
            "SWIFT_OPTIMIZATION_LEVEL": "-Osize",
        ])
    }

    @Test func settingsDictionary_swiftObjcBridgingHeaderPath() {
        // Given/When
        let settings = SettingsDictionary()
            .swiftObjcBridgingHeaderPath("/my/bridging/header/path.h")

        // Then
        #expect(settings == [
            "SWIFT_OBJC_BRIDGING_HEADER": "/my/bridging/header/path.h",
        ])
    }

    @Test func settingsDictionary_otherCFlags() {
        // Given/When
        let settings = SettingsDictionary()
            .otherCFlags(["$(inherited)", "-my-c-flag"])

        // Then
        #expect(settings == [
            "OTHER_CFLAGS": ["$(inherited)", "-my-c-flag"],
        ])
    }

    @Test func settingsDictionary_otherLinkerFlags() {
        // Given/When
        let settings = SettingsDictionary()
            .otherLinkerFlags(["$(inherited)", "-my-linker-flag"])

        // Then
        #expect(settings == [
            "OTHER_LDFLAGS": ["$(inherited)", "-my-linker-flag"],
        ])
    }

    @Test func settingsDictionary_SwiftOptimizeObjectLifetimes() {
        // Given/When
        let settings1 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(true)

        // Then
        #expect(settings1 == [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "YES",
        ])

        // Given/When
        let settings2 = SettingsDictionary()
            .swiftOptimizeObjectLifetimes(false)

        // Then
        #expect(settings2 == [
            "SWIFT_OPTIMIZE_OBJECT_LIFETIME": "NO",
        ])
    }

    @Test func settingsDictionary_marketingVersion() {
        // Given/When
        let settings = SettingsDictionary()
            .marketingVersion("1.0.0")

        // Then
        #expect(settings == [
            "MARKETING_VERSION": "1.0.0",
        ])
    }

    @Test func settingsDictionary_debugInformationFormat() {
        // Given/When
        let settings1 = SettingsDictionary()
            .debugInformationFormat(.dwarf)

        // Then
        #expect(settings1 == [
            "DEBUG_INFORMATION_FORMAT": "dwarf",
        ])

        // Given/When
        let settings2 = SettingsDictionary()
            .debugInformationFormat(.dwarfWithDsym)

        // Then
        #expect(settings2 == [
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        ])
    }
}
