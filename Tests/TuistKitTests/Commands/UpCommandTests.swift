import Basic
import Foundation
import Utility
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpCommandTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var printer: MockPrinter!
    var graphLoader: MockGraphLoader!
    var graphUp: MockGraphUp!
    var subject: UpCommand!
    var parser: ArgumentParser!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        printer = MockPrinter()
        graphLoader = MockGraphLoader()
        graphUp = MockGraphUp()
        parser = ArgumentParser.test()
        subject = UpCommand(parser: parser,
                            fileHandler: fileHandler,
                            printer: printer,
                            graphLoader: graphLoader,
                            graphUp: graphUp)
    }

    func test_command() {
        XCTAssertEqual(UpCommand.command, "up")
    }

    func test_overview() {
        XCTAssertEqual(UpCommand.overview, "Configures the environment for the project.")
    }

    func test_run_configures_the_environment() throws {
        let result = try parser.parse([UpCommand.command])

        graphLoader.loadStub = { path in
            XCTAssertEqual(path, self.fileHandler.currentPath)
            return Graph.test()
        }
        var met: Bool = false
        graphUp.meetStub = { _ in
            met = true
        }

        try subject.run(with: result)

        XCTAssertTrue(met)
    }
}
