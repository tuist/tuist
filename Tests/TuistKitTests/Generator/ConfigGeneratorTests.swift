import Basic
import Foundation
import TuistCore
import xcodeproj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class ConfigGeneratorTests: XCTestCase {
    var pbxproj: PBXProj!
    var graph: Graph!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.add(object: pbxTarget)
        fileHandler = try! MockFileHandler()
        subject = ConfigGenerator()
    }

    func test_generateProjectConfig_whenDebug() throws {
        try generateProjectConfig(config: .debug)
        XCTAssertEqual(pbxproj.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let debugConfig: XCBuildConfiguration = configurationList.buildConfigurations.first!
        XCTAssertEqual(debugConfig.name, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateProjectConfig_whenRelease() throws {
        try generateProjectConfig(config: .release)

        XCTAssertEqual(pbxproj.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.configurationLists.first!

        let releaseConfig: XCBuildConfiguration = configurationList.buildConfigurations.last!
        XCTAssertEqual(releaseConfig.name, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateTargetConfig() throws {
        // Given / When
        try generateTargetConfig()

        // Then
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

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
        
        assert(config: debugConfig, contains: commonSettings)
        assert(config: debugConfig, contains: debugSettings)
        assert(config: debugConfig, hasXcconfig: "debug.xcconfig")

        assert(config: releaseConfig, contains: commonSettings)
        assert(config: releaseConfig, contains: releaseSettings)
        assert(config: releaseConfig, hasXcconfig: "release.xcconfig")
    }
    
    func test_generateTestTargetConfiguration() throws {
        
        // Given / When
        try generateTestTargetConfig()
        
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")
        
        let testHostSettings = [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/App",
            "BUNDLE_LOADER": "$(TEST_HOST)"
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
        let project = Project.test(path: dir.path,
                                   name: "Test",
                                   settings: Settings(base: ["Base": "Base"],
                                                      debug: Configuration(settings: ["Debug": "Debug"],
                                                                           xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                      release: Configuration(settings: ["Release": "Release"],
                                                                             xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))),
                                   targets: [])
        let fileElements = ProjectFileElements()
        let options = GenerationOptions()
        _ = try subject.generateProjectConfig(project: project,
                                              pbxproj: pbxproj,
                                              fileElements: fileElements,
                                              options: options)
    }

    private func generateTargetConfig() throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try fileHandler.createFolder(xcconfigsDir)
        try "".write(to: xcconfigsDir.appending(component: "debug.xcconfig").url, atomically: true, encoding: .utf8)
        try "".write(to: xcconfigsDir.appending(component: "release.xcconfig").url, atomically: true, encoding: .utf8)
        let target = Target.test(name: "Test",
                                 settings: Settings(base: ["Base": "Base"],
                                                    debug: Configuration(settings: ["Debug": "Debug"],
                                                                         xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                    release: Configuration(settings: ["Release": "Release"],
                                                                           xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))))
        let project = Project.test(path: dir.path,
                                   name: "Test",
                                   settings: nil,
                                   targets: [target])
        let fileElements = ProjectFileElements()
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: dir.path)
        let graph = Graph.test()
        try fileElements.generateProjectFiles(project: project,
                                              graph: graph,
                                              groups: groups,
                                              pbxproj: pbxproj,
                                              sourceRootPath: project.path)
        let options = GenerationOptions()
        _ = try subject.generateTargetConfig(target,
                                             pbxTarget: pbxTarget,
                                             pbxproj: pbxproj,
                                             fileElements: fileElements,
                                             graph: graph,
                                             options: options,
                                             sourceRootPath: AbsolutePath("/"))
    }
    
    private func generateTestTargetConfig() throws {
        
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        
        let appTarget = Target.test(name: "App", platform: .iOS, product: .app)
        
        let target = Target.test(name: "Test", product: .unitTests)
        let project = Project.test(path: dir.path, name: "Project", targets: [target])
        
        let appTargetNode = TargetNode(project: project, target: appTarget, dependencies: [ ])
        let testTargetNode = TargetNode(project: project, target: target, dependencies: [ appTargetNode ])
        
        let graph = Graph.test(entryNodes: [ appTargetNode, testTargetNode ])

        _ = try subject.generateTargetConfig(target,
                                             pbxTarget: pbxTarget,
                                             pbxproj: pbxproj,
                                             fileElements: .init(),
                                             graph: graph,
                                             options: .init(),
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
