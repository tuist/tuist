import Mockable
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class DefaultSettingsProvider_iOSTests: TuistUnitTestCase {
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
        "VALIDATE_PRODUCT": "YES",
    ]

    private let appTargetEssentialDebugSettings: [String: SettingValue] = [
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "DEBUG"]),
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_VERSION": "5.0",
    ]

    private let appTargetEssentialReleaseSettings: [String: SettingValue] = [
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SDKROOT": "iphoneos",
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
        "SWIFT_VERSION": "5.0",
    ]

    private let frameworkTargetEssentialDebugSettings: [String: SettingValue] = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "DEBUG"]),
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
        "SWIFT_VERSION": "5.0",
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
        "VERSION_INFO_PREFIX": "",
        "CODE_SIGN_IDENTITY": "",
        "SKIP_INSTALL": "YES",
        "DYLIB_CURRENT_VERSION": "1",
        "SWIFT_VERSION": "5.0",
    ]

    private let testTargetEssentialDebugSettings: [String: SettingValue] = [
        "SDKROOT": "iphoneos",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "DEBUG"]),
        "CODE_SIGN_IDENTITY": "iPhone Developer",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "SWIFT_VERSION": "5.0",
    ]

    private let multiplatformFrameworkTargetEssentialDebugSettings: [String: SettingValue] = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "DEBUG"]),
        "SKIP_INSTALL": "YES",
        "VERSIONING_SYSTEM": "apple-generic",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_INSTALL_NAME_BASE": "@rpath",
        "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
        "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"],
        "DEFINES_MODULE": "YES",
        "VERSION_INFO_PREFIX": "",
        "CURRENT_PROJECT_VERSION": "1",
        "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
        "DYLIB_COMPATIBILITY_VERSION": "1",
        "SWIFT_VERSION": "5.0",
    ]

    override func setUp() {
        super.setUp()
        subject = DefaultSettingsProvider(
            xcodeController: xcodeController
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func testProjectSettings_whenExcludingEssentialDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential(excluding: ["CLANG_CXX_LIBRARY"])
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertNotEqual(got, projectEssentialDebugSettings)
        XCTAssertNil(got["CLANG_CXX_LIBRARY"])
    }

    func testProjectSettings_whenEssentialDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertEqual(got, projectEssentialDebugSettings)
    }

    func testProjectSettings_whenEssentialRelease_iOS() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertEqual(got, projectEssentialReleaseSettings)
    }

    func testTargetSettings_whenBinaryAllowsToBeMerged() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let project = Project.test()
        let target = Target.test(product: .dynamicLibrary, mergeable: true)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["MAKE_MERGEABLE"], "YES")
        XCTAssertEqual(got["MERGEABLE_LIBRARY"], "YES")
    }

    func testTargetSettings_whenBinaryDoesNotMergeDependencies() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let project = Project.test()
        let target = Target.test(product: .app)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertNil(got["MERGED_BINARY_TYPE"])
    }

    func testTargetSettings_whenAppMergesDependencies_automatic() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let project = Project.test()
        let target = Target.test(product: .app, mergedBinaryType: .automatic)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["MERGED_BINARY_TYPE"], "automatic")
    }

    func testTargetSettings_whenAppMergesDependencies_manualDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let project = Project.test()
        let target = Target.test(product: .app, mergedBinaryType: .manual(mergeableDependencies: Set(["Sample"])))
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["MERGED_BINARY_TYPE"], "manual")
        XCTAssertEqual(got["OTHER_LDFLAGS"], "-Wl,-reexport_framework,Sample")
    }

    func testTargetSettings_whenAppMergesDependencies_manualRelease() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let project = Project.test()
        let target = Target.test(product: .app, mergedBinaryType: .manual(mergeableDependencies: Set(["Sample"])))
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["MERGED_BINARY_TYPE"], "manual")
        XCTAssertEqual(got["OTHER_LDFLAGS"], "-Wl,-merge_framework,Sample")
    }

    func testTargetSettings_whenEssentialDebug_App() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(product: .app, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, appTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, frameworkTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialRelease_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, frameworkTargetEssentialReleaseSettings)
    }

    func testProjectSettings_whenRecommendedDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then

        XCTAssertSettings(got, containsAll: projectEssentialDebugSettings)
        XCTAssertEqual(got.count, 50)
    }

    func testProjectSettings_whenRecommendedRelease() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertSettings(got, containsAll: projectEssentialReleaseSettings)
        XCTAssertEqual(got.count, 47)
    }

    func testProjectSettings_whenNoneDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .none
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testProjectSettings_whenNoneRelease() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .none
        )
        let project = Project.test(settings: settings)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.projectSettings(
            project: project,
            buildConfiguration: buildConfiguration
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenRecommendedDebug() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test()
        let target = Target.test(settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(11, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: appTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 10)
    }

    func testTargetSettings_inheritsProjectDefaultSettings_when_targetBuildSettings_are_nil() async throws {
        // Given
        let project = Project.test(settings: .test(defaultSettings: .essential))
        let target = Target.test(settings: nil)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: .debug,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: appTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenXcode10() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let target = Target.test(settings: settings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(10, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertFalse(got.keys.contains(where: { $0 == "ENABLE_PREVIEWS" }))
    }

    func testTargetSettings_whenXcode11() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let target = Target.test(settings: settings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(11, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertTrue(got.keys.contains(where: { $0 == "ENABLE_PREVIEWS" }))
    }

    func testTargetSettings_whenRecommended_containsDefaultSwiftVersion() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let target = Target.test(product: .app, settings: settings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["SWIFT_VERSION"], .string("5.0"))
    }

    func testTargetSettings_whenRecommendedAndSpecifiedInProject_doesNotContainDefaultSwiftVersion() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let target = Target.test(product: .app, settings: settings)
        let project = Project.test(
            settings: .test(
                base: [
                    "SWIFT_VERSION": "4.2",
                ]
            )
        )
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertNil(got["SWIFT_VERSION"])
    }

    func testTargetSettings_whenEssential_containsDefaultSwiftVersion() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let target = Target.test(product: .app, settings: settings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got["SWIFT_VERSION"], .string("5.0"))
    }

    func testTargetSettings_whenNone_doesNotContainDefaultSwiftVersion() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .none
        )
        let target = Target.test(product: .app, settings: settings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertNil(got["SWIFT_VERSION"])
    }

    func testTargetSettings_whenRecommendedRelease_App() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let target = Target.test(product: .app, settings: settings)
        let project = Project.test()
        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(11, 0, 0))
        let graph = Graph.test(path: project.path)

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: appTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 9)
    }

    func testTargetSettings_whenRecommendedDebug_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: frameworkTargetEssentialDebugSettings)
        XCTAssertEqual(got.count, 18)
    }

    func testTargetSettings_whenRecommendedRelease_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: frameworkTargetEssentialReleaseSettings)
        XCTAssertEqual(got.count, 17)
    }

    func testTargetSettings_whenNoneDebug_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .none
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenNoneRelease_Framework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .none
        )
        let project = Project.test()
        let target = Target.test(product: .framework, settings: settings)
        let graph = Graph.test(path: project.path)

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func testTargetSettings_whenRecommendedDebug_UnitTests() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test()
        let target = Target.test(product: .unitTests, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: testTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenRecommendedDebug_UITests() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .recommended
        )
        let project = Project.test()
        let target = Target.test(product: .uiTests, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertSettings(got, containsAll: testTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_UnitTests() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(product: .unitTests, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, testTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_UITests() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(product: .uiTests, settings: settings)
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, testTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialDebug_MultiplatformFramework() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .mac],
            product: .framework,
            settings: settings
        )
        let graph = Graph.test(path: project.path)

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, multiplatformFrameworkTargetEssentialDebugSettings)
    }
}

final class DefaultSettingsProvider_MacosTests: TuistUnitTestCase {
    private var subject: DefaultSettingsProvider!

    private let macroTargetEssentialDebugSettings: [String: SettingValue] = [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["$(inherited)", "DEBUG"]),
        "SKIP_INSTALL": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        "SWIFT_VERSION": "5.0",
        "SDKROOT": "macosx",
        "CODE_SIGN_IDENTITY": "-",
    ]

    private let macroTargetEssentialReleaseSettings: [String: SettingValue] = [
        "SKIP_INSTALL": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
        "SWIFT_VERSION": "5.0",
        "SDKROOT": "macosx",
        "CODE_SIGN_IDENTITY": "-",
    ]

    override func setUp() {
        super.setUp()
        subject = DefaultSettingsProvider(
            xcodeController: xcodeController
        )
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func testTargetSettings_whenEssentialDebug_Macro() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .debug
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(
            destinations: [.mac],
            product: .macro,
            settings: settings
        )
        let graph = Graph.test(path: project.path)

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, macroTargetEssentialDebugSettings)
    }

    func testTargetSettings_whenEssentialRelease_Macro() async throws {
        // Given
        let buildConfiguration: BuildConfiguration = .release
        let settings = Settings(
            base: [:],
            configurations: [buildConfiguration: nil],
            defaultSettings: .essential
        )
        let project = Project.test()
        let target = Target.test(
            destinations: [.mac],
            product: .macro,
            settings: settings
        )
        let graph = Graph.test(path: project.path)

        // When
        let got = try await subject.targetSettings(
            target: target,
            project: project,
            buildConfiguration: buildConfiguration,
            graphTraverser: GraphTraverser(graph: graph)
        )

        // Then
        XCTAssertEqual(got, macroTargetEssentialReleaseSettings)
    }
}

final class DictionaryStringAnyExtensionTests: XCTestCase {
    func testToSettings_whenOnlyStrings() throws {
        // Given
        let subject: [String: Any] = [
            "A": "A_VALUE",
            "B": "B_VALUE",
        ]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, [
            "A": .string("A_VALUE"),
            "B": .string("B_VALUE"),
        ])
    }

    func testToSettings_whenStringsAndArray() throws {
        // Given
        let subject: [String: Any] = [
            "A": "A_VALUE",
            "B": "B_VALUE",
            "C": ["C_1", "C_2"],
            "D": ["D_1", "D_2"],
        ]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, [
            "A": .string("A_VALUE"),
            "B": .string("B_VALUE"),
            "C": .array(["C_1", "C_2"]),
            "D": .array(["D_1", "D_2"]),
        ])
    }

    func testToSettings_whenArraysOnly() throws {
        // Given
        let subject: [String: Any] = [
            "A": ["A_1", "A_2"],
            "B": ["B_1", "B_2"],
        ]

        // When
        let got = try subject.toSettings()

        // Then
        XCTAssertEqual(got, [
            "A": .array(["A_1", "A_2"]),
            "B": .array(["B_1", "B_2"]),
        ])
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

extension XCTestCase {
    fileprivate func XCTAssertSettings(
        _ first: [String: SettingValue],
        containsAll second: [String: SettingValue],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for (key, expectedValue) in second {
            let result = first[key]
            let resultDescription = result.map { "\($0)" } ?? "nil"
            XCTAssertEqual(
                result,
                expectedValue,
                "\(key):\(resultDescription) does not match expected \(key): \(expectedValue)",
                file: file,
                line: line
            )
        }
    }
}
