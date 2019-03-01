import Basic
import Foundation
import XCTest

@testable import TuistCore

final class AbsolutePathExtrasTests: XCTestCase {
    var fileHandler: FileHandling!

    override func setUp() {
        super.setUp()
        fileHandler = FileHandler()
    }

    func test_xcodeSortener() {
        let subject = [
            AbsolutePath("/sources/a.swift"),
            AbsolutePath("/a.swift"),
            AbsolutePath("/b.swift"),
            AbsolutePath("/sources/b.swift"),
        ].sorted(by: AbsolutePath.xcodeSortener(fileHandler: fileHandler))

        XCTAssertEqual(subject, [
            AbsolutePath("/a.swift"),
            AbsolutePath("/b.swift"),
            AbsolutePath("/sources/a.swift"),
            AbsolutePath("/sources/b.swift"),
        ])
    }
}
