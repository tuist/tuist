import Foundation
import Sentry
@testable import xcbuddykit
import XCTest

fileprivate final class MockSentryClient: SentryClienting {
    var startCrashHandlerCount: UInt = 0
    var startCrashHandlerStub: Error?
    var sendEventStub: ((Event, SentryRequestFinished?) -> Void)?

    func startCrashHandler() throws {
        startCrashHandlerCount += 1
        if let startCrashHandlerStub = startCrashHandlerStub {
            throw startCrashHandlerStub
        }
    }

    func send(event: Event, completion completionHandler: SentryRequestFinished?) {
        sendEventStub?(event, completionHandler)
    }
}

final class ErrorHandlerTests: XCTestCase {
    fileprivate var client: MockSentryClient!
    var printer: MockPrinter!
    var subject: ErrorHandler!
    var exited: Int32?

    override func setUp() {
        super.setUp()
        client = MockSentryClient()
        printer = MockPrinter()
        subject = ErrorHandler(printer: printer,
                               client: client) {
            self.exited = $0
        }
    }

    func test_init_staartsCrashHandler() {
        XCTAssertEqual(client.startCrashHandlerCount, 1)
    }

    func test_fatalError_printsTheDescription_whenPrintableError() {
        let error = NSError(domain: "domain", code: 20, userInfo: nil)
        subject.fatal(error: .abort(error))
        XCTAssertEqual(printer.printErrorMessageArgs.first, error.description)
    }

    func test_fatalError_doesntPrint_whenSilentError() {
        let error = NSError(domain: "domain", code: 20, userInfo: nil)
        subject.fatal(error: .abortSilent(error))
        XCTAssertEqual(printer.printErrorMessageArgs.count, 0)
    }

    func test_fatalError_exitsWith1() {
        let error = NSError(domain: "domain", code: 20, userInfo: nil)
        subject.fatal(error: .abort(error))
        XCTAssertEqual(exited, 1)
    }

    func test_fatalError_reports_whenBug() {
        let error = NSError(domain: "domain", code: 20, userInfo: nil)
        var sentEvent: Event?
        client.sendEventStub = { event, completion in
            sentEvent = event
            completion?(nil)
        }
        subject.fatal(error: .bug(error))
        XCTAssertEqual(sentEvent?.message, error.localizedDescription)
        XCTAssertEqual(sentEvent?.level, .debug)
    }

    func test_fatalError_prints_whenItsSilent() {
        let error = NSError(domain: "domain", code: 20, userInfo: nil)
        subject.fatal(error: .abortSilent(error))
        let expected = """
        An unexpected error happened. We've open an issue to fix it as soon as possible.
        We are sorry for any inconviniences it might have caused.
        """
        XCTAssertEqual(printer.printErrorMessageArgs.first, expected)
    }
}
