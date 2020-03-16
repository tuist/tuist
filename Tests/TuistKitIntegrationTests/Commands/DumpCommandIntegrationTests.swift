import Basic
import Foundation
import SPMUtility
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistLoader
@testable import TuistSupportTesting

final class DumpCommandTests: TuistTestCase {
    var errorHandler: MockErrorHandler!
    var subject: DumpCommand!
    var parser: ArgumentParser!
    var manifestLoading: ManifestLoading!

    override func setUp() {
        super.setUp()
        errorHandler = MockErrorHandler()
        parser = ArgumentParser.test()
        manifestLoading = ManifestLoader()
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

    func test_prints_the_manifest_when_swift_manifest() throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)
        let config = """
        import ProjectDescription

        let project = Project(name: "tuist",
              organizationName: "tuist",
              settings: nil,
              targets: [])
        """
        try config.write(toFile: tmpDir.path.appending(component: "Project.swift").pathString,
                         atomically: true,
                         encoding: .utf8)
        let result = try parser.parse([DumpCommand.command, "-p", tmpDir.path.pathString])
        try subject.run(with: result)
        let expected = "{\n  \"additionalFiles\": [\n\n  ],\n  \"name\": \"tuist\",\n  \"organizationName\": \"tuist\",\n  \"packages\": [\n\n  ],\n  \"schemes\": [\n\n  ],\n  \"targets\": [\n\n  ]\n}\n"

        XCTAssertPrinterOutputContains(expected)
    }
}
