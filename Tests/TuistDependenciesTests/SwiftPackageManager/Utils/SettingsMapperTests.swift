import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class SettingsMapperTests: XCTestCase {
    // Test that the right combintations end up in the right fields
    // Test that platforms exclude correctly
    // test that platform conflicts combine correctly
    func test_set_defaults() throws {
        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: []
        )

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(resolvedSettings, [
            "GCC_PREPROCESSOR_DEFINITIONS": .array(["$(inherited)",
                                                    "SWIFT_PACKAGE=1",
                ]),
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .string("$(inherited) SWIFT_PACKAGE"),
        ])
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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(
            resolvedSettings["GCC_PREPROCESSOR_DEFINITIONS"],
            .array([
                "$(inherited)",

                "CXX_DEFINE=CXX_VALUE",
                "CXX_DEFINE_2=1",
                "C_DEFINE=C_VALUE",
                "C_DEFINE_2=1",
                "SWIFT_PACKAGE=1",
            ])
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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(
            resolvedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

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
        ]

        let mapper = SettingsMapper(
            headerSearchPaths: [],
            mainRelativePath: try RelativePath(validating: "path"),
            settings: settings
        )

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(
            resolvedSettings["OTHER_SWIFT_FLAGS"],
            .array([
                "$(inherited)",
                "ArbitraryFlag",
                "-enable-upcoming-feature NewFeature",
                "-enable-experimental-feature Experimental",
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

        let resolvedSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(
            resolvedSettings["OTHER_LDFLAGS"],
            .array([
                "$(inherited)",
                "ArbitraryFlag",
            ])
        )
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

        let allPlatformSettings = try mapper.settingsDictionaryForPlatform(nil)

        XCTAssertEqual(
            allPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .string("$(inherited) SWIFT_PACKAGE Define1")
        )

        let iosPlatformSettings = try mapper.settingsDictionaryForPlatform(.ios)

        XCTAssertEqual(
            iosPlatformSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
        )

        let combinedSettings = try mapper.settingsForPlatforms([.ios, .macos, .tvos])

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=appletvos*]"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
        )

        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=appletvsimulator*]"],
            .string("$(inherited) SWIFT_PACKAGE Define1 Define2")
        )


        XCTAssertEqual(
            combinedSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
            .string("$(inherited) SWIFT_PACKAGE Define1")
        )
    }
}

// OTHER_LDFLAGS

extension TuistGraph.SettingsDictionary {
    func stringValueFor(_ key: String) throws -> String {
        try XCTUnwrap(self[key]?.stringValue)
    }

    func arrayValueFor(_ key: String) throws -> [String] {
        try XCTUnwrap(self[key]?.arrayValue)
    }
}

extension TuistGraph.SettingValue {
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
    static var ios = PackageInfo.Platform(platformName: "ios", version: "11.0", options: [])
    static var macos = PackageInfo.Platform(platformName: "macos", version: "11.0", options: [])
    static var watchos = PackageInfo.Platform(platformName: "watchos", version: "11.0", options: [])
    static var tvos = PackageInfo.Platform(platformName: "tvos", version: "11.0", options: [])
    static var visionos = PackageInfo.Platform(platformName: "visionos", version: "11.0", options: [])
    static var linux = PackageInfo.Platform(platformName: "linux", version: "11.0", options: [])
    static var windows = PackageInfo.Platform(platformName: "windows", version: "11.0", options: [])
}
