import Testing
@testable import XcodeGraphMapper

struct SubprocessRunnerTests {
    @Test func includesStandardErrorInTerminationError() async throws {
        do {
            _ = try await SubprocessRunner.capture(arguments: ["/bin/sh", "-c", "printf failure >&2; exit 3"])
            Issue.record("Expected the command to fail.")
        } catch let error as SubprocessRunnerError {
            #expect(
                error.description ==
                    "The command '/bin/sh -c printf failure >&2; exit 3' terminated with the code 3:\nfailure"
            )
        }
    }
}
