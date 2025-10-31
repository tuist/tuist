import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class SettingsMapperTests: XCTestCase {
    // Test that the right combinations end up in the right fields
    // Test that platforms exclude correctly
    // test that platform conflicts combine correctly

    func test_set_defaults() throws {
        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: []
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertTrue(resolvedSettings.isEmpty)
    }

    func test_set_GCC_PREPROCESSOR_DEFINITIONS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .c, name: .define, condition: nil, value: ["C_DEFINE=C_VALUE"]),
            .init(tool: .c, name: .define, condition: nil, value: ["C_DEFINE_2"]),
            .init(tool: .cxx, name: .define, condition: nil, value: ["CXX_DEFINE=CXX_VALUE"]),
            .init(tool: .cxx, name: .define, condition: nil, value: ["CXX_DEFINE_2"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["GCC_PREPROCESSOR_DEFINITIONS"],
            .array([
                "$(inherited)",

                "CXX_DEFINE=CXX_VALUE",
                "CXX_DEFINE_2=1",
                "C_DEFINE=C_VALUE",
                "C_DEFINE_2=1",
            ])
        )
    }

    func test_set_SWIFT_OBJC_INTEROP_MODE_when_cplusplus() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .interoperabilityMode, condition: nil, value: ["Cxx"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["SWIFT_OBJC_INTEROP_MODE"],
            .string("objcxx")
        )
    }

    func test_set_SWIFT_OBJC_INTEROP_MODE_when_c() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .interoperabilityMode, condition: nil, value: ["C"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["SWIFT_OBJC_INTEROP_MODE"],
            .string("objc")
        )
    }

    func test_set_HEADER_SEARCH_PATHS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .c, name: .headerSearchPath, condition: nil, value: ["cPath"]),
            .init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["cxxPath"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["HEADER_SEARCH_PATHS"],

            .array(["$(inherited)", "$(SRCROOT)/path/cPath", "$(SRCROOT)/path/cxxPath"])
        )
    }

    func test_set_SWIFT_ACTIVE_COMPILATION_CONDITIONS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .define, condition: nil, value: ["Define1"]),
            .init(tool: .swift, name: .define, condition: nil, value: ["Define2"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1", "Define2"])
        )
    }

    func test_set_OTHER_CFLAGS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .c, name: .unsafeFlags, condition: nil, value: ["ArbitraryFlag"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_CFLAGS"],
            .array(["$(inherited)", "ArbitraryFlag"])
        )
    }

    func test_set_OTHER_CPLUSPLUSFLAGS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .cxx, name: .unsafeFlags, condition: nil, value: ["ArbitraryFlag"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_CPLUSPLUSFLAGS"],
            .array(["$(inherited)", "ArbitraryFlag"])
        )
    }

    func test_set_OTHER_SWIFT_FLAGS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .unsafeFlags, condition: nil, value: ["ArbitraryFlag"]),
            .init(tool: .swift, name: .enableUpcomingFeature, condition: nil, value: ["NewFeature"]),
            .init(tool: .swift, name: .enableExperimentalFeature, condition: nil, value: ["Experimental"]),
            .init(tool: .swift, name: .swiftLanguageMode, condition: nil, value: ["5"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_SWIFT_FLAGS"],
            .array([
                "$(inherited)",
                "ArbitraryFlag",
                "-enable-upcoming-feature \"NewFeature\"",
                "-enable-experimental-feature \"Experimental\"",
                "-swift-version 5",
            ])
        )
    }

    func test_set_OTHER_LDFLAGS() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["ArbitraryFlag"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_LDFLAGS"],
            .array([
                "$(inherited)",
                "ArbitraryFlag",
            ])
        )
    }

    func test_set_SWIFT_VERSION() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .swiftLanguageMode, condition: nil, value: ["6"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(resolvedSettings["SWIFT_VERSION"], .string("6"))
    }

    func test_set_Combined() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .define, condition: nil, value: ["Define1"]),
            .init(
                tool: .swift,
                name: .define,
                condition: PackageInfo.PackageConditionDescription(platformNames: ["ios", "tvos"], config: nil),
                value: ["Define2"]
            ),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let allPlatformSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            allPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1"])
        )

        let iosPlatformSettings = try mapper.settingsDictionary(for: .iOS)

        XCTAssertEqual(
            iosPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        let combinedSettings = try mapper.mapSettings()

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=appletvos*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=appletvsimulator*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1"])
        )
    }

    func test_set_maccatalyst() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .define, condition: nil, value: ["Define1"]),
            .init(
                tool: .swift,
                name: .define,
                condition: PackageInfo.PackageConditionDescription(platformNames: ["maccatalyst"], config: nil),
                value: ["Define2"]
            ),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let allPlatformSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            allPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1"])
        )

        let iosPlatformSettings = try mapper.settingsDictionary(for: .iOS)

        XCTAssertEqual(
            iosPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        let combinedSettings = try mapper.mapSettings()

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]"],
            .array(["$(inherited)", "Define1", "Define2"])
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .array(["$(inherited)", "Define1"])
        )
    }

    func test_strict_memory_safety_warnings() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .strictMemorySafety, condition: nil, value: ["warnings"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_SWIFT_FLAGS"],
            .array(["$(inherited)", "-strict-memory-safety"])
        )
    }

    func test_strict_memory_safety_errors() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .strictMemorySafety, condition: nil, value: ["errors"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_SWIFT_FLAGS"],
            .array(["$(inherited)", "-strict-memory-safety", "-Werror=StrictMemorySafety"])
        )
    }

    func test_set_OTHER_CFLAGS_with_disableWarning() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .c, name: .disableWarning, condition: nil, value: ["unused-variable"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_CFLAGS"],
            .array(["$(inherited)", "-Wno-unused-variable"])
        )
    }

    func test_set_OTHER_CPLUSPLUSFLAGS_with_disableWarning() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .cxx, name: .disableWarning, condition: nil, value: ["deprecated"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_CPLUSPLUSFLAGS"],
            .array(["$(inherited)", "-Wno-deprecated"])
        )
    }

    func test_set_OTHER_SWIFT_FLAGS_with_disableWarning() throws {
        let settings: [PackageInfo.Target.TargetBuildSettingDescription.Setting] = [
            .init(tool: .swift, name: .disableWarning, condition: nil, value: ["unused-parameter"]),
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionary()

        XCTAssertEqual(
            resolvedSettings["OTHER_SWIFT_FLAGS"],
            .array(["$(inherited)", "-Wno-unused-parameter"])
        )
    }
}

// OTHER_LDFLAGS

extension XcodeGraph.SettingsDictionary {
    func stringValueFor(_ key: String) throws -> String {
        try XCTUnwrap(self[key]?.stringValue)
    }

    func arrayValueFor(_ key: String) throws -> [String] {
        try XCTUnwrap(self[key]?.arrayValue)
    }
}

extension XcodeGraph.SettingValue {
    var stringValue: String? {
        if case let .string(string) = self {
            return string
        } else {
            return nil
        }
    }

    var arrayValue: [String]? {
        if case let .array(array) = self {
            return array
        } else {
            return nil
        }
    }
}

extension PackageInfo.Platform {
    static var ios = PackageInfo.Platform(platformName: "ios", version: "12.0", options: [])
    static var macos = PackageInfo.Platform(platformName: "macos", version: "10.13", options: [])
    static var watchos = PackageInfo.Platform(platformName: "watchos", version: "4.0", options: [])
    static var tvos = PackageInfo.Platform(platformName: "tvos", version: "12.0", options: [])
    static var visionos = PackageInfo.Platform(platformName: "visionos", version: "1.0", options: [])
}
