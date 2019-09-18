import Basic
import Foundation
import TuistCore
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class ConfigGeneratorTests: XCTestCase {
    var pbxproj: PBXProj!
    var graph: Graph!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
        subject = ConfigGenerator()
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
        let commonSettings = [
            "Base": "Base",
            "INFOPLIST_FILE": "$(SRCROOT)/Info.plist",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.test.bundle_id",
            "CODE_SIGN_ENTITLEMENTS": "$(SRCROOT)/Test.entitlements",
            "SWIFT_VERSION": Constants.swiftVersion,
        ]

        let debugSettings = [
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        ]

        let releaseSettings = [
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

    func test_generateTestTargetConfiguration() throws {
        // Given / When
        try generateTestTargetConfig()

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/App",
            "BUNDLE_LOADER": "$(TEST_HOST)",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    func test_generateUITestTargetConfiguration() throws {
        // Given / When
        try generateTestTargetConfig(uiTest: true)

        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        let testHostSettings = [
            "TEST_TARGET_NAME": "App",
        ]

        assert(config: debugConfig, contains: testHostSettings)
        assert(config: releaseConfig, contains: testHostSettings)
    }

    private func generateProjectConfig(config _: BuildConfiguration) throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try fileHandler.createFolder(xcconfigsDir)
        try "".write(to: xcconfigsDir.appending(component: "debug.xcconfig").url, atomically: true, encoding: .utf8)
        try "".write(to: xcconfigsDir.appending(component: "release.xcconfig").url, atomically: true, encoding: .utf8)

        // CustomDebug, CustomRelease, Debug, Release
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug: Configuration(settings: ["Debug": "Debug"],
                                  xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
            .debug("CustomDebug"): Configuration(settings: ["CustomDebug": "CustomDebug"], xcconfig: nil),
            .release: Configuration(settings: ["Release": "Release"],
                                    xcconfig: xcconfigsDir.appending(component: "release.xcconfig")),
            .release("CustomRelease"): Configuration(settings: ["CustomRelease": "CustomRelease"], xcconfig: nil),
        ]
        let project = Project.test(path: dir.path,
                                   name: "Test",
                                   settings: Settings(base: ["Base": "Base"], configurations: configurations),
                                   targets: [])
        let fileElements = ProjectFileElements()
        _ = try subject.generateProjectConfig(project: project,
                                              pbxproj: pbxproj,
                                              fileElements: fileElements)
    }

    private func generateTargetConfig() throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try fileHandler.createFolder(xcconfigsDir)
        try "".write(to: xcconfigsDir.appending(component: "debug.xcconfig").url, atomically: true, encoding: .utf8)
        try "".write(to: xcconfigsDir.appending(component: "release.xcconfig").url, atomically: true, encoding: .utf8)
        let configurations: [BuildConfiguration: Configuration?] = [
            .debug: Configuration(settings: ["Debug": "Debug"],
                                  xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
            .debug("CustomDebug"): Configuration(settings: ["CustomDebug": "CustomDebug"], xcconfig: nil),
            .release: Configuration(settings: ["Release": "Release"],
                                    xcconfig: xcconfigsDir.appending(component: "release.xcconfig")),
            .release("CustomRelease"): Configuration(settings: ["CustomRelease": "CustomRelease"], xcconfig: nil),
        ]
        let target = Target.test(name: "Test",
                                 settings: Settings(base: ["Base": "Base"], configurations: configurations))
        let project = Project.test(path: dir.path,
                                   name: "Test",
                                   settings: .default,
                                   targets: [target])
        let fileElements = ProjectFileElements()
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: dir.path)
        let graph = Graph.test()
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: project.path)
        _ = try subject.generateTargetConfig(target,
                                             pbxTarget: pbxTarget,
                                             pbxproj: pbxproj,
                                             projectSettings: project.settings,
                                             fileElements: fileElements,
                                             graph: graph,
                                             sourceRootPath: AbsolutePath("/"))
    }

    private func generateTestTargetConfig(uiTest: Bool = false) throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)

        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)

        let target = Target.test(name: "Test", product: uiTest ? .uiTests : .unitTests)
        let project = Project.test(path: dir.path, name: "Project", targets: [target])

        let appTargetNode = TargetNode(project: project, target: appTarget, dependencies: [])
        let testTargetNode = TargetNode(project: project, target: target, dependencies: [appTargetNode])

        let graph = Graph.test(entryNodes: [appTargetNode, testTargetNode])

        _ = try subject.generateTargetConfig(target,
                                             pbxTarget: pbxTarget,
                                             pbxproj: pbxproj,
                                             projectSettings: project.settings,
                                             fileElements: .init(),
                                             graph: graph,
                                             sourceRootPath: dir.path)
    }

    // MARK: - Helpers

    func assert(config: XCBuildConfiguration?,
                contains settings: [String: String],
                file: StaticString = #file,
                line: UInt = #line) {
        let matches = settings.filter {
            config?.buildSettings[$0.key] as? String == $0.value
        }

        XCTAssertEqual(matches.count,
                       settings.count,
                       "Settings \(String(describing: config?.buildSettings)) do not contain expected settings \(settings)",
                       file: file,
                       line: line)
    }

    func assert(config: XCBuildConfiguration?,
                hasXcconfig xconfigPath: String,
                file: StaticString = #file,
                line: UInt = #line) {
        let xcconfig: PBXFileReference? = config?.baseConfiguration
        XCTAssertEqual(xcconfig?.path,
                       xconfigPath,
                       file: file,
                       line: line)
    }
}
