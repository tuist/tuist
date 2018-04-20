import Foundation
@testable import xcbuddykit
import XCTest

final class DumpCommandTests: XCTestCase {
    var printer: MockPrinter!
    var grahLoaderContext: MockGraphLoaderContext!
    var commandsContext: MockCommandsContext!
    var subject: DumpCommand!

    override func setUp() {
        grahLoaderContext = MockGraphLoaderContext()
        printer = MockPrinter()
        commandsContext = MockCommandsContext()
        subject = DumpCommand(graphLoaderContext: grahLoaderContext, commandsContext: commandsContext)
    }

    func test_name() {
        XCTAssertEqual(subject.command, "dump")
    }

    func test_overview() {
        XCTAssertEqual(subject.overview, "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON.")
    }

    func test_run_throws_when_file_doesnt_exist() {
        XCTFail()
    }

    func test_run_throws_when_the_manifest_loading_fails() {
        XCTFail()
    }

    func test_prints_the_manifest() {
        XCTFail()
    }
}
