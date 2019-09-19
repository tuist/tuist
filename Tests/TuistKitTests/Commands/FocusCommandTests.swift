import Basic
import Foundation
import SPMUtility
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class FocusCommandTests: XCTestCase {
    var subject: FocusCommand!

    var parser: ArgumentParser!
    var fileHandler: MockFileHandler!
    var opener: MockOpener!
    var generator: MockGenerator!
    var manifestLoader: MockGraphManifestLoader!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        parser = ArgumentParser.test()
        opener = MockOpener()
        generator = MockGenerator()
        manifestLoader = MockGraphManifestLoader()

        subject = FocusCommand(parser: parser,
                               generator: generator,
                               manifestLoader: manifestLoader,
                               opener: opener)
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
        let workspacePath = AbsolutePath("/test.xcworkspace")
        manifestLoader.manifestsAtStub = { _ in
            Set([.project])
        }
        generator.generateProjectWorkspaceStub = { _, _ in
            workspacePath
        }
        try subject.run(with: result)

        XCTAssertEqual(opener.openArgs.last, workspacePath)
    }
}
