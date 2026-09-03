import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistCore
import TuistLogging
import TuistServer
import TuistSupport
import TuistXCResultService
import XCResultParser

/// One test case the stress gate examined.
public struct StressNewTestsCandidate: Equatable, Sendable {
    public enum Outcome: String, Sendable {
        case passed
        case disagreed
        case excludedTooSlow = "excluded_too_slow"
        case excludedCandidateCap = "excluded_candidate_cap"
        case notStressedCeiling = "not_stressed_ceiling"
        case notStressedError = "not_stressed_error"
    }

    /// The failure one repetition produced, flattened so a candidate stays comparable.
    public struct Failure: Equatable, Sendable {
        public let message: String?
        public let path: String?
        public let lineNumber: Int
        public let issueType: String

        public init(message: String?, path: String?, lineNumber: Int, issueType: String) {
            self.message = message
            self.path = path
            self.lineNumber = lineNumber
            self.issueType = issueType
        }

        init(_ failure: TestCaseFailure) {
            message = failure.message
            path = failure.path?.pathString
            lineNumber = failure.lineNumber
            issueType = failure.issueType?.rawValue ?? "issue_recorded"
        }
    }

    /// One execution of the candidate during the stress pass, in order.
    public struct Repetition: Equatable, Sendable {
        public let number: Int
        public let passed: Bool
        public let duration: Int
        public let failure: Failure?

        public init(number: Int, passed: Bool, duration: Int, failure: Failure?) {
            self.number = number
            self.passed = passed
            self.duration = duration
            self.failure = failure
        }
    }

    public let identifier: TestIdentifier
    public var repetitions: Int
    public var failedRepetitions: Int
    public var outcome: Outcome
    public let isQuarantined: Bool
    public var repetitionResults: [Repetition]

    public init(
        identifier: TestIdentifier,
        repetitions: Int,
        failedRepetitions: Int,
        outcome: Outcome,
        isQuarantined: Bool,
        repetitionResults: [Repetition] = []
    ) {
        self.identifier = identifier
        self.repetitions = repetitions
        self.failedRepetitions = failedRepetitions
        self.outcome = outcome
        self.isQuarantined = isQuarantined
        self.repetitionResults = repetitionResults
    }

    /// A muted candidate is stressed and recorded, but the gate inherits the mute and cannot fail on it.
    public var blocks: Bool { outcome == .disagreed && !isQuarantined }
}

/// What the stress gate did for one run.
public struct StressNewTestsResult: Equatable, Sendable {
    public enum Outcome: String, Sendable {
        case passed
        case disagreed
        case skipped
        case noCandidates = "no_candidates"
    }

    public enum SkipReason: String, Sendable {
        case firstPassFailed = "first_pass_failed"
        case noDefaultBranch = "no_default_branch"
        case noDefaultBranchHistory = "no_default_branch_history"
        case bulkChange = "bulk_change"
        case verdictUnavailable = "verdict_unavailable"
    }

    public let mode: StressNewTestsMode
    public let outcome: Outcome
    public let skipReason: SkipReason?
    public let newCount: Int
    public let stressedCount: Int
    public let excludedCount: Int
    public let inventoryCount: Int
    public let candidates: [StressNewTestsCandidate]

    public init(
        mode: StressNewTestsMode,
        outcome: Outcome,
        skipReason: SkipReason? = nil,
        newCount: Int,
        stressedCount: Int,
        excludedCount: Int,
        inventoryCount: Int,
        candidates: [StressNewTestsCandidate]
    ) {
        self.mode = mode
        self.outcome = outcome
        self.skipReason = skipReason
        self.newCount = newCount
        self.stressedCount = stressedCount
        self.excludedCount = excludedCount
        self.inventoryCount = inventoryCount
        self.candidates = candidates
    }

    public var blockingCandidates: [StressNewTestsCandidate] { candidates.filter(\.blocks) }

    /// Whether the run must fail: only in `enforce`, and only on a disagreement the gate holds against the run.
    public var blocks: Bool { mode == .enforce && !blockingCandidates.isEmpty }

    public var serverPayload: Components.Schemas.StressNewTestsResult {
        .init(
            excluded_count: excludedCount,
            inventory_count: inventoryCount,
            mode: mode == .enforce ? .enforce : .report,
            new_count: newCount,
            outcome: .init(rawValue: outcome.rawValue) ?? .skipped,
            skip_reason: skipReason.flatMap { .init(rawValue: $0.rawValue) },
            stressed_count: stressedCount,
            test_cases: candidates.map { candidate in
                .init(
                    failed_repetitions: candidate.failedRepetitions,
                    is_quarantined: candidate.isQuarantined,
                    module_name: candidate.identifier.target,
                    name: candidate.identifier.method ?? "",
                    outcome: .init(rawValue: candidate.outcome.rawValue) ?? .not_stressed_error,
                    repetition_results: candidate.repetitionResults.map { repetition in
                        .init(
                            duration: repetition.duration,
                            failure: repetition.failure.map { failure in
                                .init(
                                    issue_type: .init(rawValue: failure.issueType),
                                    line_number: failure.lineNumber,
                                    message: failure.message,
                                    path: failure.path
                                )
                            },
                            repetition_number: repetition.number,
                            status: repetition.passed ? .success : .failure
                        )
                    },
                    repetitions: candidate.repetitions,
                    suite_name: candidate.identifier.class
                )
            }
        )
    }
}

public enum StressNewTestsError: FatalError, Equatable {
    case blocked([StressNewTestsCandidate])

    public var description: String {
        switch self {
        case let .blocked(candidates):
            return candidates
                .map {
                    "\($0.identifier.method ?? $0.identifier.description) failed \($0.failedRepetitions) of \($0.repetitions) repetitions and blocked this run."
                }
                .joined(separator: "\n")
        }
    }

    public var type: ErrorType { .abort }
}

/// Reruns the given identifiers `repetitions` times each in a fresh process per repetition, writing the
/// result bundle to `resultBundlePath`. Throws when xcodebuild fails, which includes a repetition failing.
public typealias StressNewTestsPass = (
    _ identifiers: [TestIdentifier],
    _ repetitions: Int,
    _ resultBundlePath: AbsolutePath
) async throws -> Void

@Mockable
public protocol StressNewTestsServicing {
    /// Runs the gate for a first pass that already happened. Returns `nil` when nothing ran and nothing
    /// should be recorded: the account is not entitled.
    func run(
        mode: StressNewTestsMode,
        testSummary: TestSummary?,
        firstPassFailed: Bool,
        fullHandle: String,
        serverURL: URL,
        mutedTests: [TestIdentifier],
        stressPass: @escaping StressNewTestsPass
    ) async -> StressNewTestsResult?
}

public struct StressNewTestsService: StressNewTestsServicing {
    private let createStressNewTestsVerdictService: CreateStressNewTestsVerdictServicing
    private let xcResultService: XCResultServicing
    private let fileSystem: FileSysteming

    public init(
        createStressNewTestsVerdictService: CreateStressNewTestsVerdictServicing = CreateStressNewTestsVerdictService(),
        xcResultService: XCResultServicing = XCResultService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.createStressNewTestsVerdictService = createStressNewTestsVerdictService
        self.xcResultService = xcResultService
        self.fileSystem = fileSystem
    }

    public func run(
        mode: StressNewTestsMode,
        testSummary: TestSummary?,
        firstPassFailed: Bool,
        fullHandle: String,
        serverURL: URL,
        mutedTests: [TestIdentifier],
        stressPass: @escaping StressNewTestsPass
    ) async -> StressNewTestsResult? {
        guard !firstPassFailed, let testSummary else {
            let result = StressNewTestsResult(
                mode: mode,
                outcome: .skipped,
                skipReason: .firstPassFailed,
                newCount: 0,
                stressedCount: 0,
                excludedCount: 0,
                inventoryCount: 0,
                candidates: []
            )
            printHeading()
            Logger.current.notice("Skipped: the first pass already failed, so nothing was stressed.")
            return result
        }

        let executed = testSummary.testCases.filter { $0.status != .skipped }

        let verdict: Components.Schemas.StressNewTestsVerdict
        do {
            verdict = try await createStressNewTestsVerdictService.createVerdict(
                fullHandle: fullHandle,
                serverURL: serverURL,
                testCases: executed.compactMap { testCase in
                    guard let module = testCase.module else { return nil }
                    return StressNewTestsVerdictTestCase(
                        name: testCase.name,
                        suiteName: testCase.testSuite,
                        moduleName: module,
                        duration: testCase.duration
                    )
                }
            )
        } catch {
            AlertController.current.warning(
                .alert("Failed to fetch the stress gate verdict: \(error.localizedDescription). Nothing was stressed.")
            )
            return StressNewTestsResult(
                mode: mode,
                outcome: .skipped,
                skipReason: .verdictUnavailable,
                newCount: 0,
                stressedCount: 0,
                excludedCount: 0,
                inventoryCount: 0,
                candidates: []
            )
        }

        if let guardSignal = verdict._guard {
            printHeading()
            Logger.current.notice("\(Self.guardDescription(guardSignal))")
            return StressNewTestsResult(
                mode: mode,
                outcome: .skipped,
                skipReason: .init(rawValue: guardSignal.kind.rawValue),
                newCount: guardSignal.new_count,
                stressedCount: 0,
                excludedCount: 0,
                inventoryCount: guardSignal.inventory_count,
                candidates: []
            )
        }

        var candidates: [StressNewTestsCandidate] = verdict.candidates.compactMap { candidate in
            guard let identifier = try? TestIdentifier(
                target: candidate.module_name,
                class: candidate.suite_name.isEmpty ? nil : candidate.suite_name,
                method: candidate.name
            ) else { return nil }
            let outcome: StressNewTestsCandidate.Outcome =
                switch candidate.excluded_reason {
                case .too_slow: .excludedTooSlow
                case .candidate_cap: .excludedCandidateCap
                case nil: .passed
                }
            return StressNewTestsCandidate(
                identifier: identifier,
                repetitions: candidate.repetitions,
                failedRepetitions: 0,
                outcome: outcome,
                isQuarantined: mutedTests.contains(identifier)
            )
        }

        if candidates.isEmpty {
            return StressNewTestsResult(
                mode: mode,
                outcome: .noCandidates,
                newCount: 0,
                stressedCount: 0,
                excludedCount: 0,
                inventoryCount: verdict.inventory_count,
                candidates: []
            )
        }

        let ceiling = Duration.milliseconds(verdict.parameters.wall_clock_ceiling_ms)
        await stressCandidates(&candidates, ceiling: ceiling, stressPass: stressPass)

        let stressedCount = candidates.filter { $0.outcome == .passed || $0.outcome == .disagreed }.count
        let result = StressNewTestsResult(
            mode: mode,
            outcome: candidates.contains(where: \.blocks) ? .disagreed : .passed,
            newCount: candidates.count,
            stressedCount: stressedCount,
            excludedCount: candidates.count - stressedCount,
            inventoryCount: verdict.inventory_count,
            candidates: candidates
        )
        print(result, ceiling: ceiling)
        return result
    }

    /// How many candidates share one xcodebuild invocation. Small enough that the
    /// wall-clock ceiling is consulted often, large enough that the cap's 200
    /// candidates do not become 200 invocations.
    static let stressBatchSize = 10

    private struct ObservedRepetitions {
        let repetitions: Int
        let failed: Int
        let results: [StressNewTestsCandidate.Repetition]
    }

    private func stressCandidates(
        _ candidates: inout [StressNewTestsCandidate],
        ceiling: Duration,
        stressPass: StressNewTestsPass
    ) async {
        let start = ContinuousClock.now
        let groups = Dictionary(
            grouping: candidates.indices.filter { candidates[$0].repetitions > 0 },
            by: { candidates[$0].repetitions }
        )

        for repetitions in groups.keys.sorted(by: >) {
            // The budget is rechecked between batches rather than between groups: a single
            // group can hold every candidate the cap allows, so one invocation for the whole
            // group would run far past the ceiling before anything looked at the clock.
            let group = groups[repetitions] ?? []
            for batchStart in stride(from: 0, to: group.count, by: Self.stressBatchSize) {
                let indices = Array(group[batchStart ..< min(batchStart + Self.stressBatchSize, group.count)])
                if start.duration(to: .now) >= ceiling {
                    for index in indices {
                        candidates[index].outcome = .notStressedCeiling
                    }
                    continue
                }

                let identifiers = indices.map { candidates[$0].identifier }
                let outcomes = await stress(identifiers: identifiers, repetitions: repetitions, stressPass: stressPass)
                for index in indices {
                    let identifier = candidates[index].identifier
                    guard let observed = outcomes[identifier] else {
                        candidates[index].outcome = .notStressedError
                        continue
                    }

                    // Record what actually ran, never what was asked for. A pass that dies
                    // partway still leaves a parseable bundle, and reporting a test as having
                    // held up over ten repetitions when three of them ran is the one lie this
                    // gate must not tell. A failure, on the other hand, is proof however few
                    // repetitions produced it.
                    candidates[index].repetitions = observed.results.count
                    candidates[index].failedRepetitions = observed.failed
                    candidates[index].repetitionResults = observed.results
                    candidates[index].outcome =
                        if observed.failed > 0 {
                            .disagreed
                        } else if observed.results.count >= repetitions {
                            .passed
                        } else {
                            .notStressedError
                        }
                }
            }
        }
    }

    private func stress(
        identifiers: [TestIdentifier],
        repetitions: Int,
        stressPass: StressNewTestsPass
    ) async -> [TestIdentifier: ObservedRepetitions] {
        guard let directory = try? await fileSystem.makeTemporaryDirectory(prefix: "stress-new-tests") else {
            return [:]
        }
        defer { Task { try? await fileSystem.remove(directory) } }
        let resultBundlePath = directory.appending(component: "stress-\(repetitions).xcresult")

        var passError: Error?
        do {
            try await stressPass(identifiers, repetitions, resultBundlePath)
        } catch {
            passError = error
        }

        guard let summary = try? await xcResultService.parse(path: resultBundlePath, rootDirectory: nil) else {
            if let passError {
                AlertController.current.warning(
                    .alert("The stress pass with \(repetitions) repetitions failed to run: \(passError.localizedDescription)")
                )
            }
            return [:]
        }

        var observed: [TestIdentifier: ObservedRepetitions] = [:]
        for testCase in summary.testCases {
            guard let module = testCase.module,
                  let identifier = try? TestIdentifier(target: module, class: testCase.testSuite, method: testCase.name),
                  identifiers.contains(identifier)
            else { continue }
            // A single-iteration pass produces no repetition nodes, so the test case's own
            // result is repetition one.
            let results: [StressNewTestsCandidate.Repetition]
            if testCase.repetitions.isEmpty {
                results = [
                    StressNewTestsCandidate.Repetition(
                        number: 1,
                        passed: testCase.status != .failed,
                        duration: testCase.duration ?? 0,
                        failure: testCase.failures.first.map(StressNewTestsCandidate.Failure.init)
                    ),
                ]
            } else {
                results = testCase.repetitions
                    .sorted { $0.repetitionNumber < $1.repetitionNumber }
                    .map { repetition in
                        StressNewTestsCandidate.Repetition(
                            number: repetition.repetitionNumber,
                            passed: repetition.status != .failed,
                            duration: repetition.duration,
                            failure: repetition.failures.first.map(StressNewTestsCandidate.Failure.init)
                        )
                    }
            }
            observed[identifier] = ObservedRepetitions(
                repetitions: results.count,
                failed: results.filter { !$0.passed }.count,
                results: results
            )
        }
        return observed
    }

    private func printHeading() {
        Logger.current.notice("Stress-testing new tests", metadata: .section)
    }

    private func print(_ result: StressNewTestsResult, ceiling: Duration) {
        printHeading()
        Logger.current.notice(
            "\(result.newCount) new test cases, \(result.stressedCount) stressed, \(result.excludedCount) excluded"
        )
        let width = result.candidates.map(\.identifier.description.count).max() ?? 0
        for candidate in result.candidates {
            let name = candidate.identifier.description.padding(toLength: width, withPad: " ", startingAt: 0)
            Logger.current.notice("\(name)   \(Self.outcomeDescription(candidate, ceiling: ceiling))")
        }
        if result.mode == .report {
            for candidate in result.blockingCandidates {
                AlertController.current.warning(
                    .alert(
                        "\(candidate.identifier.method ?? candidate.identifier.description) failed \(candidate.failedRepetitions) of \(candidate.repetitions) repetitions and would have blocked this run.",
                        takeaway: "Pass --stress-new-tests enforce to make it blocking."
                    )
                )
            }
        }
    }

    static func outcomeDescription(_ candidate: StressNewTestsCandidate, ceiling: Duration) -> String {
        switch candidate.outcome {
        case .passed:
            return "\(candidate.repetitions) repetitions, passed"
        case .disagreed:
            let muted = candidate.isQuarantined ? " (muted)" : ""
            return "\(candidate.repetitions) repetitions, \(candidate.failedRepetitions) failed\(muted)"
        case .excludedTooSlow:
            return "excluded, slower than the curve's last bucket"
        case .excludedCandidateCap:
            return "excluded, beyond the candidate cap"
        case .notStressedCeiling:
            let seconds = Int(ceiling.components.seconds)
            return "not stressed, the \(seconds / 60 > 0 ? "\(seconds / 60) minute" : "\(seconds) second") wall-clock ceiling was reached"
        case .notStressedError:
            return "not stressed, the stress pass failed to run"
        }
    }

    static func guardDescription(_ signal: Components.Schemas.StressNewTestsVerdict._guardPayload) -> String {
        switch signal.kind {
        case .no_default_branch:
            return "Skipped: the project has no default branch, so no test case can be new. Set one in the project settings."
        case .no_default_branch_history:
            return "Skipped: no test case has run in CI on the default branch yet, so all \(signal.new_count) test cases would read as new."
        case .bulk_change:
            return "Skipped: \(signal.new_count) of the run's test cases are new against \(signal.inventory_count) on the default branch, so the bulk-change guard ran nothing."
        }
    }
}
