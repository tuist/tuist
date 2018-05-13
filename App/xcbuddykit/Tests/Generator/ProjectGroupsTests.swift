import Basic
import Foundation
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

final class ProjectGroupsTests: XCTestCase {
    var subject: ProjectGroups!

    override func setUp() {
        super.setUp()
        let path = AbsolutePath("/test/")
        let sourceRootPath = AbsolutePath("/test/")
        let project = Project(path: path,
                              name: "Project",
                              schemes: [],
                              settings: nil,
                              targets: [])
        let pbxproj = PBXProj()
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath)
    }

    func test_generate() {
        let main = subject.main
        XCTAssertEqual(main.path, ".")
        XCTAssertEqual(main.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.targets.reference))
        XCTAssertEqual(subject.targets.name, "Targets")
        XCTAssertNil(subject.targets.path)
        XCTAssertEqual(subject.targets.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.configurations.reference))
        XCTAssertEqual(subject.configurations.name, "Configurations")
        XCTAssertNil(subject.configurations.path)
        XCTAssertEqual(subject.configurations.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.support.reference))
        XCTAssertEqual(subject.support.name, "Support")
        XCTAssertNil(subject.support.path)
        XCTAssertEqual(subject.support.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.projectDescription.reference))
        XCTAssertEqual(subject.projectDescription.name, "ProjectDescription")
        XCTAssertNil(subject.projectDescription.path)
        XCTAssertEqual(subject.projectDescription.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.frameworks.reference))
        XCTAssertEqual(subject.frameworks.name, "Frameworks")
        XCTAssertNil(subject.frameworks.path)
        XCTAssertEqual(subject.frameworks.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.products.reference))
        XCTAssertEqual(subject.products.name, "Products")
        XCTAssertNil(subject.products.path)
        XCTAssertEqual(subject.products.sourceTree, .buildProductsDir)
    }

    func test_targetName() throws {
        let got = try subject.target(name: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.targets.children.contains(got.reference))
    }

    func test_targetFrameworks() throws {
        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.children.contains(got.reference))
    }

    func test_targetConfigurations() throws {
        let got = try subject.targetConfigurations("Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.configurations.children.contains(got.reference))
    }

    func test_projectConfigurations() throws {
        let got = try subject.projectConfigurations()
        XCTAssertEqual(got.name, "Project")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.configurations.children.contains(got.reference))
    }
}
