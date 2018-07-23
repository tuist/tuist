import Basic
import Foundation
import XCTest
@testable import TuistKit

final class FileAggregatorTests: XCTestCase {
    var subject: FileAggregator!

    override func setUp() {
        super.setUp()
        subject = FileAggregator()
    }

    func test_aggregate() throws {
        let dir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let aPath = dir.path.appending(component: "a.swift")
        let bPath = dir.path.appending(component: "b.swift")
        try "a".write(toFile: aPath.asString,
                      atomically: true,
                      encoding: .utf8)
        try "b".write(toFile: bPath.asString,
                      atomically: true,
                      encoding: .utf8)
        let cPath = dir.path.appending(component: "c.swift")
        try subject.aggregate([aPath, bPath], into: cPath)
        let content = try String(contentsOf: URL(fileURLWithPath: cPath.asString))
        XCTAssertEqual(content, "a\nb")
    }
}
