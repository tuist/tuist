import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import xcodeproj
import XCTest

final class FocusCommandTests: XCTestCase {
    var subject: FocusCommand!
    var errorHandler: MockErrorHandler!
    var graphLoader: MockGraphLoader!
    var workspaceGenerator: MockWorkspaceGenerator!
    var parser: ArgumentParser!
    var printer: MockPrinter!
    var fileHandler: MockFileHandler!
    var opener: MockOpener!
    var system: MockSystem!
    var resourceLocator: MockResourceLocator!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        errorHandler = MockErrorHandler()
        graphLoader = MockGraphLoader()
        workspaceGenerator = MockWorkspaceGenerator()
        parser = ArgumentParser.test()
        fileHandler = try! MockFileHandler()
        opener = MockOpener()
        system = MockSystem()
        resourceLocator = MockResourceLocator()

        subject = FocusCommand(parser: parser,
                               graphLoader: graphLoader,
                               workspaceGenerator: workspaceGenerator,
                               printer: printer,
                               system: system,
                               resourceLocator: resourceLocator,
                               fileHandler: fileHandler,
                               opener: opener)
    }

    func test_command() {
        XCTAssertEqual(FocusCommand.command, "focus")
    }

    func test_overview() {
        XCTAssertEqual(FocusCommand.overview, "Opens Xcode ready to focus on the project in the current directory.")
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let result = try parser.parse([FocusCommand.command, "-c", "Debug"])
        let error = NSError.test()
        workspaceGenerator.generateStub = { _, _, _, _ in
            throw error
        }
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run() throws {
        let result = try parser.parse([FocusCommand.command, "-c", "Debug"])
        let workspacePath = AbsolutePath("/test.xcworkspace")
        workspaceGenerator.generateStub = { _, _, _, _ in
            workspacePath
        }
        try subject.run(with: result)

        XCTAssertEqual(opener.openArgs.last, workspacePath)
    }
}
