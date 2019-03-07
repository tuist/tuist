import Basic
import Foundation
import TuistCore
import xcodeproj
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class ProjectGeneratorTests: XCTestCase {
    var subject: ProjectGenerator!
    var targetGenerator: MockTargetGenerator!
    var configGenerator: ConfigGenerator!
    var printer: MockPrinter!
    var system: MockSystem!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        targetGenerator = MockTargetGenerator()
        configGenerator = ConfigGenerator()
        printer = MockPrinter()
        system = MockSystem()
        fileHandler = try! MockFileHandler()
        subject = ProjectGenerator(targetGenerator: targetGenerator,
                                   configGenerator: configGenerator,
                                   printer: printer,
                                   system: system,
                                   resourceLocator: MockResourceLocator(),
                                   fileHandler: fileHandler)
    }

    func test_generate() throws {
        // Given
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let targets = [target]
        let project = Project.test(path: fileHandler.currentPath, name: "Project", targets: targets)
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: fileHandler.currentPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project,
                                       options: GenerationOptions(),
                                       graph: graph)

        // Then
        let schemesPath = got.path.appending(RelativePath("xcshareddata/xcschemes"))
        let projectScheme = schemesPath.appending(component: "Project-Project.xcscheme")
        let targetScheme = schemesPath.appending(component: "Target.xcscheme")
        XCTAssertTrue(fileHandler.exists(projectScheme))
        XCTAssertTrue(fileHandler.exists(targetScheme))
    }

    func test_generate_defaultGroupsOrder() throws {
        // Given
        let project = Project.test()

        // When
        let path = try subject.generate(project: project,
                                        options: GenerationOptions(),
                                        graph: Graph.test(),
                                        sourceRootPath: fileHandler.currentPath)

        // Then
        let xcodeproj = try XcodeProj(pathString: path.path.asString)
        let mainGroup = try xcodeproj.pbxproj.rootGroup()
        XCTAssertEqual(mainGroup?.children.map { $0.nameOrPath }, [
            "Project",
            "Manifest",
            "Frameworks",
            "Products",
        ])
    }

    func test_generate_customGroupsOrder() throws {
        // Given
        let path = fileHandler.currentPath
        let infoPlist = path.appending(component: "Info.plist")
        let sources = [
            path.appending(RelativePath("Sources/c.swift")),
            path.appending(RelativePath("Mocks/d.swift")),
            path.appending(RelativePath("Sources/component/b.swift")),
            path.appending(RelativePath("root.swift")),
        ]
        let target = Target.test(infoPlist: infoPlist,
                                 entitlements: nil,
                                 settings: nil,
                                 sources: sources,
                                 resources: [],
                                 projectStructure: ProjectStructure(filesGroup: nil))
        let project = Project.test(path: fileHandler.currentPath,
                                   settings: nil,
                                   projectStructure: ProjectStructure(filesGroup: nil),
                                   targets: [target])

        // When
        let xcodeProjectPath = try subject.generate(project: project,
                                                    options: GenerationOptions(),
                                                    graph: Graph.test(),
                                                    sourceRootPath: fileHandler.currentPath)

        // Then
        let xcodeproj = try XcodeProj(pathString: xcodeProjectPath.path.asString)
        let mainGroup = try xcodeproj.pbxproj.rootGroup()
        XCTAssertEqual(mainGroup?.children.map { $0.nameOrPath }, [
            "Info.plist",
            "root.swift",
            "Mocks",
            "Sources",
            "Manifest",
            "Frameworks",
            "Products",
        ])
    }
}
