import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ProjectGeneratorTests: TuistUnitTestCase {
    var subject: ProjectGenerator!

    override func setUp() {
        super.setUp()
        system.swiftVersionStub = { "5.2" }
        subject = ProjectGenerator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_generate_testTargetIdentity() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let app = Target.test(name: "App",
                              platform: .iOS,
                              product: .app)
        let test = Target.test(name: "Tests",
                               platform: .iOS,
                               product: .unitTests)
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   targets: [app, test])

        let testTargetNode = TargetNode(project: project,
                                        target: test,
                                        dependencies: [TargetNode(project: project, target: app, dependencies: [])])
        let appNode = TargetNode(project: project, target: app, dependencies: [])

        let graph = Graph.test(entryPath: temporaryPath,
                               entryNodes: [testTargetNode, appNode],
                               targets: [project.path: [testTargetNode, appNode]])

        // When
        let generatedProject = try subject.generate(project: project, graph: graph)

        // Then
        let pbxproj = generatedProject.xcodeProj.pbxproj
        let pbxproject = try pbxproj.rootProject()
        let nativeTargets = pbxproj.nativeTargets
        let attributes = pbxproject?.targetAttributes ?? [:]
        let appTarget = nativeTargets.first(where: { $0.name == "App" })
        XCTAssertTrue(attributes.contains { attribute in

            guard let testTargetID = attribute.value["TestTargetID"] as? PBXNativeTarget else {
                return false
            }

            return attribute.key.name == "Tests" && testTargetID == appTarget

        }, "Test target is missing from target attributes.")
    }

    func test_generate_testUsingFileName() throws {
        // Given
        let project = Project.test(name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.create(project: project,
                                 dependencies: [
                                 ])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        XCTAssertEqual(got.xcodeprojPath.basename, "SomeAwesomeName.xcodeproj")
    }

    func test_objectVersion_when_xcode11_and_spm() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [.test(dependencies: [.package(product: "A")])],
                                   packages: [.remote(url: "A", requirement: .exact("0.1"))])

        let target = Target.test()
        let packageNode = PackageNode(package: .remote(url: "A", requirement: .exact("0.1")),
                                      path: temporaryPath)
        let graph = Graph.test(entryPath: temporaryPath,
                               entryNodes: [TargetNode(project: project,
                                                       target: target,
                                                       dependencies: [packageNode])],
                               projects: [project],
                               packages: [packageNode])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 52)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode11() throws {
        xcodeController.selectedVersionStub = .success(Version(11, 0, 0))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: temporaryPath)

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 50)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_objectVersion_when_xcode10() throws {
        xcodeController.selectedVersionStub = .success(Version(10, 2, 1))

        // Given
        let temporaryPath = try self.temporaryPath()
        let project = Project.test(path: temporaryPath,
                                   name: "Project",
                                   fileName: "SomeAwesomeName",
                                   targets: [])
        let graph = Graph.test(entryPath: temporaryPath)

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxproj = got.xcodeProj.pbxproj
        XCTAssertEqual(pbxproj.objectVersion, 50)
        XCTAssertEqual(pbxproj.archiveVersion, Xcode.LastKnown.archiveVersion)
    }

    func test_knownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(entryPath: path)
        let resources = [
            "resources/en.lproj/App.strings",
            "resources/en.lproj/Extension.strings",
            "resources/fr.lproj/App.strings",
            "resources/fr.lproj/Extension.strings",
            "resources/Base.lproj/App.strings",
            "resources/Base.lproj/Extension.strings",
        ]
        let project = Project.test(path: path,
                                   targets: [
                                       .test(resources: resources.map {
                                           .file(path: path.appending(RelativePath($0)))
                                       }),
                                   ])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
            "fr",
        ])
    }

    func test_generate_setsDefaultKnownRegions() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(entryPath: path)
        let project = Project.test(path: path,
                                   targets: [])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        XCTAssertEqual(pbxProject.knownRegions, [
            "Base",
            "en",
        ])
    }

    func test_generate_setsOrganizationName() throws {
        // Given
        let path = try temporaryPath()
        let graph = Graph.test(entryPath: path)
        let project = Project.test(path: path,
                                   organizationName: "tuist",
                                   targets: [])

        // When
        let got = try subject.generate(project: project, graph: graph)

        // Then
        let pbxProject = try XCTUnwrap(try got.xcodeProj.pbxproj.rootProject())
        let attributes = try XCTUnwrap(pbxProject.attributes as? [String: String])
        XCTAssertEqual(attributes, [
            "ORGANIZATIONNAME": "tuist",
        ])
    }
}
