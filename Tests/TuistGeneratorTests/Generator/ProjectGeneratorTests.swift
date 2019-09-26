import Basic
import Foundation
import TuistCore
import XcodeProj
import XCTest
import SPMUtility

@testable import TuistCoreTesting
@testable import TuistGenerator

final class ProjectGeneratorTests: XCTestCase {
    var subject: ProjectGenerator!
    var system: MockSystem!
    var fileHandler: MockFileHandler!
    var xcodeController: MockXcodeController!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()
        xcodeController = sharedMockXcodeController()

        system = MockSystem()
        subject = ProjectGenerator(system: system)
    }

    func test_generate() throws {
        // Given
        let target = Target.test(name: "Target", platform: .iOS, product: .framework, infoPlist: .dictionary(["a": "b"]))
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
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let schemesPath = got.path.appending(RelativePath("xcshareddata/xcschemes"))
        let targetScheme = schemesPath.appending(component: "Target.xcscheme")
        XCTAssertTrue(fileHandler.exists(targetScheme))
        XCTAssertTrue(fileHandler.exists(got.path.appending(RelativePath("../Derived/InfoPlists/Target.plist"))))
    }

    func test_generate_scheme() throws {
        // Given
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let sharedScheme = Scheme.test(name: "Target-Scheme", shared: true, buildAction: BuildAction(targets: ["Target"]))

        let targets = [target]
        let project = Project.test(path: fileHandler.currentPath, name: "Project", targets: targets, schemes: [sharedScheme])
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: fileHandler.currentPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let schemesPath = got.path.appending(RelativePath("xcshareddata/xcschemes"))
        let targetScheme = schemesPath.appending(component: "Target-Scheme.xcscheme")
        XCTAssertTrue(fileHandler.exists(targetScheme))
    }

    func test_generate_local_scheme() throws {
        // Given
        let target = Target.test(name: "Target", platform: .iOS, product: .framework)
        let localScheme = Scheme.test(name: "Target-Local", shared: false, buildAction: BuildAction(targets: ["Target"]))

        let targets = [target]
        let project = Project.test(path: fileHandler.currentPath, name: "Project", targets: targets, schemes: [localScheme])
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))

        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: fileHandler.currentPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
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
        let generatedProject = try subject.generate(project: project, graph: graph)

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

    func test_generate_testUsingFileName() throws {
        // Given
        let project = Project.test(path: fileHandler.currentPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        try fileHandler.touch(fileHandler.currentPath.appending(component: "Project.swift"))
        let target = Target.test()
        let cache = GraphLoaderCache()
        cache.add(project: project)
        let graph = Graph.test(entryPath: fileHandler.currentPath,
                               cache: cache,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [])])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertTrue(fileHandler.exists(got.path))
        XCTAssertEqual(got.path.components.last, "SomeAwesomeName.xcodeproj")
        XCTAssertEqual(project.name, "Project")
    }
    
    func test_objectVersion_when_xcode11() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))
        
        // Given
        let project = Project.test(path: fileHandler.currentPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: fileHandler.currentPath)
        
        // When
        let got = try subject.generate(project: project, graph: graph)
        
        // Then
        XCTAssertEqual(got.pbxproj.objectVersion, 52)
        XCTAssertEqual(got.pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }
    
    func test_objectVersion_when_xcode10() throws {
        xcodeController.selectedVersionStub = .success(Version(10, 2, 1))
        
        // Given
        let project = Project.test(path: fileHandler.currentPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: fileHandler.currentPath)
        
        // When
        let got = try subject.generate(project: project, graph: graph)
        
        // Then
        XCTAssertEqual(got.pbxproj.objectVersion, 50)
        XCTAssertEqual(got.pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }
}
