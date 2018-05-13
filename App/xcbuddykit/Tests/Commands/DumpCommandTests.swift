import Basic
import Foundation
import Utility
@testable import xcbuddykit
import XCTest

final class DumpCommandTests: XCTestCase {
    var printer: MockPrinter!
    var errorHandler: MockErrorHandler!
    var subject: DumpCommand!
    var parser: ArgumentParser!

    override func setUp() {
        let graphLoaderContext = GraphLoaderContext()
        printer = MockPrinter()
        errorHandler = MockErrorHandler()
        let commandsContext = CommandsContext(printer: printer, errorHandler: errorHandler)
        parser = ArgumentParser.test()
        subject = DumpCommand(graphLoaderContext: graphLoaderContext,
                              context: commandsContext,
                              parser: parser)
    }

    func test_dumpCommandError_returns_the_right_description_when_manifestNotFound() {
        let error = DumpCommandError.manifestNotFound(AbsolutePath("/test"))
        XCTAssertEqual(error.errorDescription, "Couldn't find Project.swift, Workspace.swift, or Config.swift in the directory /test")
    }

    func test_name() {
        XCTAssertEqual(DumpCommand.command, "dump")
    }

    func test_overview() {
        XCTAssertEqual(DumpCommand.overview, "Prints parsed Project.swift, Workspace.swift, or Config.swift as JSON.")
    }

    func test_run_throws_when_file_doesnt_exist() throws {
        let tmpDir = try TemporaryDirectory()
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        subject.run(with: result)
        XCTAssertEqual(errorHandler.tryErrors.first as? DumpCommandError, DumpCommandError.manifestNotFound(tmpDir.path))
    }

    func test_run_throws_when_the_manifest_loading_fails() throws {
        let tmpDir = try TemporaryDirectory()
        try "invalid config".write(toFile: tmpDir.path.appending(component: "Config.swift").asString,
                                   atomically: true,
                                   encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        subject.run(with: result)
        XCTAssertEqual(errorHandler.tryErrors.count, 1)
    }

    func test_prints_the_manifest() throws {
        let tmpDir = try TemporaryDirectory()
        let config = """
        import ProjectDescription
        let config = Config()
        """
        try config.write(toFile: tmpDir.path.appending(component: "Config.swift").asString,
                         atomically: true,
                         encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.asString])
        subject.run(with: result)
        XCTAssertEqual(printer.printArgs.first, "{\n\n}\n")
    }
}
