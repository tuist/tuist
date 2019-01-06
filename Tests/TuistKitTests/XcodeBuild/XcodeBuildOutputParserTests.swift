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
        XCTAssertEqual(event, .analyze(filePath: "CocoaChip/CCChip8DisplayView.m",
                                       name: "CCChip8DisplayView.m"))
    }

    func test_parse_when_buildTarget() throws {
        let line = try sample(name: "build_target")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .buildTarget(target: "Pods",
                                           project: "The Spacer",
                                           configuration: "Debug"))
    }

    fileprivate func sample(name: String) throws -> String {
        let path = fixture(path: RelativePath("xcodebuild/samples/\(name)"))
        return try String(contentsOf: path.url)
    }
}
