import XcodeProj
import XCTest
@testable import TuistGenerator

class PBXGroupSorterTests: XCTestCase {
    var subject: PBXGroupSorter!

    override func setUp() {
        subject = PBXGroupSorter()
    }

    func test_projectGroupsSort_simpleGroupsCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("somefile1.swift"),
            group("somegroup2", [
                file("somefile2.swift"),
                file("somefile1.swift"),
            ]),
            group("somegroup1", [
                file("somefile4.swift"),
                file("somefile3.swift"),
            ]),
        ])

        // When
        subject.sort(with: mainGroup)

        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("somegroup1", [
                file("somefile3.swift"),
                file("somefile4.swift"),
            ]),
            group("somegroup2", [
                file("somefile1.swift"),
                file("somefile2.swift"),
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
                ]),
            ]),
            group("somegroup1", [
                file("somefile4.swift"),
                group("somegroup3", [
                    file("somefile6.swift"),
                ]),
                file("somefile3.swift"),
            ]),
        ])

        // When
        subject.sort(with: mainGroup)

        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("somegroup1", [
                group("somegroup3", [
                    file("somefile6.swift"),
                ]),
                file("somefile3.swift"),
                file("somefile4.swift"),
            ]),
            group("somegroup2", [
                group("somegroup4", [
                    file("somefile7.swift"),
                ]),
                file("somefile1.swift"),
                file("somefile2.swift"),
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
            file("file2"),
        ])

        // When
        subject.sort(with: mainGroup)

        // Then
        assertGroupsEqual(mainGroup, group("project", [
            file("file1"), // folder references
            file("file2"),
            file("file3"),
            file("file4.swift"),
        ]))
    }

    func test_projectGroupsSort_simpleEmptyFoldersAndGroupsCase() throws {
        // Given
        let mainGroup = PBXGroup(children: [
            file("file3"),
            file("file1"),
            file("file4.swift"),
            group("zzzgroup", [
                file("zz.swift"),
            ]),
            file("file2"),
        ])

        // When
        subject.sort(with: mainGroup)

        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("zzzgroup", [ // groups before files
                file("zz.swift"),
            ]),
            file("file1"), // folder references
            file("file2"),
            file("file3"),
            file("file4.swift"),
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
                    file("aa.swift"),
                ]),
                file("file2"),
            ]),
        ])

        // When
        subject.sort(with: mainGroup)

        // Then
        assertGroupsEqual(mainGroup, group("project", [
            group("rootfolder", [
                group("zzzgroup", [ // groups before files
                    file("aa.swift"),
                    file("zz.swift"),
                ]),
                file("file1"), // folder references
                file("file2"),
                file("file3"),
                file("file4.swift"),
            ]),
            file("somerootfile.md"),
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
