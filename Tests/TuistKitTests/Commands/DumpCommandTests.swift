import Basic
import Foundation
import SPMUtility
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class DumpCommandTests: XCTestCase {
    var printer: MockPrinter!
    var errorHandler: MockErrorHandler!
    var fileHandler: MockFileHandler!
    var subject: DumpCommand!
    var parser: ArgumentParser!
    var manifestLoading: GraphManifestLoading!

    override func setUp() {
        printer = MockPrinter()
        errorHandler = MockErrorHandler()
        parser = ArgumentParser.test()
        fileHandler = try! MockFileHandler()
        manifestLoading = GraphManifestLoader()
        subject = DumpCommand(fileHandler: fileHandler,
                              manifestLoader: manifestLoading,
                              printer: printer,
                              parser: parser)
    }

    func test_name() {
        XCTAssertEqual(DumpCommand.command, "dump")
    }

    func test_overview() {
        XCTAssertEqual(DumpCommand.overview, "Outputs the project manifest as a JSON")
    }

    func test_run_throws_when_file_doesnt_exist() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as? GraphManifestLoaderError, GraphManifestLoaderError.manifestNotFound(.project, tmpDir.path))
        }
    }

    func test_run_throws_when_the_manifest_loading_fails() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        try "invalid config".write(toFile: tmpDir.path.appending(component: "Project.swift").asString,
                                   atomically: true,
                                   encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        XCTAssertThrowsError(try subject.run(with: result))
    }

    func test_prints_the_manifest_when_swift_manifest() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let config = """
        import ProjectDescription

        let project = Project(name: "tuist",
              settings: nil,
              targets: [])
        """
        try config.write(toFile: tmpDir.path.appending(component: "Project.swift").asString,
                         atomically: true,
                         encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        try subject.run(with: result)
        let expected = "{\n  \"name\": \"tuist\",\n  \"targets\": [\n\n  ]\n}\n"
        XCTAssertEqual(printer.printArgs.first, expected)
    }
}
