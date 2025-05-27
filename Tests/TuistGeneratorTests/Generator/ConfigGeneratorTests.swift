import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XcodeProj
@testable import TuistGenerator
@testable import TuistSupportTesting

struct ConfigGeneratorTests {
    var pbxproj: PBXProj!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!

    init() throws {
        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
        subject = ConfigGenerator()

        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateProjectConfig_whenDebug() async throws {
        try await generateProjectConfig(config: .debug)
        #expect(pbxproj.configurationLists.count == 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let debugConfig: XCBuildConfiguration = configurationList.buildConfigurations[2]
        #expect(debugConfig.name == "Debug")
        #expect(debugConfig.buildSettings["Debug"] == .string("Debug"))
        #expect(debugConfig.buildSettings["Base"] == .string("Base"))
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateProjectConfig_whenRelease() async throws {
        try await generateProjectConfig(config: .release)

        #expect(pbxproj.configurationLists.count == 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let releaseConfig: XCBuildConfiguration = configurationList.buildConfigurations[3]
        #expect(releaseConfig.name == "Release")
        #expect(releaseConfig.buildSettings["Release"] == .string("Release"))
        #expect(releaseConfig.buildSettings["Base"] == .string("Base"))
        #expect(releaseConfig.buildSettings["MTL_ENABLE_DEBUG_INFO"] == .string("NO"))

        let customReleaseConfig: XCBuildConfiguration = configurationList.buildConfigurations[1]
        #expect(customReleaseConfig.name == "CustomRelease")
        #expect(customReleaseConfig.buildSettings["Base"] == .string("Base"))
        #expect(customReleaseConfig.buildSettings["MTL_ENABLE_DEBUG_INFO"] == .string("NO"))
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTargetConfig() async throws {
        // Given
        let commonSettings: SettingsDictionary = [
            "Base": "Base",
            "INFOPLIST_FILE": "$(SRCROOT)/Info.plist",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.test.bundle_id",
            "CODE_SIGN_ENTITLEMENTS": "$(SRCROOT)/Test.entitlements",
            "SWIFT_VERSION": "5.0",
        ]

        let debugSettings: SettingsDictionary = [
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        ]

        let releaseSettings: SettingsDictionary = [
            "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
        ]

        // When
        try await generateTargetConfig()

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let customDebugConfig = configurationList?.configuration(name: "CustomDebug")
        let releaseConfig = configurationList?.configuration(name: "Release")
        let customReleaseConfig = configurationList?.configuration(name: "CustomRelease")

        assert(config: debugConfig, contains: commonSettings)
        assert(config: debugConfig, contains: debugSettings)
        assert(config: debugConfig, hasXcconfig: "debug.xcconfig")

        assert(config: customDebugConfig, contains: commonSettings)
        assert(config: customDebugConfig, contains: debugSettings)

        assert(config: releaseConfig, contains: commonSettings)
        assert(config: releaseConfig, contains: releaseSettings)
        assert(config: releaseConfig, hasXcconfig: "release.xcconfig")

        assert(config: customReleaseConfig, contains: commonSettings)
        assert(config: customReleaseConfig, contains: releaseSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_whenSourceRootIsEqualToXcodeprojPath() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let project = Project.test(
            sourceRootPath: sourceRootPath,
            xcodeProjPath: sourceRootPath.appending(component: "Project.xcodeproj")
        )
        let target = Target.test(
            infoPlist: .file(path: sourceRootPath.appending(component: "Info.plist"))
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: sourceRootPath
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "INFOPLIST_FILE": "Info.plist",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_whenVariableInfoPlistPath() async throws {
        // Given
        let sourceRootPath = try #require(FileSystem.temporaryTestDirectory)
        let project = Project.test(
            sourceRootPath: sourceRootPath,
            xcodeProjPath: sourceRootPath.appending(component: "Project.xcodeproj")
        )
        let target = Target.test(
            infoPlist: .variable("$(INFO_PLIST_FILE_VARIABLE)")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: sourceRootPath
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "INFOPLIST_FILE": "$(INFO_PLIST_FILE_VARIABLE)",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTestTargetConfiguration_iOS() async throws {
        // Given / When
        try await generateTestTargetConfig(appName: "App")

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTestTargetConfiguration_iOS_when_essentialSettings() async throws {
        // Given / When
        let settings = Settings.test(defaultSettings: .essential)
        try await generateTestTargetConfig(appName: "App", settings: settings)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTestTargetConfiguration_macOS() async throws {
        // Given / When
        try await generateTestTargetConfig(appName: "App", destinations: .macOS)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTestTargetConfiguration_macOS_when_essentialSettings() async throws {
        // Given / When
        let settings = Settings.test(defaultSettings: .essential)
        try await generateTestTargetConfig(appName: "App", destinations: .macOS, settings: settings)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTestTargetConfiguration_usesProductName() async throws {
        // Given / When
        try await generateTestTargetConfig(
            appName: "App-dash",
            productName: "App_dash"
        )

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App_dash.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App_dash",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTestTargetConfiguration_usesProductName_when_essentialSettings() async throws {
        // Given / When
        let settings = Settings.test(defaultSettings: .essential)
        try await generateTestTargetConfig(
            appName: "App-dash",
            productName: "App_dash",
            settings: settings
        )

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App_dash.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App_dash",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateUITestTargetConfiguration() async throws {
        // Given / When
        try await generateTestTargetConfig(appName: "App", uiTest: true)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_TARGET_NAME": "App",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateUITestTargetConfiguration_when_essentialSettings() async throws {
        // Given / When
        let settings = Settings.test(defaultSettings: .essential)
        try await generateTestTargetConfig(appName: "App", uiTest: true, settings: settings)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_TARGET_NAME": "App",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    func test_generateUITestTargetConfiguration_usesTargetName() async throws {
        // Given / When
        try await generateTestTargetConfig(
            appName: "App-dash",
            productName: "App_dash",
            uiTest: true
        )

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_TARGET_NAME": "App-dash", // `TEST_TARGET_NAME` should reference the target name as opposed to `productName`
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateUITestTargetConfiguration_usesTargetName_when_essentialSettings() async throws {
        // Given / When
        let settings = Settings.test(defaultSettings: .essential)
        try await generateTestTargetConfig(
            appName: "App-dash",
            productName: "App_dash",
            uiTest: true,
            settings: settings
        )

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_TARGET_NAME": "App-dash", // `TEST_TARGET_NAME` should reference the target name as opposed to `productName`
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenIOS_withMacAndVisionForIPhoneSupport() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign],
            deploymentTargets: .iOS("12.0")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "SDKROOT": "iphoneos",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "IPHONEOS_DEPLOYMENT_TARGET": "12.0",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "YES",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "YES",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)

        // SUPPORTED_PLATFORMS is only set when multiple platforms are defined by the target
        #expect(debugConfig?.buildSettings["SUPPORTED_PLATFORMS"] == nil)
        #expect(releaseConfig?.buildSettings["SUPPORTED_PLATFORMS"] == nil)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenIOS_withoutMacAndVisionForIPhoneSupport() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad],
            deploymentTargets: .iOS("12.0")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "1,2",
            "IPHONEOS_DEPLOYMENT_TARGET": "12.0",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenIOS_for_framework() async throws {
        // Given
        let target = Target.test(
            destinations: [.iPhone, .iPad, .macWithiPadDesign],
            product: .framework,
            deploymentTargets: .iOS("13.0")
        )
        let project = Project.test(targets: [target])
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "1,2",
            "IPHONEOS_DEPLOYMENT_TARGET": "13.0",
            "SUPPORTS_MACCATALYST": "NO",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTargetWithDeploymentTarget_whenMac() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.mac], deploymentTargets: .macOS("10.14.1"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "MACOSX_DEPLOYMENT_TARGET": "10.14.1",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenCatalyst() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad, .macCatalyst],
            deploymentTargets: .iOS("13.1")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "1,2,6",
            "IPHONEOS_DEPLOYMENT_TARGET": "13.1",
            "SUPPORTS_MACCATALYST": "YES",
            "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "YES",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenWatch() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleWatch], deploymentTargets: .watchOS("6.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "4",
            "WATCHOS_DEPLOYMENT_TARGET": "6.0",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTargetWithDeploymentTarget_whenTV() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleTv], deploymentTargets: .tvOS("14.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "3",
            "TVOS_DEPLOYMENT_TARGET": "14.0",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenVision() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleVision], deploymentTargets: .visionOS("1.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "7",
            "XROS_DEPLOYMENT_TARGET": "1.0",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetWithDeploymentTarget_whenVisionWithiPadDesign() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad, .appleVisionWithiPadDesign],
            deploymentTargets: .init(iOS: "16.0", visionOS: "1.0")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "TARGETED_DEVICE_FAMILY": "1,2",
            "XROS_DEPLOYMENT_TARGET": "1.0",
            "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
            "SDKROOT": "iphoneos",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTargetWithMultiplePlatforms() async throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.mac, .iPad, .iPhone])
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .default,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let expectedSettings: SettingsDictionary = [
            "SDKROOT": "auto",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks"],
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateProjectConfig_defaultConfigurationName() async throws {
        // Given
        let settings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
            .release("CustomRelease"): nil,
            .release("AnotherRelease"): nil,
        ])
        let project = Project.test(settings: settings)

        // When
        let result = try await subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements()
        )

        // Then
        #expect(result.defaultConfigurationName == "AnotherRelease")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateProjectConfig_defaultConfigurationName_whenNoReleaseConfiguration() async throws {
        // Given
        let settings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
        ])
        let project = Project.test(settings: settings)

        // When
        let result = try await subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements()
        )

        // Then
        #expect(result.defaultConfigurationName == "AnotherDebug")
    }

    func test_generateProjectConfig_defaultConfigurationName_whenDefaultConfigurationNameIsProvided() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("CustomDebug"): nil,
                .debug("AnotherDebug"): nil,
                .release("CustomRelease"): nil,
                .release("AnotherRelease"): nil,
            ],
            defaultConfiguration: "CustomDebug"
        )
        let project = Project.test(settings: settings)

        // When
        let result = try await subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements()
        )

        // Then
        #expect(result.defaultConfigurationName == "CustomDebug")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_defaultConfigurationName() async throws {
        // Given
        let projectSettings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
            .release("CustomRelease"): nil,
            .release("AnotherRelease"): nil,
        ])
        let project = Project.test()
        let target = Target.test()
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let result = pbxTarget.buildConfigurationList
        #expect(result?.defaultConfigurationName == "AnotherRelease")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_defaultConfigurationName_whenNoReleaseConfiguration() async throws {
        // Given
        let projectSettings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
        ])
        let project = Project.test()
        let target = Target.test()
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let result = pbxTarget.buildConfigurationList
        #expect(result?.defaultConfigurationName == "AnotherDebug")
    }

    func test_generateTargetConfig_defaultConfigurationName_whenDefaultConfigurationNameIsProvided() async throws {
        // Given
        let projectSettings = Settings(
            configurations: [
                .debug("CustomDebug"): nil,
                .debug("AnotherDebug"): nil,
                .release("CustomRelease"): nil,
                .release("AnotherRelease"): nil,
            ],
            defaultConfiguration: "CustomDebug"
        )
        let project = Project.test()
        let target = Target.test()
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let result = pbxTarget.buildConfigurationList
        #expect(result?.defaultConfigurationName == "CustomDebug")
    }

    @Test(.withMockedXcodeController, .inTemporaryDirectory) func test_generateTargetConfigWithDuplicateValues() async throws {
        // Given
        let projectSettings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
        ])

        let targetSettings = Settings.test(
            base: ["OTHER_SWIFT_FLAGS": SettingValue.array([
                "$(inherited)",
                "CUSTOM_SWIFT_FLAG1",
            ])],
            debug: .test(settings: ["OTHER_SWIFT_FLAGS": SettingValue.array([
                "$(inherited)",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/B1",
                "-Xcc",
                "-fmodule-map-file=$(SRCROOT)/B2",
            ])]),
            release: .test()
        )
        let target = Target.test(settings: targetSettings)
        let project = Project.test()
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]

        #expect(targetSettingsResult == [
            "$(inherited)",
            "CUSTOM_SWIFT_FLAG1",
            "-Xcc",
            "-fmodule-map-file=$(SRCROOT)/B1",
            "-Xcc",
            "-fmodule-map-file=$(SRCROOT)/B2",
        ])
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_addsTheLoadPluginExecutableSwiftFlag_when_tagetDependsOnMacroStaticFramework(
    ) async throws {
        // Given
        let projectSettings = Settings.default
        let app = Target.test(name: "app", platform: .iOS, product: .app)
        let macroFramework = Target.test(name: "framework", platform: .macOS, product: .staticFramework)
        let macroExecutable = Target.test(name: "macro", platform: .macOS, product: .macro)
        let project = Project.test(targets: [app, macroFramework, macroExecutable])

        let graph = Graph.test(path: project.path, projects: [project.path: project], dependencies: [
            .target(name: app.name, path: project.path): Set([.target(name: macroFramework.name, path: project.path)]),
            .target(name: macroFramework.name, path: project.path): Set([.target(
                name: macroExecutable.name,
                path: project.path
            )]),
            .target(name: macroExecutable.name, path: project.path): Set([]),
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            app,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]
        #expect(
            targetSettingsResult ==
                .array([
                    "-load-plugin-executable",
                    "$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/\(macroExecutable.productName)#\(macroExecutable.productName)",
                ])
        )
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_doesntAddTheLoadPluginExecutableSwiftFlag_when_theTargetDependsOnAStaticFrameworkThatDoesntRepresentAMacro(
    ) async throws {
        // Given
        let projectSettings = Settings.default
        let app = Target.test(name: "app", platform: .iOS, product: .app)
        let macroFramework = Target.test(name: "framework", platform: .macOS, product: .staticFramework)
        let project = Project.test(targets: [app, macroFramework])

        let graph = Graph.test(path: project.path, projects: [project.path: project], dependencies: [
            .target(name: app.name, path: project.path): Set([.target(name: macroFramework.name, path: project.path)]),
            .target(name: macroFramework.name, path: project.path): Set([]),
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            app,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]
        #expect(targetSettingsResult == nil)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_entitlementAreCorrectlyMappedToXCConfig_when_targetIsAppClipAndXCConfigIsProvided(
    ) async throws {
        let projectSettings = Settings.default
        let appClip = Target.test(
            name: "app",
            platform: .iOS,
            product: .appClip,
            entitlements: .variable("$(MY_CUSTOM_VARIABLE)")
        )

        let project = Project.test(targets: [appClip])

        let graph = Graph.test(path: project.path, projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            appClip,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["CODE_SIGN_ENTITLEMENTS"]
        #expect(targetSettingsResult == "$(MY_CUSTOM_VARIABLE)")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_entitlementAreCorrectlyMappedToXCConfig_when_targetIsAppClipAndXCConfigIsProvidedByStringLiteral(
    ) async throws {
        let projectSettings = Settings.default
        let appClip = Target.test(
            name: "app",
            platform: .iOS,
            product: .appClip,
            entitlements: "$(MY_CUSTOM_VARIABLE)"
        )

        let project = Project.test(targets: [appClip])

        let graph = Graph.test(path: project.path, projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            appClip,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: projectSettings,
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["CODE_SIGN_ENTITLEMENTS"]
        #expect(targetSettingsResult == "$(MY_CUSTOM_VARIABLE)")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_mergedBinaryTypeIsAutomatic_defaultSettingsIsEssential() async throws {
        // Given
        let settings = Settings.test(defaultSettings: .essential)
        let appTarget = Target.test(settings: settings, mergedBinaryType: .automatic)
        let project = Project.test(targets: [appTarget])
        let graph = Graph.test(path: project.path, projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            appTarget,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .test(),
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["MERGED_BINARY_TYPE"]
        #expect(targetSettingsResult == "automatic")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_mergedBinaryTypeIsManual_defaultSettingsIsEssential() async throws {
        // Given
        let settings = Settings.test(defaultSettings: .essential)
        let appTarget = Target.test(settings: settings, mergedBinaryType: .manual(mergeableDependencies: []))
        let project = Project.test(targets: [appTarget])
        let graph = Graph.test(path: project.path, projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            appTarget,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .test(),
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["MERGED_BINARY_TYPE"]
        #expect(targetSettingsResult == "manual")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_mergeableIsTrue_defaultSettingsIsEssential() async throws {
        // Given
        let settings = Settings.test(defaultSettings: .essential)
        let frameworkTarget = Target.test(product: .framework, settings: settings, mergeable: true)
        let project = Project.test(targets: [frameworkTarget])
        let graph = Graph.test(path: project.path, projects: [project.path: project])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            frameworkTarget,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: .test(),
            fileElements: ProjectFileElements(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["MERGEABLE_LIBRARY"]
        #expect(targetSettingsResult == "YES")
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_defaultSettingsIsRecommendedWithExcludingTEST_HOST_then_TEST_HOSTIsNil(
    ) async throws {
        // Given
        let settings = Settings.test(defaultSettings: .recommended(excluding: ["TEST_HOST"]))
        let appTarget = Target.test(name: "App", product: .app)
        let target = Target.test(name: "Test", product: .unitTests, settings: settings)
        let project = Project.test(name: "Project", targets: [target, appTarget])
        let graph = Graph.test(
            name: project.name,
            path: project.path,
            projects: [project.path: project],
            dependencies: [
                GraphDependency
                    .target(name: target.name, path: project.path): Set([.target(name: appTarget.name, path: project.path)]),
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: project.settings,
            fileElements: .init(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["TEST_HOST"]
        #expect(targetSettingsResult == nil)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_defaultSettingsIsEssentialWithExcludingTEST_HOST_then_TEST_HOSTIsNil() async throws {
        // Given
        let settings = Settings.test(defaultSettings: .essential(excluding: ["TEST_HOST"]))
        let appTarget = Target.test(name: "App", product: .app)
        let target = Target.test(name: "Test", product: .unitTests, settings: settings)
        let project = Project.test(name: "Project", targets: [target, appTarget])
        let graph = Graph.test(
            name: project.name,
            path: project.path,
            projects: [project.path: project],
            dependencies: [
                GraphDependency
                    .target(name: target.name, path: project.path): Set([.target(name: appTarget.name, path: project.path)]),
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: project.settings,
            fileElements: .init(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["TEST_HOST"]
        #expect(targetSettingsResult == nil)
    }

    @Test(
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func test_generateTargetConfig_when_defaultSettingsIsNoneWithExcludingTEST_HOST_then_TEST_HOSTIsNil() async throws {
        // Given
        let settings = Settings.test(defaultSettings: .none)
        let appTarget = Target.test(name: "App", product: .app)
        let target = Target.test(name: "Test", product: .unitTests, settings: settings)
        let project = Project.test(name: "Project", targets: [target, appTarget])
        let graph = Graph.test(
            name: project.name,
            path: project.path,
            projects: [project.path: project],
            dependencies: [
                GraphDependency
                    .target(name: target.name, path: project.path): Set([.target(name: appTarget.name, path: project.path)]),
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: project.settings,
            fileElements: .init(),
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/project")
        )

        // Then
        let targetSettingsResult = pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["TEST_HOST"]
        #expect(targetSettingsResult == nil)
    }

    // MARK: - Helpers

    private func generateProjectConfig(config _: BuildConfiguration) async throws {
        let dir = try #require(FileSystem.temporaryTestDirectory)
        let xcconfigsDir = dir.appending(component: "xcconfigs")
        try FileHandler.shared.createFolder(xcconfigsDir)
        try "".write(to: xcconfigsDir.appending(component: "debug.xcconfig").url, atomically: true, encoding: .utf8)
        try "".write(to: xcconfigsDir.appending(component: "release.xcconfig").url, atomically: true, encoding: .utf8)

        // CustomDebug, CustomRelease, Debug, Release
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug: Configuration(
                settings: ["Debug": "Debug"],
                xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")
            ),
            .debug("CustomDebug"): Configuration(settings: ["CustomDebug": "CustomDebug"], xcconfig: nil),
            .release: Configuration(
                settings: ["Release": "Release"],
                xcconfig: xcconfigsDir.appending(component: "release.xcconfig")
            ),
            .release("CustomRelease"): Configuration(settings: ["CustomRelease": "CustomRelease"], xcconfig: nil),
        ]
        let project = Project.test(
            path: dir,
            name: "Test",
            settings: Settings(base: ["Base": "Base"], configurations: configurations),
            targets: []
        )
        let fileElements = ProjectFileElements()
        _ = try await subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: fileElements
        )
    }

    private func generateTargetConfig() async throws {
        let dir = try #require(FileSystem.temporaryTestDirectory)
        let xcconfigsDir = dir.appending(component: "xcconfigs")
        try FileHandler.shared.createFolder(xcconfigsDir)
        try "".write(to: xcconfigsDir.appending(component: "debug.xcconfig").url, atomically: true, encoding: .utf8)
        try "".write(to: xcconfigsDir.appending(component: "release.xcconfig").url, atomically: true, encoding: .utf8)
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug: Configuration(
                settings: ["Debug": "Debug"],
                xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")
            ),
            .debug("CustomDebug"): Configuration(settings: ["CustomDebug": "CustomDebug"], xcconfig: nil),
            .release: Configuration(
                settings: ["Release": "Release"],
                xcconfig: xcconfigsDir.appending(component: "release.xcconfig")
            ),
            .release("CustomRelease"): Configuration(settings: ["CustomRelease": "CustomRelease"], xcconfig: nil),
        ]
        let target = Target.test(
            name: "Test",
            bundleId: "com.test.bundle_id",
            infoPlist: .file(path: try AbsolutePath(validating: "/Info.plist")),
            entitlements: .file(path: try AbsolutePath(validating: "/Test.entitlements")),
            settings: Settings(base: ["Base": "Base"], configurations: configurations)
        )
        let project = Project.test(
            path: dir,
            sourceRootPath: dir,
            xcodeProjPath: dir.appending(component: "Project.xcodeproj"),
            name: "Test",
            settings: .default,
            targets: [target]
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        let fileElements = ProjectFileElements()
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj)
        try fileElements.generateProjectFiles(
            project: project,
            graphTraverser: graphTraverser,
            groups: groups,
            pbxproj: pbxproj
        )
        _ = try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: project.settings,
            fileElements: fileElements,
            graphTraverser: graphTraverser,
            sourceRootPath: try AbsolutePath(validating: "/")
        )
    }

    private func generateTestTargetConfig(
        appName: String = "App",
        destinations: Destinations = .iOS,
        productName: String? = nil,
        uiTest: Bool = false,
        settings: Settings? = nil
    ) async throws {
        let dir = try #require(FileSystem.temporaryTestDirectory)

        let appTarget = Target.test(
            name: appName,
            destinations: destinations,
            product: .app,
            productName: productName,
            settings: settings
        )

        let target = Target.test(name: "Test", destinations: destinations, product: uiTest ? .uiTests : .unitTests)
        let project = Project.test(path: dir, name: "Project", targets: [target, appTarget])

        let graph = Graph.test(
            name: project.name,
            path: project.path,
            projects: [project.path: project],
            dependencies: [
                GraphDependency
                    .target(name: target.name, path: project.path): Set([.target(name: appTarget.name, path: project.path)]),
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        _ = try await subject.generateTargetConfig(
            target,
            project: project,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            projectSettings: project.settings,
            fileElements: .init(),
            graphTraverser: graphTraverser,
            sourceRootPath: dir
        )
    }

    func assert(
        config: XCBuildConfiguration?,
        contains settings: [String: SettingValue]
    ) {
        let matches = settings.filter {
            if let stringValue = config?.buildSettings[$0.key]?.stringValue {
                return $0.value == .string(stringValue)
            } else if let arrayValue = config?.buildSettings[$0.key]?.arrayValue {
                return $0.value == .array(arrayValue)
            } else {
                return false
            }
        }

        #expect(
            matches.count ==
                settings.count
        )
    }

    func assert(
        config: XCBuildConfiguration?,
        hasXcconfig xconfigPath: String
    ) {
        let xcconfig: PBXFileReference? = config?.baseConfiguration
        #expect(
            xcconfig?.path ==
                xconfigPath
        )
    }
}
