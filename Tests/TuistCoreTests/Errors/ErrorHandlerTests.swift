import Foundation
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting

private struct TestError: FatalError {
    var description: String { return "Error" }
    var type: ErrorType
}

final class ErrorHandlerTests: XCTestCase {
    var subject: ErrorHandler!
    var exited: Int32?

    override func setUp() {
        super.setUp()
        mockEnvironment()

        subject = ErrorHandler {
            self.exited = $0
        }
    }

    func test_fatalError_printsTheDescription_whenPrintableError() {
        let error = TestError(type: .abort)
        subject.fatal(error: error)
        XCTAssertPrinterErrorContains(error.description)
    }

    func test_fatalError_exitsWith1() {
        let error = TestError(type: .abort)
        subject.fatal(error: error)
        XCTAssertEqual(exited, 1)
    }

    func test_fatalError_prints_whenItsSilent() {
        let error = TestError(type: .bugSilent)
        subject.fatal(error: error)
        let expected = """
        An unexpected error happened. We've opened an issue to fix it as soon as possible.
        We are sorry for any inconveniences it might have caused.
        """
        XCTAssertPrinterErrorContains(expected)
    }
}
