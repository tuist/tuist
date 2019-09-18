import Basic
import Foundation
import SPMUtility
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class UpCommandTests: XCTestCase {
    var subject: UpCommand!
    var fileHandler: MockFileHandler!
    var parser: ArgumentParser!
    var setupLoader: MockSetupLoader!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        parser = ArgumentParser.test()
        setupLoader = MockSetupLoader()

        subject = UpCommand(parser: parser,
                            setupLoader: setupLoader)
    }

    func test_command() {
        XCTAssertEqual(UpCommand.command, "up")
    }

    func test_overview() {
        XCTAssertEqual(UpCommand.overview, "Configures the environment for the project.")
    }

    func test_run_configures_the_environment() throws {
        // given
        let currentPath = fileHandler.currentPath.pathString
        let result = try parser.parse([UpCommand.command])
        var receivedPaths = [String]()
        setupLoader.meetStub = { path in
            receivedPaths.append(path.pathString)
        }

        // when
        try subject.run(with: result)

        // then
        XCTAssertEqual(receivedPaths, [currentPath])
        XCTAssertEqual(setupLoader.meetCount, 1)
    }

    func test_run_uses_the_given_path() throws {
        // given
        let path = AbsolutePath("/path")
        let result = try parser.parse([UpCommand.command, "-p", path.pathString])
        var receivedPaths = [String]()
        setupLoader.meetStub = { path in
            receivedPaths.append(path.pathString)
        }

        // when
        try subject.run(with: result)

        // then
        XCTAssertEqual(receivedPaths, ["/path"])
        XCTAssertEqual(setupLoader.meetCount, 1)
    }
}
