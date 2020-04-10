import Basic
import Foundation
import XCTest
@testable import TuistSupport
@testable import TuistSupportTesting

final class ProcessResultTests: TuistUnitTestCase {
    func test_command_returns_the_right_command_when_xcrun() {
        // Given
        let subject = ProcessResult(arguments: ["/usr/bin/xcrun", "swiftc"],
                                    exitStatus: .terminated(code: 1),
                                    output: .failure(AnyError(TestError("error"))),
                                    stderrOutput: .failure(AnyError(TestError("error"))))

        // When
        let got = subject.command()

        // Then
        XCTAssertEqual(got, "swiftc")
    }
}
