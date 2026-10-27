import Testing

@testable import TuistRunnerCommand

struct RunnerShellTerminalClientTests {
    @Test func exitStatusReturnsZeroForSuccessfulExitFrames() {
        #expect(RunnerShellTerminalClient.exitStatus(for: #"{"type":"exit","status":0}"#) == 0)
    }

    @Test func exitStatusReturnsNonzeroExitFrames() {
        #expect(RunnerShellTerminalClient.exitStatus(for: #"{"type":"exit","status":42}"#) == 42)
    }

    @Test func exitStatusIgnoresMalformedExitFrames() {
        #expect(RunnerShellTerminalClient.exitStatus(for: #"{"type":"exit","status":"42"}"#) == nil)
        #expect(RunnerShellTerminalClient.exitStatus(for: #"{"type":"exit"}"#) == nil)
    }

    @Test func exitStatusIgnoresUnrelatedMessages() {
        #expect(RunnerShellTerminalClient.exitStatus(for: #"{"type":"status","status":"connected"}"#) == nil)
    }
}
