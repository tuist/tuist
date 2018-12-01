import Basic
import Foundation
import XCTest

@testable import TuistCore

final class AbsolutePathExtrasTests: XCTestCase {
    func test_xcodeSortener() {
        let subject = [
            AbsolutePath("/sources/a.swift"),
            AbsolutePath("/a.swift"),
            AbsolutePath("/b.swift"),
            AbsolutePath("/sources/b.swift"),
        ].sorted(by: AbsolutePath.xcodeSortener())

        XCTAssertEqual(subject, [
            AbsolutePath("/a.swift"),
            AbsolutePath("/b.swift"),
            AbsolutePath("/sources/a.swift"),
            AbsolutePath("/sources/b.swift"),
        ])
    }
}
