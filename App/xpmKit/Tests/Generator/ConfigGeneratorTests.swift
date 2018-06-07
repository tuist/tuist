import Basic
import Foundation
@testable import xcodeproj
import XCTest
@testable import xpmKit

final class ConfigGeneratorTests: XCTestCase {
    var pbxproj: PBXProj!
    var context: GeneratorContexting!
    var graph: Graph!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.objects.addObject(pbxTarget)
        context = GeneratorContext(graph: Graph.test())
        subject = ConfigGenerator()
    }

    func test_generateProjectConfig_whenDebug() throws {
        _ = try generateProjectConfig(config: .debug)
        XCTAssertEqual(pbxproj.objects.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.objects.configurationLists.first!.value

        let debugConfig: XCBuildConfiguration = try configurationList.buildConfigurationsReferences.first!.object()
        XCTAssertEqual(debugConfig.name, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateProjectConfig_whenRelease() throws {
        _ = try generateProjectConfig(config: .release)

        XCTAssertEqual(pbxproj.objects.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.objects.configurationLists.first!.value

        let releaseConfig: XCBuildConfiguration = try configurationList.buildConfigurationsReferences.last!.object()
        XCTAssertEqual(releaseConfig.name, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateTargetConfig_whenDebug() throws {
        _ = try generateTargetConfig(config: .debug)
        let configurationList = try pbxTarget.buildConfigurationList()
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Debug")
        XCTAssertEqual(config?.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(config?.buildSettings["Debug"] as? String, "Debug")
        let xcconfig: PBXFileReference? = try config?.baseConfigurationReference?.object()
        XCTAssertEqual(xcconfig?.path, "debug.xcconfig")
    }

    func test_generateTargetConfig_whenRelease() throws {
        _ = try generateTargetConfig(config: .release)
        let configurationList = try pbxTarget.buildConfigurationList()
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Release")
        XCTAssertEqual(config?.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(config?.buildSettings["Release"] as? String, "Release")
        let xcconfig: PBXFileReference? = try config?.baseConfigurationReference?.object()
        XCTAssertEqual(xcconfig?.path, "release.xcconfig")
    }

    private func generateProjectConfig(config _: BuildConfiguration) throws -> ProjectGroups {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try xcconfigsDir.mkpath()
        try xcconfigsDir.appending(component: "debug.xcconfig").write("")
        try xcconfigsDir.appending(component: "release.xcconfig").write("")
        let project = Project(path: dir.path,
                              name: "Test",
                              schemes: [],
                              settings: Settings(base: ["Base": "Base"],
                                                 debug: Configuration(settings: ["Debug": "Debug"],
                                                                      xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                 release: Configuration(settings: ["Release": "Release"],
                                                                        xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))),
                              targets: [])
        let fileElements = ProjectFileElements()
        let groups = ProjectGroups.generate(project: project, objects: pbxproj.objects, sourceRootPath: dir.path)
        let options = GenerationOptions(buildConfiguration: .debug)
        _ = try subject.generateProjectConfig(project: project,
                                              objects: pbxproj.objects,
                                              fileElements: fileElements,
                                              options: options)
        return groups
    }

    private func generateTargetConfig(config: BuildConfiguration) throws -> ProjectGroups {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try xcconfigsDir.mkpath()
        try xcconfigsDir.appending(component: "debug.xcconfig").write("")
        try xcconfigsDir.appending(component: "release.xcconfig").write("")
        let target = Target.test(name: "Test",
                                 settings: Settings(base: ["Base": "Base"],
                                                    debug: Configuration(settings: ["Debug": "Debug"],
                                                                         xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                    release: Configuration(settings: ["Release": "Release"],
                                                                           xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))))
        let project = Project(path: dir.path,
                              name: "Test",
                              schemes: [],
                              settings: nil,
                              targets: [target])
        let fileElements = ProjectFileElements()
        let groups = ProjectGroups.generate(project: project, objects: pbxproj.objects, sourceRootPath: dir.path)
        let graph = Graph.test()
        fileElements.generateProjectFiles(project: project,
                                          graph: graph,
                                          groups: groups,
                                          objects: pbxproj.objects,
                                          sourceRootPath: project.path)
        let options = GenerationOptions(buildConfiguration: config)
        _ = try subject.generateTargetConfig(target,
                                             pbxTarget: pbxTarget,
                                             objects: pbxproj.objects,
                                             fileElements: fileElements,
                                             options: options)
        return groups
    }
}
