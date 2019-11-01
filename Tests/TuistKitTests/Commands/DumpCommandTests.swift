import Basic
import Foundation
import SPMUtility
import TuistSupport
import XCTest

@testable import TuistSupportTesting
@testable import TuistKit

final class DumpCommandTests: TuistUnitTestCase {
    var errorHandler: MockErrorHandler!
    var subject: DumpCommand!
    var parser: ArgumentParser!
    var manifestLoading: GraphManifestLoading!

    override func setUp() {
        super.setUp()
        errorHandler = MockErrorHandler()
        parser = ArgumentParser.test()
        manifestLoading = GraphManifestLoader()
        subject = DumpCommand(manifestLoader: manifestLoading,
                              parser: parser)
    }

    override func tearDown() {
        errorHandler = nil
        parser = nil
        manifestLoading = nil
        subject = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(DumpCommand.command, "dump")
    }

    func test_overview() {
        XCTAssertEqual(DumpCommand.overview, "Outputs the project manifest as a JSON")
    }

    func test_run_throws_when_file_doesnt_exist() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.pathString])
        XCTAssertThrowsSpecific(try subject.run(with: result),
                                GraphManifestLoaderError.manifestNotFound(.project, tmpDir.path))
    }

    func test_run_throws_when_the_manifest_loading_fails() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        try "invalid config".write(toFile: tmpDir.path.appending(component: "Project.swift").pathString,
                                   atomically: true,
                                   encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.pathString])
        XCTAssertThrowsError(try subject.run(with: result))
    }
}
