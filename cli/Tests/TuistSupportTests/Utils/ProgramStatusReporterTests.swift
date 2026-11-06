import Foundation
import Synchronization
import Testing
@testable import TuistSupport

struct ProgramStatusReporterTests {
    private enum TestError: Error {
        case failed
    }

    @Test(arguments: [
        (["tuist", "generate"], true, false, true),
        (["tuist", "generate"], false, false, false),
        (["tuist", "generate"], true, true, false),
        (["tuist", "generate", "--json"], true, false, false),
        (["tuist", "--quiet", "generate"], true, false, false),
        (["tuist", "dump"], true, false, false),
        (["tuist", "--verbose", "dump"], true, false, false),
    ])
    func shouldReport(arguments: [String], isInteractive: Bool, isCI: Bool, expected: Bool) {
        #expect(ProgramStatusReporter.shouldReport(
            arguments: arguments,
            isInteractive: isInteractive,
            isCI: isCI
        ) == expected)
    }

    @Test func shouldReport_whenTerminalIsDumb_returnsFalse() {
        #expect(!ProgramStatusReporter.shouldReport(
            arguments: ["tuist", "generate"],
            isInteractive: true,
            isCI: false,
            terminalType: "dumb"
        ))
    }

    @Test func shouldReport_whenQuietEnvironmentIsEnabled_returnsFalse() {
        #expect(!ProgramStatusReporter.shouldReport(
            arguments: ["tuist", "generate"],
            isInteractive: true,
            isCI: false,
            isQuiet: true
        ))
    }

    @Test func report_usesOSC7501AndStringTerminator() {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        subject.report(.working)
        subject.report(.blocked, kind: .auth, message: "Sign in: café")
        subject.report(.done, kind: .question)

        #expect(output.withLock { $0 } == [
            "\u{1B}]7501;state=working:app=tuist\u{1B}\\",
            "\u{1B}]7501;state=blocked:app=tuist:kind=auth:msg=\(Data("Sign in: café".utf8).base64EncodedString())\u{1B}\\",
            "\u{1B}]7501;state=done:app=tuist\u{1B}\\",
        ])
    }

    @Test func report_whenDisabled_writesNothing() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: false) { report in
            output.withLock { $0.append(report) }
        }

        await subject.withCommandStatus {
            await subject.withBlockedStatus(kind: .question, message: "Continue?") {}
        }

        #expect(output.withLock { $0.isEmpty })
    }

    @Test func withCommandStatus_whenWriterThrows_preservesSuccess() async {
        let subject = ProgramStatusReporter(isEnabled: true) { _ in throw TestError.failed }

        let result = await subject.withCommandStatus { 42 }

        #expect(result == 42)
    }

    @Test func withCommandStatus_whenWriterThrows_preservesCommandError() async {
        let subject = ProgramStatusReporter(isEnabled: true) { _ in throw TestError.failed }

        await #expect(throws: CancellationError.self) {
            try await subject.withCommandStatus { throw CancellationError() }
        }
    }

    @Test func report_sanitizesControlCharacters() throws {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        subject.report(.blocked, kind: .question, message: "First\nsecond\t\u{1B}\u{7F}\u{85}last")

        let report = try #require(output.withLock { $0.first })
        #expect(try decodedMessage(report) == "First second    last")
    }

    @Test func report_limitsMessageBytesWithoutBreakingUnicode() throws {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        subject.report(.working, message: String(repeating: "a", count: 2047) + "🌍")

        let report = try #require(output.withLock { $0.first })
        let message = try decodedMessage(report)
        #expect(message == String(repeating: "a", count: 2047))
        #expect(message.utf8.count <= 2048)
        #expect(report.utf8.count <= 4096)
    }

    @Test func withCommandStatus_reportsWorkingThenDoneAndReturnsResult() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        let result = await subject.withCommandStatus {
            #expect(output.withLock { $0.count } == 1)
            return 42
        }

        #expect(result == 42)
        #expect(states(output.withLock { $0 }) == ["working", "done"])
    }

    @Test func withCommandStatus_reportsErrorAndRethrows() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        await #expect(throws: TestError.failed) {
            try await subject.withCommandStatus { throw TestError.failed }
        }

        #expect(states(output.withLock { $0 }) == ["working", "error"])
    }

    @Test func withCommandStatus_reportsIdleOnCancellation() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        await #expect(throws: CancellationError.self) {
            try await subject.withCommandStatus { throw CancellationError() }
        }

        #expect(states(output.withLock { $0 }) == ["working", "idle"])
    }

    @Test(arguments: [(Int32(0), "done"), (1, "error"), (2, "error"), (130, "idle")])
    func finish_reportsExitStatus(exitCode: Int32, expected: String) {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        subject.finish(exitCode: exitCode)

        #expect(states(output.withLock { $0 }) == [expected])
    }

    @Test func withBlockedStatus_reportsBlockedThenWorkingAndReturnsResult() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        let result = await subject.withBlockedStatus(kind: .auth, message: "Sign in") {
            #expect(states(output.withLock { $0 }) == ["blocked"])
            return 42
        }

        #expect(result == 42)
        #expect(states(output.withLock { $0 }) == ["blocked", "working"])
    }

    @Test func withBlockedStatus_restoresWorkingOnFailure() async {
        let output = Mutex<[String]>([])
        let subject = ProgramStatusReporter(isEnabled: true) { report in
            output.withLock { $0.append(report) }
        }

        await #expect(throws: TestError.failed) {
            try await subject.withCommandStatus {
                try await subject.withBlockedStatus(kind: .auth, message: "Sign in") {
                    throw TestError.failed
                }
            }
        }

        #expect(states(output.withLock { $0 }) == ["working", "blocked", "working", "error"])
    }

    private func states(_ reports: [String]) -> [String] {
        reports.map { report in
            String(report.split(separator: ":")[0].split(separator: "=")[1])
        }
    }

    private func decodedMessage(_ report: String) throws -> String {
        let encoded = try #require(report.components(separatedBy: ":msg=").last)
            .replacingOccurrences(of: "\u{1B}\\", with: "")
        let data = try #require(Data(base64Encoded: encoded))
        return try #require(String(data: data, encoding: .utf8))
    }
}
