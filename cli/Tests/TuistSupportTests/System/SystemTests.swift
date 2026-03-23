import Foundation
import TSCBasic
import Testing
@testable import TuistSupport
@testable import TuistTesting

struct ProcessResultTests {
    @Test
    func test_command_returns_the_right_command_when_xcrun() {
        // Given
        let subject = ProcessResult(
            arguments: ["/usr/bin/xcrun", "swiftc"],
            environment: [:],
            exitStatus: .terminated(code: 1),
            output: .failure(TestError("error")),
            stderrOutput: .failure(TestError("error"))
        )

        // When
        let got = subject.command()

        // Then
        #expect(got == "swiftc")
    }
}
