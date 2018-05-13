import Foundation
@testable import xcbuddykit
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
        let context = Context(errorHandler: errorHandler)
        subject = CommandRegistry(context: context,
                                  commandCheck: commandCheck) { return ["xcbuddy", type(of: self.command).command] }
        command = MockCommand(parser: subject.parser)
        subject.register(command: MockCommand.self)
    }

    func test_run_reportsFatalErrors() throws {
        var thrownError: Error?
        errorHandler.tryStub = { block in
            do {
                try block()
            } catch {
                thrownError = error
            }
        }
        commandCheck.checkStub = { _ in throw NSError.test() }
        try subject.run()
        XCTAssertNotNil(thrownError)
    }
}
