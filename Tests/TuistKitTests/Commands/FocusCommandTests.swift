import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistLoader
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class FocusCommandTests: TuistUnitTestCase {
    var subject: FocusCommand!
    var parser: ArgumentParser!
    var opener: MockOpener!
    var generator: MockGenerator!
    var manifestLoader: MockManifestLoader!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        opener = MockOpener()
        generator = MockGenerator()
        manifestLoader = MockManifestLoader()

        subject = FocusCommand(parser: parser,
                               generator: generator,
                               manifestLoader: manifestLoader,
                               opener: opener)
    }

    override func tearDown() {
        parser = nil
        opener = nil
        generator = nil
        manifestLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_command() {
        XCTAssertEqual(FocusCommand.command, "focus")
    }

    func test_overview() {
        XCTAssertEqual(FocusCommand.overview, "Opens Xcode ready to focus on the project in the current directory.")
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let result = try parser.parse([FocusCommand.command])
        let error = NSError.test()
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { _, _ in
            throw error
        }
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let result = try parser.parse([FocusCommand.command])
        let graph = Graph.test()
        let workspacePath = AbsolutePath("/test.xcworkspace")
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { _, _ in
            (workspacePath, graph)
        }
        try subject.run(with: result)

        XCTAssertEqual(opener.openArgs.last?.0, workspacePath)
    }
}
