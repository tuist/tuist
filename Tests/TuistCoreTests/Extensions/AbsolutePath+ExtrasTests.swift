import Basic
import Foundation
import XCTest

@testable import TuistCore

final class AbsolutePathExtrasTests: XCTestCase {
    func test_xcodeSortener() {
        // Given
        let paths = [
            "/sources/a.swift",
            "/c",
            "/sources/module1/z.swift",
            "/sources/module2/a.swift",
            "/sources/module1/a.swift",
            "/sources/module2/sub/g.swift",
            "/sub",
            "/sources/module2/sub/a.swift",
            "/Project.swift",
            "/a",
        ]

        var subject = paths.map { AbsolutePath($0) }

        // When
        subject.sort(by: AbsolutePath.xcodeSortener())

        // Then
        XCTAssertEqual(subject.map { $0.asString }, [
            "/Project.swift",
            "/a",
            "/c",
            "/sub",
            "/sources/a.swift",
            "/sources/module1/a.swift",
            "/sources/module1/z.swift",
            "/sources/module2/a.swift",
            "/sources/module2/sub/a.swift",
            "/sources/module2/sub/g.swift",
        ])
    }
}
