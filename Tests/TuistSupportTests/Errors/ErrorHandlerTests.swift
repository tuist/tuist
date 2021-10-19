import Foundation
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

private struct TestError: FatalError {
    var description: String { "Error" }
    var type: ErrorType
}

final class ErrorHandlerTests: TuistUnitTestCase {
    var subject: ErrorHandler!

    override func setUp() {
        super.setUp()

        subject = ErrorHandler()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_fatalError_printsTheDescription_whenPrintableError() {
        let error = TestError(type: .abort)
        subject.fatal(error: error)
        XCTAssertPrinterErrorContains(error.description)
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
