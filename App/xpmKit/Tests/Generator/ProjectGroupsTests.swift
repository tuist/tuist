import Basic
import Foundation
@testable import xcodeproj
import XCTest
@testable import xpmKit

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
        subject = ProjectGroups.generate(project: project, objects: pbxproj.objects, sourceRootPath: sourceRootPath)
    }

    func test_generate() {
        let main = subject.main
        XCTAssertEqual(main.path, ".")
        XCTAssertEqual(main.sourceTree, .group)

        XCTAssertTrue(main.childrenReferences.contains(subject.project.reference))
        XCTAssertEqual(subject.project.name, "Project")
        XCTAssertNil(subject.project.path)
        XCTAssertEqual(subject.project.sourceTree, .group)

        XCTAssertTrue(main.childrenReferences.contains(subject.projectDescription.reference))
        XCTAssertEqual(subject.projectDescription.name, "ProjectDescription")
        XCTAssertNil(subject.projectDescription.path)
        XCTAssertEqual(subject.projectDescription.sourceTree, .group)

        XCTAssertTrue(main.childrenReferences.contains(subject.frameworks.reference))
        XCTAssertEqual(subject.frameworks.name, "Frameworks")
        XCTAssertNil(subject.frameworks.path)
        XCTAssertEqual(subject.frameworks.sourceTree, .group)

        XCTAssertTrue(main.childrenReferences.contains(subject.products.reference))
        XCTAssertEqual(subject.products.name, "Products")
        XCTAssertNil(subject.products.path)
        XCTAssertEqual(subject.products.sourceTree, .group)
    }

    func test_targetFrameworks() throws {
        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.childrenReferences.contains(got.reference))
    }
}
