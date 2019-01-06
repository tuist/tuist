import Basic
import Foundation
import TuistCoreTesting
import XCTest

@testable import TuistKit

final class XcodeBuildOutputParserTests: XCTestCase {
    var subject: XcodeBuildOutputParser!

    override func setUp() {
        super.setUp()
        subject = XcodeBuildOutputParser()
    }

    func test_parse_when_analyze() throws {
        let line = try sample(name: "analyze")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, XcodeBuildOutputEvent.analyze(filePath: "CocoaChip/CCChip8DisplayView.m",
                                                            name: "CCChip8DisplayView.m"))
    }

    fileprivate func sample(name: String) throws -> String {
        let path = fixture(path: RelativePath("xcodebuild/samples/\(name)"))
        return try String(contentsOf: path.url)
    }
}
