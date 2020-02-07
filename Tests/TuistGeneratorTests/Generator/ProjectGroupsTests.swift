import Basic
import Foundation
import PathKit
import TuistCore
import TuistCoreTesting
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

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
                          packages: [],
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
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)
        ProjectGroups.addFirstLevelDefaults(firstLevelGroup: subject)

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
        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)

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
        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)
        ProjectGroups.addFirstLevelDefaults(firstLevelGroup: subject)

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
        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)

        let got = try subject.targetFrameworks(target: "Test")
        XCTAssertEqual(got.name, "Test")
        XCTAssertEqual(got.sourceTree, .group)
        XCTAssertTrue(subject.frameworks.children.contains(got))
    }

    func test_projectGroup_unknownProjectGroups() throws {
        // Given
        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)

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

        subject = ProjectGroups.generate(project: project,
                                         pbxproj: pbxproj,
                                         xcodeprojPath: project.path.appending(component: "\(project.fileName).xcodeproj"),
                                         sourceRootPath: sourceRootPath,
                                         playgrounds: playgrounds)

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
    
    func test_projectGroupsSort_simpleGroupsCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("somefile1.swift"),
            group("somegroup2", [
                file("somefile2.swift"),
                file("somefile1.swift")
            ]),
            group("somegroup1", [
                file("somefile4.swift"),
                file("somefile3.swift")
            ]),
        ])
        
        // When
        ProjectGroups.sortGroups(group: mainGroup)
        
        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("somegroup1", [
                file("somefile3.swift"),
                file("somefile4.swift")
            ]),
            group("somegroup2", [
                file("somefile1.swift"),
                file("somefile2.swift")
            ]),
            file("somefile1.swift"),
        ]))
    }
    
    func test_projectGroupsSort_nestedGroupsCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("somefile1.swift"),
            group("somegroup2", [
                file("somefile2.swift"),
                file("somefile1.swift"),
                group("somegroup4", [
                    file("somefile7.swift"),
                ])
            ]),
            group("somegroup1", [
                file("somefile4.swift"),
                group("somegroup3", [
                    file("somefile6.swift"),
                ]),
                file("somefile3.swift")
            ]),
        ])
        
        // When
        ProjectGroups.sortGroups(group: mainGroup)
        
        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("somegroup1", [
                group("somegroup3", [
                    file("somefile6.swift"),
                ]),
                file("somefile3.swift"),
                file("somefile4.swift")
            ]),
            group("somegroup2", [
                group("somegroup4", [
                    file("somefile7.swift"),
                ]),
                file("somefile1.swift"),
                file("somefile2.swift")
            ]),
            file("somefile1.swift"),
        ]))
    }
    
    func test_projectGroupsSort_simpleEmptyFoldersCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("file3"),
            file("file1"),
            file("file4.swift"),
            file("file2")
        ])
        
        // When
        ProjectGroups.sortGroups(group: mainGroup)
        
        // Then
        assertGroupsEqual(mainGroup, group("project", [
            file("file1"), // folder references
            file("file2"),
            file("file3"),
            file("file4.swift")
        ]))
    }
    
    func test_projectGroupsSort_simpleEmptyFoldersAndGroupsCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("file3"),
            file("file1"),
            file("file4.swift"),
            group("zzzgroup", [
                file("zz.swift")
            ]),
            file("file2")
        ])
        
        // When
        ProjectGroups.sortGroups(group: mainGroup)
        
        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("zzzgroup", [ // groups before files
                file("zz.swift")
            ]),
            file("file1"), // folder references
            file("file2"),
            file("file3"),
            file("file4.swift")
        ]))
    }
    
    func test_projectGroupsSort_simpleEmptyFoldersAndGroupsCaseDeeperNesting() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("somerootfile.md"),
            group("rootfolder", [
                file("file3"),
                file("file1"),
                file("file4.swift"),
                group("zzzgroup", [
                    file("zz.swift"),
                    file("aa.swift")
                ]),
                file("file2")
            ])
        ])
        
        // When
        ProjectGroups.sortGroups(group: mainGroup)
        
        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("rootfolder", [
                group("zzzgroup", [ // groups before files
                    file("aa.swift"),
                    file("zz.swift")
                ]),
                file("file1"), // folder references
                file("file2"),
                file("file3"),
                file("file4.swift")
            ]),
            file("somerootfile.md")
        ]))
    }
    
    // MARK: - Helpers
    func assertGroupsEqual(_ first: PBXGroup, _ second: PBXGroup, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(first.flattenedChildren, second.flattenedChildren, file: file, line: line)
    }
    var references: [PBXFileElement] = []
    
    func file(_ name: String) -> PBXFileReference {
        let file = PBXFileReference(path: name)
        references.append(file)
        return file
    }
    
    func group(_ name: String, _ children: [PBXFileElement]) -> PBXGroup {
        let group = PBXGroup(children: children, name: name)
        references.append(group)
        return group
    }
}
