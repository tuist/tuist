import Basic
import Foundation
import PathKit
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

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
                          settings: .default,
                          filesGroup: .group(name: "Project"),
                          targets: [
                              .test(filesGroup: .group(name: "Target")),
                              .test(),
                          ],
                          schemes: [])
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
        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)

        let main = subject.main
        XCTAssertNil(main.path)
        XCTAssertEqual(main.sourceTree, .group)
        XCTAssertEqual(main.children.count, 5)

        XCTAssertNotNil(main.group(named: "Project"))
        XCTAssertNil(main.group(named: "Project")?.path)
        XCTAssertEqual(main.group(named: "Project")?.sourceTree, .group)

        XCTAssertNotNil(main.group(named: "Target"))
        XCTAssertNil(main.group(named: "Target")?.path)
        XCTAssertEqual(main.group(named: "Target")?.sourceTree, .group)

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

    func test_generate_groupsOrder() throws {
        // Given
        playgrounds.pathsStub = { _ in
            [AbsolutePath("/Playgrounds/Test.playground")]
        }
        let target1 = Target.test(filesGroup: .group(name: "B"))
        let target2 = Target.test(filesGroup: .group(name: "C"))
        let target3 = Target.test(filesGroup: .group(name: "A"))
        let target4 = Target.test(filesGroup: .group(name: "C"))
        let project = Project.test(filesGroup: .group(name: "P"),
                                   targets: [target1, target2, target3, target4])

        // When
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        // Then
        let paths = subject.main.children.compactMap { $0.nameOrPath }
        XCTAssertEqual(paths, [
            "P",
            "B",
            "C",
            "A",
            "Frameworks",
            "Playgrounds",
            "Products",
        ])
    }

    func test_targetFrameworks() throws {
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.children.contains(got))
    }

    func test_projectGroup_unknownProjectGroups() throws {
        // Given
        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        // When / Then
        XCTAssertThrowsSpecific(try subject.projectGroup(named: "abc"),
                                ProjectGroupsError.missingGroup("abc"))
    }

    func test_projectGroup_knownProjectGroups() throws {
        // Given
        let target1 = Target.test(filesGroup: .group(name: "A"))
        let target2 = Target.test(filesGroup: .group(name: "B"))
        let target3 = Target.test(filesGroup: .group(name: "B"))
        let project = Project.test(filesGroup: .group(name: "P"),
                                   targets: [target1, target2, target3])

        subject = ProjectGroups.generate(project: project, pbxproj: pbxproj, sourceRootPath: sourceRootPath, playgrounds: playgrounds)

        // When / Then
        XCTAssertNotNil(try? subject.projectGroup(named: "A"))
        XCTAssertNotNil(try? subject.projectGroup(named: "B"))
        XCTAssertNotNil(try? subject.projectGroup(named: "P"))
    }

    func test_projectGroupsError_description() {
        XCTAssertEqual(ProjectGroupsError.missingGroup("abc").description, "Couldn't find group: abc")
    }

    func test_projectGroupsError_type() {
        XCTAssertEqual(ProjectGroupsError.missingGroup("abc").type, .bug)
    }
}
