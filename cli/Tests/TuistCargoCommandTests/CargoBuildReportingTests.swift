import Foundation
import Testing
@testable import TuistCargoCommand

struct CargoBuildReportingTests {
    private let started = Date(timeIntervalSince1970: 1000)
    private let marker = "    Finished `test` profile [unoptimized + debuginfo] target(s) in 0.12s\n"
    private let running = "     Running unittests src/lib.rs (target/debug/deps/store-0123456789abcdef)\n"

    private func compilation(failed: Bool) -> CargoCompilation {
        CargoCompilation(
            name: "store", source: "src/lib.rs", kind: "test", dependencies: [],
            startOffsetMs: 0, durationMs: 100, status: failed ? "failure" : "success", diagnostics: []
        )
    }

    @Test func stopsBuildTimingBeforeTestExecutionEvenWithoutCompilerRows() throws {
        var progress = CargoTestBuildProgress()
        let compiled = started.addingTimeInterval(2)
        progress.receive(Array(marker.utf8), at: compiled)
        #expect(progress.finished == nil)
        progress.receive(Array(running.utf8), at: compiled.addingTimeInterval(0.25))
        let result = CargoTestResult(
            report: nil, buildFinished: progress.finished, finished: started.addingTimeInterval(30), canReportBuildFailure: false
        )
        let outcome = try #require(CargoBuildOutcome.test(result, compilations: []))
        #expect(!outcome.failed)
        #expect(outcome.finished == compiled)
        #expect(CargoCommandService.milliseconds(outcome.finished.timeIntervalSince(started)) == 2000)
    }

    @Test func compilationSuccessIsIndependentOfLaterCompilerFailuresInTests() throws {
        let result = CargoTestResult(
            report: nil, buildFinished: started, finished: started.addingTimeInterval(30), canReportBuildFailure: false
        )
        let outcome = try #require(CargoBuildOutcome.test(result, compilations: [compilation(failed: true)]))
        #expect(!outcome.failed)
        #expect(outcome.finished == started)
    }

    @Test func reportsObservedCompilationFailuresWithoutABuildCompletionMarker() throws {
        let finished = started.addingTimeInterval(3)
        let result = CargoTestResult(report: nil, buildFinished: nil, finished: finished, canReportBuildFailure: true)
        let outcome = try #require(CargoBuildOutcome.test(result, compilations: [compilation(failed: true)]))
        #expect(outcome.failed)
        #expect(outcome.finished == finished)
    }

    @Test func omitsUnmeasuredBuildsRatherThanGuessingFromCompilerRowsOrTestExit() {
        let result = CargoTestResult(
            report: nil, buildFinished: nil, finished: started.addingTimeInterval(30), canReportBuildFailure: true
        )
        #expect(CargoBuildOutcome.test(result, compilations: []) == nil)
        #expect(CargoBuildOutcome.test(result, compilations: [compilation(failed: false)]) == nil)
        let success = CargoTestResult(report: nil, buildFinished: nil, finished: started, canReportBuildFailure: false)
        #expect(CargoBuildOutcome.test(success, compilations: [compilation(failed: true)]) == nil)
    }

    @Test func doesNotMisattributeNestedCompilerFailuresWhenTestsWereObservedWithoutABuildBoundary() {
        let result = CargoTestResult(
            report: CargoTestReport(modules: [], duration: 0), buildFinished: nil, finished: started, canReportBuildFailure: true
        )
        #expect(CargoBuildOutcome.test(result, compilations: [compilation(failed: true)]) == nil)
    }

    @Test func excludesCompilerRowsThatExtendBeyondTheBuildPhase() {
        let outcome = CargoBuildOutcome(finished: started.addingTimeInterval(1), failed: false)
        var built = compilation(failed: false)
        built.startOffsetMs = 900
        var rounded = built
        rounded.durationMs = 101
        var overlapping = built
        overlapping.durationMs = 102
        var nested = compilation(failed: true)
        nested.startOffsetMs = 1500
        var invalidOffset = built
        invalidOffset.startOffsetMs = Int.min
        var invalidDuration = built
        invalidDuration.durationMs = Int.max
        var negativeDuration = built
        negativeDuration.durationMs = -1
        #expect(outcome.compilations(
            [built, rounded, overlapping, nested, invalidOffset, invalidDuration, negativeDuration], started: started
        ) == [built, rounded])
    }

    @Test func requiresExecutionEvidenceAndUsesTheLastCompilationSummary() {
        var progress = CargoTestBuildProgress()
        progress.receive(Array(marker.utf8), at: started)
        #expect(progress.finished == nil)
        let outerFinished = started.addingTimeInterval(2)
        progress.receive(Array(marker.utf8), at: outerFinished)
        progress.receive(Array(running.utf8), at: outerFinished.addingTimeInterval(0.1))
        #expect(progress.finished == outerFinished)
    }

    @Test func retainsSuccessfulCompilationWhenThereAreNoRunnableTests() {
        var progress = CargoTestBuildProgress()
        progress.receive(Array(marker.utf8), at: started)
        #expect(progress.finished == nil)
        #expect(progress.completion(succeeded: true) == started)
        #expect(progress.completion(succeeded: false) == nil)
    }

    @Test func rejectsUnconfirmedCompletionOnCompilationFailure() {
        var progress = CargoTestBuildProgress()
        progress.receive(Array((marker + "error: could not compile store\n").utf8), at: started)
        #expect(progress.finished == nil)
        #expect(progress.canReportFailure)
    }

    @Test func recognizesChunkedColoredBuildCompletionAndRetainsTheFirstBoundary() {
        var progress = CargoTestBuildProgress()
        let colored = marker.replacingOccurrences(of: "Finished", with: "\u{1B}[1m\u{1B}[32mFinished\u{1B}[0m")
        for byte in colored.utf8 {
            progress.receive([byte], at: started)
        }
        progress.receive(Array(running.utf8), at: started.addingTimeInterval(0.1))
        progress.receive(Array(marker.utf8), at: started.addingTimeInterval(30))
        #expect(progress.finished == started)
    }

    @Test(arguments: [
        "    Finished `release` profile [optimized] target(s) in 1m 23s\n",
        "    Finished `ci` profile [optimized + debuginfo] target(s) in 0.00s\r\n",
        "    Finished test [unoptimized + debuginfo] target(s) in 0.12s\n",
        "    Finished `test` profile [unoptimized] target(s) in 1h 2m 3s\n",
    ])
    func supportsProfilesAndLongBuilds(line: String) {
        var progress = CargoTestBuildProgress()
        progress.receive(Array((line + running).utf8), at: started)
        #expect(progress.finished == started)
    }

    @Test(arguments: [
        "     Running unittests src/lib.rs (target/debug/deps/store-0123456789abcdef)\n",
        "   Doc-tests store\n",
        "  --- stdout\n",
        "  --- stderr\n",
        String(repeating: "x", count: 4097) + "\n",
    ])
    func doesNotInterpretTestOutputOrOversizedLinesAsBuildCompletion(prefix: String) {
        var progress = CargoTestBuildProgress()
        progress.receive(Array((prefix + marker + running).utf8), at: started)
        #expect(progress.finished == nil)
        #expect(!progress.canReportFailure)
        #expect(progress.completion(succeeded: true) == nil)
    }

    @Test(arguments: [
        "warning: Finished `test` profile [unoptimized + debuginfo] target(s) in 0.12s\n",
        "Finished running tests in 0.12s\n",
        "Finished `test` profile [unoptimized + debuginfo] target(s) in unknown\n",
    ])
    func requiresACargoBuildSummary(line: String) {
        var progress = CargoTestBuildProgress()
        progress.receive(Array((line + running).utf8), at: started)
        #expect(progress.finished == nil)
    }

    @Test func distinguishesBuildOnlyCargoTestsFromExecutingTests() {
        #expect(CargoInvocation(["test"]).executesTests)
        #expect(CargoInvocation(["t", "--doc"]).executesTests)
        #expect(CargoInvocation(["test", "--", "--list"]).executesTests)
        #expect(CargoInvocation(["test", "--", "--no-run"]).executesTests)
        #expect(!CargoInvocation(["test", "--no-run"]).executesTests)
        #expect(!CargoInvocation(["build"]).executesTests)
        #expect(!CargoInvocation(["nextest", "run"]).executesTests)
    }
}
