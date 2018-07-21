import Basic
import Foundation
@testable import xcodeproj
import XCTest
@testable import xpmkit

final class ConfigGeneratorTests: XCTestCase {
    var pbxproj: PBXProj!
    var context: GeneratorContexting!
    var graph: Graph!
    var subject: ConfigGenerator!
    var pbxTarget: PBXNativeTarget!
    var resourceLocator: MockResourceLocator!

    override func setUp() {
        super.setUp()
        pbxproj = PBXProj()
        pbxTarget = PBXNativeTarget(name: "Test")
        pbxproj.objects.addObject(pbxTarget)
        resourceLocator = MockResourceLocator()
        context = GeneratorContext(graph: Graph.test(),
                                   resourceLocator: resourceLocator)
        resourceLocator.projectDescriptionStub = { AbsolutePath("/test/ProjectDescription.dylib") }
        subject = ConfigGenerator()
    }

    func test_generateProjectConfig_whenDebug() throws {
        try generateProjectConfig(config: .debug)
        XCTAssertEqual(pbxproj.objects.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.objects.configurationLists.first!.value

        let debugConfig: XCBuildConfiguration = try configurationList.buildConfigurationsReferences.first!.object()
        XCTAssertEqual(debugConfig.name, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(debugConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateProjectConfig_whenRelease() throws {
        try generateProjectConfig(config: .release)

        XCTAssertEqual(pbxproj.objects.configurationLists.count, 1)
        let configurationList: XCConfigurationList = pbxproj.objects.configurationLists.first!.value

        let releaseConfig: XCBuildConfiguration = try configurationList.buildConfigurationsReferences.last!.object()
        XCTAssertEqual(releaseConfig.name, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(releaseConfig.buildSettings["Base"] as? String, "Base")
    }

    func test_generateManifestsConfig_whenDebug() throws {
        try generateManifestsConfig(config: .debug)
        let configurationList = pbxproj.objects.configurationLists.first?.value
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Debug")
        XCTAssertEqual(config?.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["LIBRARY_SEARCH_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] as? Bool, true)
        XCTAssertEqual(config?.buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] as? Bool, false)
        XCTAssertEqual(config?.buildSettings["SWIFT_INCLUDE_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["SWIFT_VERSION"] as? String, Constants.swiftVersion)
        XCTAssertEqual(config?.buildSettings["LD"] as? String, "/usr/bin/true")
        XCTAssertEqual(config?.buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] as? String, "SWIFT_PACKAGE")
        XCTAssertEqual(config?.buildSettings["OTHER_SWIFT_FLAGS"] as? String, "-swift-version 4 -I /test")
    }

    func test_generateManifestsConfig_whenRelease() throws {
        try generateManifestsConfig(config: .release)
        let configurationList = pbxproj.objects.configurationLists.first?.value
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Release")
        XCTAssertEqual(config?.buildSettings["FRAMEWORK_SEARCH_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["LIBRARY_SEARCH_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["SWIFT_FORCE_DYNAMIC_LINK_STDLIB"] as? Bool, true)
        XCTAssertEqual(config?.buildSettings["SWIFT_FORCE_STATIC_LINK_STDLIB"] as? Bool, false)
        XCTAssertEqual(config?.buildSettings["SWIFT_INCLUDE_PATHS"] as? String, "/test")
        XCTAssertEqual(config?.buildSettings["SWIFT_VERSION"] as? String, Constants.swiftVersion)
        XCTAssertEqual(config?.buildSettings["LD"] as? String, "/usr/bin/true")
        XCTAssertEqual(config?.buildSettings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] as? String, "SWIFT_PACKAGE")
        XCTAssertEqual(config?.buildSettings["OTHER_SWIFT_FLAGS"] as? String, "-swift-version 4 -I /test")
    }

    func test_generateTargetConfig_whenDebug() throws {
        try generateTargetConfig(config: .debug)
        let configurationList = try pbxTarget.buildConfigurationList()
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Debug")
        XCTAssertEqual(config?.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(config?.buildSettings["Debug"] as? String, "Debug")
        XCTAssertEqual(config?.buildSettings["INFOPLIST_FILE"] as? String, "$(SRCROOT)/Info.plist")
        XCTAssertEqual(config?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String, "com.test.bundle_id")
        XCTAssertEqual(config?.buildSettings["CODE_SIGN_ENTITLEMENTS"] as? String, "$(SRCROOT)/Test.entitlements")
        XCTAssertEqual(config?.buildSettings["SWIFT_VERSION"] as? String, Constants.swiftVersion)

        let xcconfig: PBXFileReference? = try config?.baseConfigurationReference?.object()
        XCTAssertEqual(xcconfig?.path, "debug.xcconfig")
    }

    func test_generateTargetConfig_whenRelease() throws {
        try generateTargetConfig(config: .release)
        let configurationList = try pbxTarget.buildConfigurationList()
        let config = try configurationList?.buildConfigurations().first
        XCTAssertEqual(config?.name, "Release")
        XCTAssertEqual(config?.buildSettings["Base"] as? String, "Base")
        XCTAssertEqual(config?.buildSettings["Release"] as? String, "Release")
        XCTAssertEqual(config?.buildSettings["INFOPLIST_FILE"] as? String, "$(SRCROOT)/Info.plist")
        XCTAssertEqual(config?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] as? String, "com.test.bundle_id")
        XCTAssertEqual(config?.buildSettings["CODE_SIGN_ENTITLEMENTS"] as? String, "$(SRCROOT)/Test.entitlements")
        XCTAssertEqual(config?.buildSettings["SWIFT_VERSION"] as? String, Constants.swiftVersion)

        let xcconfig: PBXFileReference? = try config?.baseConfigurationReference?.object()
        XCTAssertEqual(xcconfig?.path, "release.xcconfig")
    }

    private func generateProjectConfig(config: BuildConfiguration) throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try xcconfigsDir.mkpath()
        try xcconfigsDir.appending(component: "debug.xcconfig").write("")
        try xcconfigsDir.appending(component: "release.xcconfig").write("")
        let project = Project(path: dir.path,
                              name: "Test",
                              settings: Settings(base: ["Base": "Base"],
                                                 debug: Configuration(settings: ["Debug": "Debug"],
                                                                      xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                 release: Configuration(settings: ["Release": "Release"],
                                                                        xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))),
                              targets: [])
        let fileElements = ProjectFileElements()
        let options = GenerationOptions(buildConfiguration: config)
        _ = try subject.generateProjectConfig(project: project,
                                              objects: pbxproj.objects,
                                              fileElements: fileElements,
                                              options: options)
    }

    private func generateManifestsConfig(config: BuildConfiguration) throws {
        let options = GenerationOptions(buildConfiguration: config)
        _ = try subject.generateManifestsConfig(pbxproj: pbxproj,
                                                context: context,
                                                options: options)
    }

    private func generateTargetConfig(config: BuildConfiguration) throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let xcconfigsDir = dir.path.appending(component: "xcconfigs")
        try xcconfigsDir.mkpath()
        try xcconfigsDir.appending(component: "debug.xcconfig").write("")
        try dir.path.appending(component: "release.xcconfig").write("")
        let target = Target.test(name: "Test",
                                 settings: Settings(base: ["Base": "Base"],
                                                    debug: Configuration(settings: ["Debug": "Debug"],
                                                                         xcconfig: xcconfigsDir.appending(component: "debug.xcconfig")),
                                                    release: Configuration(settings: ["Release": "Release"],
                                                                           xcconfig: xcconfigsDir.appending(component: "release.xcconfig"))))
        let project = Project(path: dir.path,
                              name: "Test",
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
                                             options: options,
                                             sourceRootPath: AbsolutePath("/"))
    }
}
