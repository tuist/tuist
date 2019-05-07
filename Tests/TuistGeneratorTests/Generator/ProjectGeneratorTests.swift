import Basic
import Foundation
import TuistCore
import XcodeProj
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class ProjectGeneratorTests: XCTestCase {
    var subject: ProjectGenerator!
    var printer: MockPrinter!
    var system: MockSystem!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        system = MockSystem()
        fileHandler = try! MockFileHandler()
        subject = ProjectGenerator(printer: printer,
                                   system: system)
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
        let targetScheme = schemesPath.appending(component: "Target.xcscheme")
        XCTAssertTrue(fileHandler.exists(targetScheme))
    }

    func test_generate_scheme() throws {
        // Given
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let sharedScheme = Scheme.test(name: "Target-Scheme", shared: true, buildAction: BuildAction(targets: ["Target"]))
        let localScheme = Scheme.test(name: "Target-Local", shared: false, buildAction: BuildAction(targets: ["Target"]))

        let targets = [target]
        let project = Project.test(path: fileHandler.currentPath, name: "Project", targets: targets, schemes: [sharedScheme, localScheme])
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
        let scheme = schemesPath.appending(component: "Target-Scheme.xcscheme")
        XCTAssertTrue(fileHandler.exists(scheme))
        
        let username = NSUserName()
        let userSchemesPath = got.path.appending(RelativePath("xcuserdata/\(username).xcuserdatad/xcschemes"))
        let userScheme = userSchemesPath.appending(component: "Target-Local.xcscheme")
        XCTAssertTrue(fileHandler.exists(userScheme))
    }

    func test_generate_testTargetIdentity() throws {
        // Given
        let app = Target.test(name: "App",
                              platform: .iOS,
                              product: .app)
        let test = Target.test(name: "Tests",
                               platform: .iOS,
                               product: .unitTests)
        let project = Project.test(path: fileHandler.currentPath,
                                   name: "Project",
                                   targets: [app, test])

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: fileHandler.currentPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: test,
                                                       dependencies: [
                                                           TargetNode(project: project, target: app, dependencies: []),
                                                       ])])

        // When
        let generatedProject = try subject.generate(project: project,
                                                    options: GenerationOptions(),
                                                    graph: graph)

        // Then
        let pbxproject = try generatedProject.pbxproj.rootProject()
        let nativeTargets = generatedProject.targets
        let attributes = pbxproject?.targetAttributes ?? [:]
        XCTAssertTrue(attributes.contains { attribute in

            guard let app = nativeTargets["App"], let testTargetID = attribute.value["TestTargetID"] as? PBXNativeTarget else {
                return false
            }

            return attribute.key.name == "Tests" && testTargetID == app

        }, "Test target is missing from target attributes.")
    }
}
