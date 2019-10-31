import TuistSupportTesting
import XCTest
@testable import TuistGenerator

final class DefaultSettingsProvider_iOSTests: XCTestCase {
    private var subject: DefaultSettingsProvider!

    private let projectEssentialDebugSettings: [String: SettingValue] = [
        "CLANG_CXX_LIBRARY": "libc++",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++14",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "MTL_ENABLE_DEBUG_INFO": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_C_LANGUAGE_STANDARD": "gnu11",
        "ONLY_ACTIVE_ARCH": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_TESTABILITY": "YES",
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
    ]

    private let projectEssentialReleaseSettings: [String: SettingValue] = [
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "GCC_C_LANGUAGE_STANDARD": "gnu11",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_ENABLE_OBJC_WEAK": "YES",
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "COPY_PHASE_STRIP": "NO",
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_CXX_LIBRARY": "libc++",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "ENABLE_NS_ASSERTIONS": "NO",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++14",
    ]

    private let appTargetEssentialDebugSettings: [String: SettingValue] = [
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
    ]

    private let appTargetEssentialReleaseSettings: [String: SettingValue] = [
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SDKROOT": "iphoneos",
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "VALIDATE_PRODUCT": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
    ]

    private let frameworkTargetEssentialDebugSettings: [String: SettingValue] = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SKIP_INSTALL": "YES",
        "CODE_SIGN_IDENTITY": "",
        "VERSIONING_SYSTEM": "apple-generic",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        "DEFINES_MODULE": "YES",
        "VERSION_INFO_PREFIX": "",
        "CURRENT_PROJECT_VERSION": "1",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_COMPATIBILITY_VERSION": "1",
    ]

    private let frameworkTargetEssentialReleaseSettings: [String: SettingValue] = [
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        "DEFINES_MODULE": "YES",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "DYLIB_COMPATIBILITY_VERSION": "1",
        "VERSIONING_SYSTEM": "apple-generic",
        "CURRENT_PROJECT_VERSION": "1",
        "SDKROOT": "iphoneos",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)",
        "VALIDATE_PRODUCT": "YES",
        "VERSION_INFO_PREFIX": "",
        "CODE_SIGN_IDENTITY": "",
        "SKIP_INSTALL": "YES",
        "DYLIB_CURRENT_VERSION": "1",
    ]

    override func setUp() {
        super.setUp()
        subject = DefaultSettingsProvider()
    }

    func testProjectSettings_whenEssentialDebug() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got, projectEssentialDebugSettings)
    }

    func testProjectSettings_whenEssentialRelease_iOS() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got, projectEssentialReleaseSettings)
    }

    func testTargetSettings_whenEssentialDebug_App() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .app, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got, appTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got, frameworkTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialRelease_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got, frameworkTargetEssentialReleaseSettings)
    }

    func testProjectSettings_whenRecommendedDebug() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then

        XCTAssertSettings(got, containsAll: projectEssentialDebugSettings)
        XCTAssertEqual(got.count, 47)
    }

    func testProjectSettings_whenRecommendedRelease() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then
        XCTAssertSettings(got, containsAll: projectEssentialReleaseSettings)
        XCTAssertEqual(got.count, 43)
    }

    func testProjectSettings_whenNoneDebug() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testProjectSettings_whenNoneRelease() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let project = Project.test(settings: settings)

        // When
        let got = try subject.projectSettings(project: project,
                                              buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenRecommendedDebug() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertSettings(got, containsAll: appTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 8)
    }

    func testTargetSettings_whenRecommendedRelease_App() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .app, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertSettings(got, containsAll: appTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 8)
    }

    func testTargetSettings_whenRecommendedDebug_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertSettings(got, containsAll: frameworkTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 17)
    }

    func testTargetSettings_whenRecommendedRelease_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertSettings(got, containsAll: frameworkTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 17)
    }

    func testTargetSettings_whenNoneDebug_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenNoneRelease_Framework() throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = try subject.targetSettings(target: target,
                                             buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }
}

final class DictionaryStringAnyExtensionTests: XCTestCase {
    func testToSettings_whenOnlyStrings() throws {
        // Given
        let subject: [String: Any] = ["A": "A_VALUE",
                                      "B": "B_VALUE"]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, ["A": .string("A_VALUE"),
                             "B": .string("B_VALUE")])
    }

    func testToSettings_whenStringsAndArray() throws {
        // Given
        let subject: [String: Any] = ["A": "A_VALUE",
                                      "B": "B_VALUE",
                                      "C": ["C_1", "C_2"],
                                      "D": ["D_1", "D_2"]]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, ["A": .string("A_VALUE"),
                             "B": .string("B_VALUE"),
                             "C": .array(["C_1", "C_2"]),
                             "D": .array(["D_1", "D_2"])])
    }

    func testToSettings_whenArraysOnly() throws {
        // Given
        let subject: [String: Any] = ["A": ["A_1", "A_2"],
                                      "B": ["B_1", "B_2"]]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, ["A": .array(["A_1", "A_2"]),
                             "B": .array(["B_1", "B_2"])])
    }

    func testToSettings_whenInvaludContent() throws {
        // Given
        let subject: [String: Any] = ["A": ["A_1": ["A_2": "A_3"]]]

        // When
        XCTAssertThrowsError(try subject.toSettings()) { error in
            // Then
            guard let error = error as? BuildSettingsError else {
                XCTFail("Unexpected error type")
                return
            }
            XCTAssertEqual(error.description, "Cannot convert \"[\"A_1\": [\"A_2\": \"A_3\"]]\" to SettingValue type")
            XCTAssertEqual(error.type, .bug)
        }
    }
}

private extension XCTestCase {
    func XCTAssertSettings(_ first: [String: SettingValue],
                           containsAll second: [String: SettingValue],
                           file: StaticString = #file,
                           line: UInt = #line) {
        let filteredFirst = first.filter { second.keys.contains($0.key) }
        XCTAssertEqual(filteredFirst, second, file: file, line: line)
    }
}
