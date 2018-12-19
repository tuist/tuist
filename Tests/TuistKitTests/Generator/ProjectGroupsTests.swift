import Basic
import Foundation
@testable import TuistKit
import xcodeproj
import XCTest

final class ProjectGroupsTests: XCTestCase {
    var subject: ProjectGroups!
    var playgrounds: MockPlaygrounds!
    var sourceRootPath: AbsolutePath!
    var project: Project!
    var pbxproj: PBXProj!

    override func setUp() {
        super.setUp()
        let path = AbsolutePath("/test/")
        playgrounds = MockPlaygrounds()
        sourceRootPath = AbsolutePath("/test/")
        project = Project(path: path,
                          name: "Project",
                          settings: nil,
                          targets: [])
        pbxproj = PBXProj()
    }

    func test_generate() {
        playgrounds.pathsStub = { projectPath in
            if projectPath == self.sourceRootPath {
                return [self.sourceRootPath.appending(RelativePath("Playgrounds/Test.playground"))]
            } else {
                return []
            }
        }
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        let main = subject.main
        XCTAssertNil(main.path)
        XCTAssertEqual(main.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.project))
        XCTAssertEqual(subject.project.name, "Project")
        XCTAssertNil(subject.project.path)
        XCTAssertEqual(subject.project.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.projectDescription))
        XCTAssertEqual(subject.projectDescription.name, "ProjectDescription")
        XCTAssertNil(subject.projectDescription.path)
        XCTAssertEqual(subject.projectDescription.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.frameworks))
        XCTAssertEqual(subject.frameworks.name, "Frameworks")
        XCTAssertNil(subject.frameworks.path)
        XCTAssertEqual(subject.frameworks.sourceTree, .group)

        XCTAssertTrue(main.children.contains(subject.products))
        XCTAssertEqual(subject.products.name, "Products")
        XCTAssertNil(subject.products.path)
        XCTAssertEqual(subject.products.sourceTree, .group)

        XCTAssertNotNil(subject.playgrounds)
        XCTAssertTrue(main.children.contains(subject.playgrounds!))
        XCTAssertEqual(subject.playgrounds?.path, "Playgrounds")
        XCTAssertNil(subject.playgrounds?.name)
        XCTAssertEqual(subject.playgrounds?.sourceTree, .group)
    }

    func test_generate_when_there_are_no_playgrounds() {
        playgrounds.pathsStub = { _ in
            []
        }
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        XCTAssertNil(subject.playgrounds)
    }

    func test_targetFrameworks() throws {
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)
        
        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.children.contains(got))
    }
}
