import Foundation
import Noora
import ServiceContextModule
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

    func test_fatalError_printsTheDescription_whenPrintableError() async throws {
        try await ServiceContext.withTestingDependencies {
            let error = TestError(type: .abort)
            subject.fatal(error: error)

            let got = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            stderr: ▌ ✖ Error
            stderr: ▌ Error
            stderr: ▌
            stderr: ▌ Sorry this didn’t work. Here’s what to try next:
            stderr: ▌  ▸ If the error is actionable, address it
            stderr: ▌  ▸ If the error is not actionable, let\'s discuss it in the ]8;;https://community.tuist.dev/c/troubleshooting-how-to/6\\Troubleshooting & how to]8;;\\
            stderr: ▌  ▸ If you are very certain it\'s a bug, ]8;;https://github.com/tuist/tuist\\file an issue]8;;\\
            """

            XCTAssertEqual(got, expectedOutput)
        }
    }

    func test_fatalError_prints_whenItsSilent() async throws {
        try await ServiceContext.withTestingDependencies {
            let error = TestError(type: .bugSilent)
            subject.fatal(error: error)

            let got = ServiceContext.current?.recordedUI()
            let expectedOutput = """
            stderr: ▌ ✖ Error
            stderr: ▌ An unexpected error happened. We've opened an issue to fix it as soon as possible.
            stderr: We are sorry for any inconveniences it might have caused.
            """

            XCTAssertEqual(got, expectedOutput)
        }
    }
}
