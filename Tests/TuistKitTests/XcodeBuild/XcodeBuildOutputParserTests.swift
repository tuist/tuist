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
        XCTAssertEqual(event, .buildTarget(target: "The Spacer",
                                           project: "Pods",
                                           configuration: "Debug"))
    }

    func test_parse_when_aggregateTarget() throws {
        let line = try sample(name: "aggregate_target")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .aggregateTarget(target: "Be Aggro",
                                               project: "AggregateExample",
                                               configuration: "Debug"))
    }

    func test_parse_when_analyzeTarget() throws {
        let line = try sample(name: "analyze_target")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .analyzeTarget(target: "The Spacer",
                                             project: "Pods",
                                             configuration: "Debug"))
    }

    func test_parse_when_checkDependencies() throws {
        let line = try sample(name: "check_dependencies")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .checkDependencies)
    }

    func test_parse_when_shellCommand() throws {
        let line = try sample(name: "shell_command")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .shellCommand(path: "/bin/rm", arguments: "-rf /bin /usr /Users"))
    }

    func test_parse_when_cleanRemove() throws {
        let line = try sample(name: "clean_remove")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .cleanRemove)
    }

    func test_parse_when_cleanTarget() throws {
        let line = try sample(name: "clean_target")
        let event = subject.parse(line: line)
        XCTAssertEqual(event, .cleanTarget(target: "Pods-ObjectiveSugar",
                                           project: "Pods",
                                           configuration: "Debug"))
    }

    // MARK: - Fileprivate

    fileprivate func sample(name: String) throws -> String {
        let path = fixture(path: RelativePath("xcodebuild/outputs/\(name)"))
        return try String(contentsOf: path.url)
    }
}
