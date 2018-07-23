import Basic
import Foundation
import Utility
@testable import xcodeproj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class GenerateCommandTests: XCTestCase {
    var subject: GenerateCommand!
    var errorHandler: MockErrorHandler!
    var graphLoader: MockGraphLoader!
    var workspaceGenerator: MockWorkspaceGenerator!
    var parser: ArgumentParser!
    var printer: MockPrinter!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        errorHandler = MockErrorHandler()
        graphLoader = MockGraphLoader()
        workspaceGenerator = MockWorkspaceGenerator()
        parser = ArgumentParser.test()
        subject = GenerateCommand(graphLoader: graphLoader,
                                  workspaceGenerator: workspaceGenerator,
                                  parser: parser,
                                  printer: printer)
    }

    func test_command() {
        XCTAssertEqual(GenerateCommand.command, "generate")
    }

    func test_overview() {
        XCTAssertEqual(GenerateCommand.overview, "Generates an Xcode workspace to start working on the project.")
    }

    func test_run_fatalErrors_when_theConfigIsInvalid() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "invalid_config"])
        XCTAssertThrowsError(try subject.run(with: result))
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "Debug"])
        var configuration: BuildConfiguration?
        let error = NSError.test()
        workspaceGenerator.generateStub = { _, _, options in
            configuration = options.buildConfiguration
            throw error
        }
        XCTAssertThrowsError(try subject.run(with: result)) {
            XCTAssertEqual($0 as NSError?, error)
        }
        XCTAssertEqual(configuration, .debug)
    }

    func test_run_prints() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "Debug"])
        try subject.run(with: result)
        XCTAssertEqual(printer.printSuccessArgs.first, "Project generated.")
    }
}
