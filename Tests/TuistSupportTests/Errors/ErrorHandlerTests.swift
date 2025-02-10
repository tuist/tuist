import Foundation
import ServiceContextModule
import XCTest
import Noora
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

    func test_fatalError_printsTheDescription_whenPrintableError() async throws {
        try await ServiceContext.withTestingDependencies {
            let error = TestError(type: .abort)
            subject.fatal(error: error)
            
            let got = ServiceContext.current?.recordedUI()
            
            let expected = """
            stderr: ▌ ✖ Error 
            stderr: ▌ Error 
            stderr: ▌
            stderr: ▌ Sorry this didn’t work. Here’s what to try next: 
            stderr: ▌  ▸ Consider creating an issue using the following link: https://github.com/tuist/tuist/issues/new/choose
            """
            XCTAssertEqual(got, expected)
        }
    }

    func test_fatalError_prints_whenItsSilent() async throws {
        try await ServiceContext.withTestingDependencies {
            let error = TestError(type: .bugSilent)
            subject.fatal(error: error)
            let expected = """
            An unexpected error happened. We've opened an issue to fix it as soon as possible.
            We are sorry for any inconveniences it might have caused.
            """
            XCTAssertPrinterErrorContains(expected)
        }
    }
}
