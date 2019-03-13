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
        try generateTargetConfig(config: .release)
        let configurationList = pbxTarget.buildConfigurationList
        let debugConfig = configurationList?.configuration(name: "Debug")
        let releaseConfig = configurationList?.configuration(name: "Release")

        func assert(config: XCBuildConfiguration?) {
            XCTAssertEqual(config?.buildSettings["Base"] as? String, "Base")
            XCTAssertEqual(config?.buildSettings["INFOPLIST_FILE"] as? String, "$(SRCROOT)/Info.plist")
            XCTAssertEqual(config?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String, "com.test.bundle_id")
            XCTAssertEqual(config?.buildSettings["CODE_SIGN_ENTITLEMENTS"] as? String, "$(SRCROOT)/Test.entitlements")
            XCTAssertEqual(config?.buildSettings["SWIFT_VERSION"] as? String, Constants.swiftVersion)

            let xcconfig: PBXFileReference? = config?.baseConfiguration
            XCTAssertEqual(xcconfig?.path, "\(config!.name.lowercased()).xcconfig")
        }

        assert(config: debugConfig)
        assert(config: releaseConfig)
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

    private func generateTargetConfig(config _: BuildConfiguration) throws {
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
                                             options: options,
                                             sourceRootPath: AbsolutePath("/"))
    }
}
