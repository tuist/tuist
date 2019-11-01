import Basic
import Foundation
import SPMUtility
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class UpCommandTests: TuistUnitTestCase {
    var subject: UpCommand!
    var parser: ArgumentParser!
    var setupLoader: MockSetupLoader!

    override func setUp() {
        super.setUp()
        parser = ArgumentParser.test()
        setupLoader = MockSetupLoader()
        subject = UpCommand(parser: parser,
                            setupLoader: setupLoader)
    }

    override func tearDown() {
        subject = nil
        parser = nil
        setupLoader = nil
        super.tearDown()
    }

    func test_command() {
        XCTAssertEqual(UpCommand.command, "up")
    }

    func test_overview() {
        XCTAssertEqual(UpCommand.overview, "Configures the environment for the project.")
    }

    func test_run_configures_the_environment() throws {
        // given
        let temporaryPath = try self.temporaryPath()
        let result = try parser.parse([UpCommand.command])
        var receivedPaths = [String]()
        setupLoader.meetStub = { path in
            receivedPaths.append(path.pathString)
        }

        // when
        try subject.run(with: result)

        // then
        XCTAssertEqual(receivedPaths, [temporaryPath.pathString])
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
