import xcodeproj
import XCTest
@testable import TuistKit

class XcodeprojExtrasTests: XCTestCase {
    func test_pbxFileElement_sort() {
        // Given
        let elements = [
            PBXFileReference(name: "d"),
            PBXGroup(name: "E"),
            PBXFileReference(name: "r"),
            PBXGroup(name: "Z"),
            PBXFileReference(name: "c"),
            PBXGroup(name: "A"),
        ]

        // When
        let sorted = elements.sorted(by: PBXFileElement.filesBeforeGroupsSort)

        // Then
        XCTAssertEqual(sorted.map { $0.nameOrPath }, [
            // Files
            "c",
            "d",
            "r",

            // Groups
            "A",
            "E",
            "Z",
        ])
    }
}
