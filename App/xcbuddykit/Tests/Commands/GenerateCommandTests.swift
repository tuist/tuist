import Basic
import Foundation
import Utility
@testable import xcbuddykit
@testable import xcodeproj
import XCTest

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
        let graphLoaderContext = GraphLoaderContext(errorHandler: errorHandler)
        let commandsContext = CommandsContext(printer: printer, errorHandler: errorHandler)
        graphLoader = MockGraphLoader()
        workspaceGenerator = MockWorkspaceGenerator()
        parser = ArgumentParser.test()
        subject = GenerateCommand(graphLoaderContext: graphLoaderContext,
                                  graphLoader: graphLoader,
                                  workspaceGenerator: workspaceGenerator,
                                  parser: parser,
                                  context: commandsContext)
    }

    func test_command() {
        XCTAssertEqual(GenerateCommand.command, "generate")
    }

    func test_overview() {
        XCTAssertEqual(GenerateCommand.overview, "Generates an Xcode workspace to start working on the project.")
    }

    func test_run_fatalErrors_when_theConfigIsInvalid() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "invalid_config"])
        subject.run(with: result)
        XCTAssertNotNil(errorHandler.fatalErrorArgs.first)
    }

    func test_run_fatalErrors_when_theworkspaceGenerationFails() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "Debug"])
        var configuration: BuildConfiguration?
        let error = NSError.test()
        workspaceGenerator.generateStub = { _, _, options in
            configuration = options.buildConfiguration
            throw error
        }
        subject.run(with: result)
        XCTAssertEqual(configuration, .debug)
        XCTAssertEqual(errorHandler.tryErrors.first as NSError?, error)
    }

    func test_run_prints() throws {
        let result = try parser.parse([GenerateCommand.command, "-c", "Debug"])
        subject.run(with: result)
        XCTAssertEqual(printer.printSectionArgs.first, "Generate command succeeded 🎉")
    }
}
