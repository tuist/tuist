import Foundation
import TuistCoreTesting
@testable import TuistKit
import XCTest

final class CommandRegistryTests: XCTestCase {
    var subject: CommandRegistry!
    var commandCheck: MockCommandCheck!
    var errorHandler: MockErrorHandler!
    var command: MockCommand!

    override func setUp() {
        super.setUp()
        commandCheck = MockCommandCheck()
        errorHandler = MockErrorHandler()
        subject = CommandRegistry(commandCheck: commandCheck,
                                  errorHandler: errorHandler,
                                  processArguments: { ["tuist", type(of: self.command).command] })
        command = MockCommand(parser: subject.parser)
        subject.register(command: MockCommand.self)
        subject.register(hiddenCommand: MockHiddenCommand.self)
    }

    func test_run_reportsFatalErrors() throws {
        commandCheck.checkStub = { _ in throw NSError.test() }
        subject.run()
        XCTAssertNotNil(errorHandler.fatalErrorArgs.last)
    }
}
