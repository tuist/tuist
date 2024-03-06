import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ConfigGeneratorTests: TuistUnitTestCase {
    var pbxproj: PBXProj!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
        subject = ConfigGenerator()
    }

    override func tearDown() {
        pbxproj = nil
        pbxTarget = nil
        subject = nil
        super.tearDown()
    }

    func test_generateProjectConfig_whenDebug() throws {
        try generateProjectConfig(config: .debug)
        XCTAssertEqual(pbxproj.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let debugConfig: XCBuildConfiguration = configurationList.buildConfigurations[2]
        XCTAssertEqual(debugConfig.name, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateProjectConfig_whenRelease() throws {
        try generateProjectConfig(config: .release)

        XCTAssertEqual(pbxproj.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let releaseConfig: XCBuildConfiguration = configurationList.buildConfigurations[3]
        XCTAssertEqual(releaseConfig.name, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(releaseConfig.buildSettings["MTL_ENABLE_DEBUG_INFO"] as? String, "NO")

        let customReleaseConfig: XCBuildConfiguration = configurationList.buildConfigurations[1]
        XCTAssertEqual(customReleaseConfig.name, "CustomRelease")
        XCTAssertEqual(customReleaseConfig.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(customReleaseConfig.buildSettings["MTL_ENABLE_DEBUG_INFO"] as? String, "NO")
    }

    func test_generateTargetConfig() throws {
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
        try generateTargetConfig()

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

    func test_generateTargetConfig_whenSourceRootIsEqualToXcodeprojPath() throws {
        // Given
        let sourceRootPath = try temporaryPath()
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
        try subject.generateTargetConfig(
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

    func test_generateTestTargetConfiguration_iOS() throws {
        // Given / When
        try generateTestTargetConfig(appName: "App")

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

    func test_generateTestTargetConfiguration_macOS() throws {
        // Given / When
        try generateTestTargetConfig(appName: "App", destinations: .macOS)

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

    func test_generateTestTargetConfiguration_usesProductName() throws {
        // Given / When
        try generateTestTargetConfig(
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

    func test_generateUITestTargetConfiguration() throws {
        // Given / When
        try generateTestTargetConfig(appName: "App", uiTest: true)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings: SettingsDictionary = [
            "TEST_TARGET_NAME": "App",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    func test_generateUITestTargetConfiguration_usesTargetName() throws {
        // Given / When
        try generateTestTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenIOS_withMacAndVisionForIPhoneSupport() throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign],
            deploymentTargets: .iOS("12.0")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
        XCTAssertNil(debugConfig?.buildSettings["SUPPORTED_PLATFORMS"])
        XCTAssertNil(releaseConfig?.buildSettings["SUPPORTED_PLATFORMS"])
    }

    func test_generateTargetWithDeploymentTarget_whenIOS_withoutMacAndVisionForIPhoneSupport() throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad],
            deploymentTargets: .iOS("12.0")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenIOS_for_framework() throws {
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
        try subject.generateTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenMac() throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.mac], deploymentTargets: .macOS("10.14.1"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenCatalyst() throws {
        // Given
        let project = Project.test()
        let target = Target.test(
            destinations: [.iPhone, .iPad, .macCatalyst],
            deploymentTargets: .iOS("13.1")
        )
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
            "IPHONEOS_DEPLOYMENT_TARGET": "13.1",
            "SUPPORTS_MACCATALYST": "YES",
            "DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER": "YES",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD": "NO",
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    func test_generateTargetWithDeploymentTarget_whenWatch() throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleWatch], deploymentTargets: .watchOS("6.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenTV() throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleTv], deploymentTargets: .tvOS("14.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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

    func test_generateTargetWithDeploymentTarget_whenVision() throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.appleVision], deploymentTargets: .visionOS("1.0"))
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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

    func test_generateTargetWithMultiplePlatforms() throws {
        // Given
        let project = Project.test()
        let target = Target.test(destinations: [.mac, .iPad, .iPhone])
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
            "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]": ["$(inherited)", "@executable_path/../Frameworks"],
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        ]

        assert(config: debugConfig, contains: expectedSettings)
        assert(config: releaseConfig, contains: expectedSettings)
    }

    func test_generateProjectConfig_defaultConfigurationName() throws {
        // Given
        let settings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
            .release("CustomRelease"): nil,
        ])
        let project = Project.test(settings: settings)

        // When
        let result = try subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements()
        )

        // Then
        XCTAssertEqual(result.defaultConfigurationName, "CustomRelease")
    }

    func test_generateProjectConfig_defaultConfigurationName_whenNoReleaseConfiguration() throws {
        // Given
        let settings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
        ])
        let project = Project.test(settings: settings)

        // When
        let result = try subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements()
        )

        // Then
        XCTAssertEqual(result.defaultConfigurationName, "AnotherDebug")
    }

    func test_generateTargetConfig_defaultConfigurationName() throws {
        // Given
        let projectSettings = Settings(configurations: [
            .debug("CustomDebug"): nil,
            .debug("AnotherDebug"): nil,
            .release("CustomRelease"): nil,
        ])
        let project = Project.test()
        let target = Target.test()
        let graph = Graph.test(path: project.path)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
        XCTAssertEqual(result?.defaultConfigurationName, "CustomRelease")
    }

    func test_generateTargetConfig_defaultConfigurationName_whenNoReleaseConfiguration() throws {
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
        try subject.generateTargetConfig(
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
        XCTAssertEqual(result?.defaultConfigurationName, "AnotherDebug")
    }

    func test_generateTargetConfigWithDuplicateValues() throws {
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
        try subject.generateTargetConfig(
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
        let targetSettingsResult = try pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]

        XCTAssertEqual(targetSettingsResult, [
            "$(inherited)",
            "CUSTOM_SWIFT_FLAG1",
            "-Xcc",
            "-fmodule-map-file=$(SRCROOT)/B1",
            "-Xcc",
            "-fmodule-map-file=$(SRCROOT)/B2",
        ])
    }

    func test_generateTargetConfig_addsTheLoadPluginExecutableSwiftFlag_when_tagetDependsOnMacroStaticFramework() throws {
        // Given
        let projectSettings = Settings.default
        let app = Target.test(name: "app", platform: .iOS, product: .app)
        let macroFramework = Target.test(name: "framework", platform: .macOS, product: .staticFramework)
        let macroExecutable = Target.test(name: "macro", platform: .macOS, product: .macro)
        let project = Project.test(targets: [app, macroFramework, macroExecutable])

        let graph = Graph.test(path: project.path, projects: [project.path: project], targets: [
            project.path: [
                app.name: app,
                macroFramework.name: macroFramework,
                macroExecutable.name: macroExecutable,
            ],
        ], dependencies: [
            .target(name: app.name, path: project.path): Set([.target(name: macroFramework.name, path: project.path)]),
            .target(name: macroFramework.name, path: project.path): Set([.target(
                name: macroExecutable.name,
                path: project.path
            )]),
            .target(name: macroExecutable.name, path: project.path): Set([]),
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
        let targetSettingsResult = try pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]
        XCTAssertEqual(
            targetSettingsResult,
            .array([
                "-load-plugin-executable",
                "$BUILD_DIR/Debug$EFFECTIVE_PLATFORM_NAME/\(macroExecutable.productName)#\(macroExecutable.productName)",
            ])
        )
    }

    func test_generateTargetConfig_doesntAddTheLoadPluginExecutableSwiftFlag_when_theTargetDependsOnAStaticFrameworkThatDoesntRepresentAMacro(
    ) throws {
        // Given
        let projectSettings = Settings.default
        let app = Target.test(name: "app", platform: .iOS, product: .app)
        let macroFramework = Target.test(name: "framework", platform: .macOS, product: .staticFramework)
        let project = Project.test(targets: [app, macroFramework])

        let graph = Graph.test(path: project.path, projects: [project.path: project], targets: [
            project.path: [
                app.name: app,
                macroFramework.name: macroFramework,
            ],
        ], dependencies: [
            .target(name: app.name, path: project.path): Set([.target(name: macroFramework.name, path: project.path)]),
            .target(name: macroFramework.name, path: project.path): Set([]),
        ])
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        try subject.generateTargetConfig(
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
        let targetSettingsResult = try pbxTarget
            .buildConfigurationList?
            .buildConfigurations
            .first { $0.name == "Debug" }?
            .buildSettings
            .toSettings()["OTHER_SWIFT_FLAGS"]
        XCTAssertEqual(targetSettingsResult, nil)
    }

    // MARK: - Helpers

    private func generateProjectConfig(config _: BuildConfiguration) throws {
        let dir = try temporaryPath()
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
        _ = try subject.generateProjectConfig(
            project: project,
            pbxproj: pbxproj,
            fileElements: fileElements
        )
    }

    private func generateTargetConfig() throws {
        let dir = try temporaryPath()
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
        _ = try subject.generateTargetConfig(
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
        uiTest: Bool = false
    ) throws {
        let dir = try temporaryPath()

        let appTarget = Target.test(
            name: appName,
            destinations: destinations,
            product: .app,
            productName: productName
        )

        let target = Target.test(name: "Test", destinations: destinations, product: uiTest ? .uiTests : .unitTests)
        let project = Project.test(path: dir, name: "Project", targets: [target])

        let graph = Graph.test(
            name: project.name,
            path: project.path,
            projects: [project.path: project],
            targets: [project.path: [appTarget.name: appTarget, target.name: target]],
            dependencies: [
                GraphDependency
                    .target(name: target.name, path: project.path): Set([.target(name: appTarget.name, path: project.path)]),
            ]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        _ = try subject.generateTargetConfig(
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
        contains settings: [String: SettingValue],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let matches = settings.filter {
            if let stringValue = config?.buildSettings[$0.key] as? String {
                return $0.value == .string(stringValue)
            } else if let arrayValue = config?.buildSettings[$0.key] as? [String] {
                return $0.value == .array(arrayValue)
            } else {
                return false
            }
        }

        XCTAssertEqual(
            matches.count,
            settings.count,
            "Settings \(String(describing: config?.buildSettings)) do not contain expected settings \(settings)",
            file: file,
            line: line
        )
    }

    func assert(
        config: XCBuildConfiguration?,
        hasXcconfig xconfigPath: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let xcconfig: PBXFileReference? = config?.baseConfiguration
        XCTAssertEqual(
            xcconfig?.path,
            xconfigPath,
            file: file,
            line: line
        )
    }
}
