import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistAlert
import TuistCore
import TuistServer
import TuistSupport
import TuistTesting
import TuistXCResultService
import XCResultParser

@testable import TuistKit

@Suite
struct StressNewTestsServiceTests {
    private let verdictService = MockCreateStressNewTestsVerdictServicing()
    private let xcResultService = MockXCResultServicing()
    private let subject: StressNewTestsService
    private let serverURL = URL(string: "https://tuist.dev")!

    init() {
        subject = StressNewTestsService(
            createStressNewTestsVerdictService: verdictService,
            xcResultService: xcResultService,
            fileSystem: FileSystem()
        )
    }

    private func summary(_ testCases: [TestCase]) -> TestSummary {
        TestSummary(
            testPlanName: nil,
            status: testCases.contains { $0.status == .failed } ? .failed : .passed,
            duration: 100,
            testModules: [
                TestModule(name: "AppTests", status: .passed, duration: 100, testSuites: [], testCases: testCases),
            ]
        )
    }

    private func testCase(_ name: String, duration: Int = 10, repetitionStatuses: [TestStatus] = []) -> TestCase {
        TestCase(
            name: name,
            testSuite: "CheckoutTests",
            module: "AppTests",
            duration: duration,
            status: .passed,
            failures: [],
            repetitions: repetitionStatuses.enumerated().map { index, status in
                TestCaseRepetition(
                    repetitionNumber: index + 1,
                    name: "Repetition \(index + 1)",
                    status: status,
                    duration: 5,
                    failures: []
                )
            }
        )
    }

    private func verdict(
        candidates: [Components.Schemas.StressNewTestsVerdict.candidatesPayloadPayload],
        guardSignal: Components.Schemas.StressNewTestsVerdict._guardPayload? = nil,
        ceiling: Int = 600_000
    ) -> Components.Schemas.StressNewTestsVerdict {
        .init(
            candidates: candidates,
            _guard: guardSignal,
            inventory_count: 40,
            parameters: .init(
                bulk_change_floor: 50,
                bulk_change_ratio: 0.3,
                candidate_cap: 200,
                repetition_curve: [.init(max_duration_ms: 5000, repetitions: 10)],
                wall_clock_ceiling_ms: ceiling
            )
        )
    }

    private func candidate(
        _ name: String,
        repetitions: Int = 10,
        excluded: Components.Schemas.StressNewTestsVerdict.candidatesPayloadPayload.excluded_reasonPayload? = nil
    )
        -> Components.Schemas.StressNewTestsVerdict.candidatesPayloadPayload
    {
        .init(
            excluded_reason: excluded,
            module_name: "AppTests",
            name: name,
            repetitions: repetitions,
            suite_name: "CheckoutTests"
        )
    }

    private func identifier(_ name: String) throws -> TestIdentifier {
        try TestIdentifier(target: "AppTests", class: "CheckoutTests", method: name)
    }

    @Test(.withMockedDependencies())
    func skipsWhenTheFirstPassFailed() async throws {
        let result = await subject.run(
            mode: .enforce,
            testSummary: summary([testCase("testNew()")]),
            firstPassFailed: true,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { _, _, _ in Issue.record("must not run a stress pass") }
        )

        #expect(result?.outcome == .skipped)
        #expect(result?.skipReason == .firstPassFailed)
        #expect(result?.blocks == false)
        verify(verdictService).createVerdict(fullHandle: .any, serverURL: .any, testCases: .any).called(0)
    }

    @Test(.withMockedDependencies())
    func sendsExecutedTestCasesAndRecordsTheGuard() async throws {
        given(verdictService)
            .createVerdict(
                fullHandle: .value("tuist/app"),
                serverURL: .any,
                testCases: .matching { $0.map(\.name) == ["testNew()"] }
            )
            .willReturn(verdict(candidates: [], guardSignal: .init(inventory_count: 100, kind: .bulk_change, new_count: 70)))

        var skipped = testCase("testSkipped()")
        skipped = TestCase(
            name: skipped.name,
            testSuite: skipped.testSuite,
            module: skipped.module,
            duration: 0,
            status: .skipped,
            failures: []
        )

        let result = await subject.run(
            mode: .enforce,
            testSummary: summary([testCase("testNew()"), skipped]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { _, _, _ in Issue.record("must not run a stress pass") }
        )

        #expect(result?.outcome == .skipped)
        #expect(result?.skipReason == .bulkChange)
        #expect(result?.newCount == 70)
        #expect(result?.inventoryCount == 100)
        #expect(result?.blocks == false)
    }

    @Test(.withMockedDependencies())
    func skipsWhenTheVerdictIsUnavailable() async throws {
        given(verdictService)
            .createVerdict(fullHandle: .any, serverURL: .any, testCases: .any)
            .willThrow(TestError("connection refused"))

        let result = await subject.run(
            mode: .enforce,
            testSummary: summary([testCase("testNew()")]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { _, _, _ in Issue.record("must not run a stress pass") }
        )

        #expect(result?.outcome == .skipped)
        #expect(result?.skipReason == .verdictUnavailable)
        #expect(result?.blocks == false)
    }

    @Test(.withMockedDependencies())
    func stressesEachRepetitionGroupOnceAndPricesTheOutcomes() async throws {
        given(verdictService)
            .createVerdict(fullHandle: .any, serverURL: .any, testCases: .any)
            .willReturn(verdict(candidates: [
                candidate("testFlaky()"),
                candidate("testStable()"),
                candidate("testSlow()", repetitions: 3),
                candidate("testTooSlow()", repetitions: 0, excluded: .too_slow),
            ]))
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willProduce { path, _ in
                if path.basename.contains("stress-10") {
                    return summary([
                        testCase(
                            "testFlaky()",
                            repetitionStatuses: [
                                .passed,
                                .failed,
                                .passed,
                                .passed,
                                .passed,
                                .passed,
                                .passed,
                                .failed,
                                .passed,
                                .passed,
                            ]
                        ),
                        testCase("testStable()", repetitionStatuses: Array(repeating: .passed, count: 10)),
                    ])
                }
                return summary([testCase("testSlow()", repetitionStatuses: [.passed, .passed, .passed])])
            }

        let passes = PassRecorder()

        let result = await subject.run(
            mode: .report,
            testSummary: summary([
                testCase("testFlaky()"),
                testCase("testStable()"),
                testCase("testSlow()"),
                testCase("testTooSlow()"),
                testCase("testOld()"),
            ]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { identifiers, repetitions, _ in
                await passes.record(identifiers: identifiers, repetitions: repetitions)
                if repetitions == 10 { throw TestError("xcodebuild exited with 65") }
            }
        )

        let recorded = await passes.passes
        #expect(recorded.map(\.repetitions) == [10, 3])
        #expect(try recorded[0].identifiers == [identifier("testFlaky()"), identifier("testStable()")])
        #expect(try recorded[1].identifiers == [identifier("testSlow()")])

        let result_ = try #require(result)
        #expect(result_.outcome == .disagreed)
        #expect(result_.newCount == 4)
        #expect(result_.stressedCount == 3)
        #expect(result_.excludedCount == 1)
        #expect(result_.blocks == false)
        let byName = Dictionary(uniqueKeysWithValues: result_.candidates.map { ($0.identifier.method!, $0) })
        #expect(byName["testFlaky()"]?.outcome == .disagreed)
        #expect(byName["testFlaky()"]?.failedRepetitions == 2)
        #expect(byName["testFlaky()"]?.repetitions == 10)
        #expect(byName["testStable()"]?.outcome == .passed)
        #expect(byName["testSlow()"]?.outcome == .passed)
        #expect(byName["testSlow()"]?.repetitions == 3)
        #expect(byName["testTooSlow()"]?.outcome == .excludedTooSlow)
        #expect(AlertController.current.warnings().count == 1)
        #expect(result_.serverPayload.outcome == .disagreed)
        #expect(result_.serverPayload.test_cases.count == 4)
    }

    @Test(.withMockedDependencies())
    func enforceBlocksOnlyOnUnmutedDisagreements() async throws {
        given(verdictService)
            .createVerdict(fullHandle: .any, serverURL: .any, testCases: .any)
            .willReturn(verdict(candidates: [candidate("testMuted()", repetitions: 2), candidate("testFlaky()", repetitions: 2)]))
        given(xcResultService)
            .parse(path: .any, rootDirectory: .any)
            .willReturn(summary([
                testCase("testMuted()", repetitionStatuses: [.passed, .failed]),
                testCase("testFlaky()", repetitionStatuses: [.failed, .passed]),
            ]))

        let result = try #require(await subject.run(
            mode: .enforce,
            testSummary: summary([testCase("testMuted()"), testCase("testFlaky()")]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [identifier("testMuted()")],
            stressPass: { _, _, _ in }
        ))

        #expect(result.blocks == true)
        #expect(try result.blockingCandidates.map(\.identifier) == [identifier("testFlaky()")])
        let muted = try #require(result.candidates.first { $0.identifier.method == "testMuted()" })
        #expect(muted.outcome == .disagreed)
        #expect(muted.isQuarantined == true)
        #expect(AlertController.current.warnings().isEmpty)
        #expect(StressNewTestsError.blocked(result.blockingCandidates)
            .description == "testFlaky() failed 1 of 2 repetitions and blocked this run.")
    }

    @Test(.withMockedDependencies())
    func recordsNoCandidatesWhenTheBranchAddsNoTests() async throws {
        given(verdictService)
            .createVerdict(fullHandle: .any, serverURL: .any, testCases: .any)
            .willReturn(verdict(candidates: []))

        let result = await subject.run(
            mode: .report,
            testSummary: summary([testCase("testOld()")]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { _, _, _ in Issue.record("must not run a stress pass") }
        )

        #expect(result?.outcome == .noCandidates)
        #expect(result?.inventoryCount == 40)
    }

    @Test(.withMockedDependencies())
    func marksCandidatesNotStressedWhenTheCeilingIsAlreadyReached() async throws {
        given(verdictService)
            .createVerdict(fullHandle: .any, serverURL: .any, testCases: .any)
            .willReturn(verdict(candidates: [candidate("testNew()")], ceiling: 0))

        let result = try #require(await subject.run(
            mode: .enforce,
            testSummary: summary([testCase("testNew()")]),
            firstPassFailed: false,
            fullHandle: "tuist/app",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { _, _, _ in Issue.record("must not run a stress pass") }
        ))

        #expect(result.candidates.map(\.outcome) == [.notStressedCeiling])
        #expect(result.stressedCount == 0)
        #expect(result.excludedCount == 1)
        #expect(result.outcome == .passed)
    }
}

private actor PassRecorder {
    private(set) var passes: [(identifiers: [TestIdentifier], repetitions: Int)] = []

    func record(identifiers: [TestIdentifier], repetitions: Int) {
        passes.append((identifiers, repetitions))
    }
}

@Suite
struct StressPassArgumentsTests {
    @Test
    func xcodebuildStressPassReplacesActionSelectionAndRepetitionOptions() throws {
        let arguments = XcodeBuildTestCommandService.stressPassArguments(
            from: [
                "test", "-workspace", "App.xcworkspace", "-scheme", "App",
                "-only-testing", "AppTests/Old", "-skip-testing:AppTests/Skipped",
                "-resultBundlePath", "/tmp/first.xcresult",
                "-retry-tests-on-failure", "-test-iterations", "3",
                "-destination", "platform=macOS",
            ],
            identifiers: [try TestIdentifier(target: "AppTests", class: "CheckoutTests", method: "testNew()")],
            repetitions: 10,
            resultBundlePath: try AbsolutePath(validating: "/tmp/stress-10.xcresult")
        )

        #expect(arguments == [
            "test-without-building", "-workspace", "App.xcworkspace", "-scheme", "App",
            "-destination", "platform=macOS",
            "-only-testing", "AppTests/CheckoutTests/testNew()",
            "-test-iterations", "10",
            "-test-repetition-relaunch-enabled", "YES",
            "-resultBundlePath", "/tmp/stress-10.xcresult",
        ])
    }

    @Test
    func serviceStressPassthroughDropsRepetitionAndSelectionOptions() {
        let arguments = TestService.stressPassthroughArguments([
            "-parallel-testing-enabled", "YES",
            "-test-iterations", "3", "-retry-tests-on-failure",
            "-only-testing:AppTests/Old", "-skip-testing", "AppTests/Skipped",
            "-resultBundlePath", "/tmp/first.xcresult",
            "-derivedDataPath", "/tmp/dd",
        ])

        #expect(arguments == ["-parallel-testing-enabled", "YES", "-derivedDataPath", "/tmp/dd"])
    }
}
