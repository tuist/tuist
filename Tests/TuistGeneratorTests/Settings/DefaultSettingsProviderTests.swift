import TuistCoreTesting
import TuistGenerator
import XCTest

final class DefaultSettingsProvider_iOSTests: XCTestCase {
    private var subject: DefaultSettingsProvider!

    private let projectEssentialDebugSettings: [String: Any] = [
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

    private let projectEssentialReleaseSettings: [String: Any] = [
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

    private let appTargetEssentialDebugSettings: [String: Any] = [
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
    ]

    private let appTargetEssentialReleaseSettings: [String: Any] = [
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SDKROOT": "iphoneos",
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "VALIDATE_PRODUCT": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
    ]

    private let frameworkTargetEssentialDebugSettings: [String: Any] = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SKIP_INSTALL": "YES",
        "CODE_SIGN_IDENTITY": "",
        "VERSIONING_SYSTEM": "apple-generic",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "DEFINES_MODULE": "YES",
        "VERSION_INFO_PREFIX": "",
        "CURRENT_PROJECT_VERSION": "1",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_COMPATIBILITY_VERSION": "1",
    ]

    private let frameworkTargetEssentialReleaseSettings: [String: Any] = [
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
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

    func testProjectSettings_whenEssentialDebug() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqualDictionaries(got, projectEssentialDebugSettings)
    }

    func testProjectSettings_whenEssentialRelease_iOS() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqualDictionaries(got, projectEssentialReleaseSettings)
    }

    func testTargetSettings_whenEssentialDebug_App() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .app, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqualDictionaries(got, appTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqualDictionaries(got, frameworkTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialRelease_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .essential)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqualDictionaries(got, frameworkTargetEssentialReleaseSettings)
    }

    func testProjectSettings_whenRecommendedDebug() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: projectEssentialDebugSettings)
        XCTAssertEqual(got.count, 47)
    }

    func testProjectSettings_whenRecommendedRelease() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: projectEssentialReleaseSettings)
        XCTAssertEqual(got.count, 43)
    }

    func testProjectSettings_whenNoneDebug() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testProjectSettings_whenNoneRelease() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let project = Project.test(settings: settings)

        // When
        let got = subject.projectSettings(project: project,
                                          buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenRecommendedDebug() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: appTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 8)
    }

    func testTargetSettings_whenRecommendedRelease_App() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .app, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: appTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 8)
    }

    func testTargetSettings_whenRecommendedDebug_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: frameworkTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 17)
    }

    func testTargetSettings_whenRecommendedRelease_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .recommended)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertDictionary(got, containsAll: frameworkTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 17)
    }

    func testTargetSettings_whenNoneDebug_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenNoneRelease_Framework() {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(base: [:],
                                configurations: [buildConfiguration: nil],
                                defaultSettings: .none)
        let target = Target.test(product: .framework, settings: settings)

        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: buildConfiguration)

        // Then
        XCTAssertEqual(got.count, 0)
    }
    
    let targetMultiPlatformSettingsForMacOSiOS = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=macosx*]": "DEBUG",
        "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "iPhone Developer",
        "SDKROOT[sdk=macosx*]": "macosx",
        "COMBINE_HIDPI_IMAGES[sdk=macosx*]": "YES",
        "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=iphonesimulator*]": "AppIcon",
        "TARGETED_DEVICE_FAMILY[sdk=iphonesimulator*]": "1,2",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphoneos*]": "DEBUG",
        "LD_RUNPATH_SEARCH_PATHS[sdk=iphoneos*]": "$(inherited) @executable_path/Frameworks",
        "CODE_SIGN_IDENTITY[sdk=iphonesimulator*]": "iPhone Developer",
        "SDKROOT[sdk=iphoneos*]": "iphoneos",
        "SWIFT_OPTIMIZATION_LEVEL[sdk=iphonesimulator*]": "-Onone",
        "SWIFT_COMPILATION_MODE[sdk=iphoneos*]": "singlefile",
        "CODE_SIGN_IDENTITY[sdk=macosx*]": "-",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=iphonesimulator*]": "DEBUG",
        "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": "$(inherited) @executable_path/../Frameworks",
        "SWIFT_OPTIMIZATION_LEVEL[sdk=macosx*]": "-Onone",
        "TARGETED_DEVICE_FAMILY[sdk=iphoneos*]": "1,2",
        "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]": "AppIcon",
        "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=iphoneos*]": "AppIcon",
        "SDKROOT[sdk=iphonesimulator*]": "iphoneos",
        "SWIFT_COMPILATION_MODE[sdk=iphonesimulator*]": "singlefile",
        "SWIFT_OPTIMIZATION_LEVEL[sdk=iphoneos*]": "-Onone",
        "LD_RUNPATH_SEARCH_PATHS[sdk=iphonesimulator*]": "$(inherited) @executable_path/Frameworks",
        "SWIFT_COMPILATION_MODE[sdk=macosx*]": "singlefile"
    ]
    
    func testTargetSettings_when_multi_platform() {
        // Given

        let target = Target.test(platform: [.iOS, .macOS])
        
        // When
        let got = subject.targetSettings(target: target,
                                         buildConfiguration: .debug)
        
        // Then
        XCTAssertDictionary(got, containsAll: targetMultiPlatformSettingsForMacOSiOS)
    }
}
