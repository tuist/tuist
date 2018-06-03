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

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
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

    private func generateProjectConfig(config: BuildConfiguration) throws -> ProjectGroups {
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
        _ = try subject.generateProjectConfig(project: project,
                                              pbxproj: pbxproj,
                                              groups: groups,
                                              fileElements: fileElements,
                                              sourceRootPath: dir.path,
                                              context: context,
                                              options: GenerationOptions(buildConfiguration: config))
        return groups
    }
}
