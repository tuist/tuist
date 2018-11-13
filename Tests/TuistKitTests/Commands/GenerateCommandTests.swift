import Basic
import Foundation
import TuistCore
@testable import TuistCoreTesting
@testable import TuistKit
import Utility
import xcodeproj
import XCTest

final class GenerateCommandTests: XCTestCase {
    var subject: GenerateCommand!
    var errorHandler: MockErrorHandler!
    var graphLoader: MockGraphLoader!
    var workspaceGenerator: MockWorkspaceGenerator!
    var parser: ArgumentParser!
    var printer: MockPrinter!
    var resourceLocator: ResourceLocator!
    var graphUp: MockGraphUp!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        errorHandler = MockErrorHandler()
        graphLoader = MockGraphLoader()
        workspaceGenerator = MockWorkspaceGenerator()
        parser = ArgumentParser.test()
        resourceLocator = ResourceLocator()
        graphUp = MockGraphUp()

        subject = GenerateCommand(graphLoader: graphLoader,
                                  workspaceGenerator: workspaceGenerator,
                                  parser: parser,
                                  printer: printer,
                                  system: System(),
                                  resourceLocator: resourceLocator,
                                  graphUp: graphUp)
    }

    func test_command() {
        XCTAssertEqual(GenerateCommand.command, "generate")
    }

    func test_overview() {
        XCTAssertEqual(GenerateCommand.overview, "Generates an Xcode workspace to start working on the project.")
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let result = try parser.parse([GenerateCommand.command])
        let error = NSError.test()
        workspaceGenerator.generateStub = { _, _, _, _ in
            throw error
        }
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError?, error)
        }
    }

    func test_run_prints() throws {
        let result = try parser.parse([GenerateCommand.command])
        try subject.run(with: result)
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated.")
    }
}
