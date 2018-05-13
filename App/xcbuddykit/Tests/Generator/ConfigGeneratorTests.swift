import Basic
import Foundation
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

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

    func testGenerateProjectConfig() throws {
        let groups = try generateProjectConfig()

        let configurationsGroup: PBXGroup = try groups.projectConfigurations()
        XCTAssertEqual(configurationsGroup.name, "Project")
        XCTAssertEqual(configurationsGroup.sourceTree, .group)
        XCTAssertNil(configurationsGroup.path)

        XCTAssertEqual(configurationsGroup.children.count, 2)

        let debugxcconfig: PBXFileReference = try configurationsGroup.children.first!.object()
        XCTAssertEqual(debugxcconfig.name, "debug.xcconfig")
        XCTAssertEqual(debugxcconfig.path, "xcconfigs/debug.xcconfig")
        XCTAssertEqual(debugxcconfig.sourceTree, .group)

        let releasexcconfig: PBXFileReference = try configurationsGroup.children.last!.object()
        XCTAssertEqual(releasexcconfig.name, "release.xcconfig")
        XCTAssertEqual(releasexcconfig.path, "xcconfigs/release.xcconfig")
        XCTAssertEqual(releasexcconfig.sourceTree, .group)

        XCTAssertEqual(pbxproj.objects.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.objects.configurationLists.first!.value

        let debugConfig: XCBuildConfiguration = try configurationList.buildConfigurations.first!.object()
        XCTAssertEqual(debugConfig.name, "Debug")
        XCTAssertTrue(debugConfig.baseConfigurationReference === debugxcconfig.reference)
        XCTAssertEqual(debugConfig.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Base"] as? String, "Base")

        let releaseConfig: XCBuildConfiguration = try configurationList.buildConfigurations.last!.object()
        XCTAssertEqual(releaseConfig.name, "Release")
        XCTAssertTrue(releaseConfig.baseConfigurationReference === releasexcconfig.reference)
        XCTAssertEqual(releaseConfig.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Base"] as? String, "Base")
    }

    private func generateProjectConfig() throws -> ProjectGroups {
        let dir = try TemporaryDirectory()
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try xcconfigsDir.mkpath()
        try xcconfigsDir.appending(component: "debug.xcconfig").write("")
        try xcconfigsDir.appending(component: "release.xcconfig").write("")
        let project = Project(path: dir.path,
                              name: "Test",
                              config: nil,
                              schemes: [],
                              settings: Settings(base: ["Base": "Base"],
                                                 debug: Configuration(settings: ["Debug": "Debug"],
                                                                      xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                 release: Configuration(settings: ["Release": "Release"],
                                                                        xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))),
                              targets: [])
        let groups = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: dir.path)
        _ = try subject.generateProjectConfig(project: project,
                                              pbxproj: pbxproj,
                                              groups: groups,
                                              sourceRootPath: dir.path,
                                              context: context)
        return groups
    }
}
