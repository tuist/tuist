import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAcceptanceTesting
import TuistAutomation
import TuistCore
import TuistServer
import TuistSupport
import TuistTestCommand
import TuistTesting
import TuistXCResultService

@testable import TuistKit

/// The stress pass for real: Xcode runs the repetitions and the counts come back out of the
/// pass's own result bundle.
///
/// The unit tests assert the arguments the gate builds against a mocked xcodebuild, which
/// cannot tell whether Xcode honours them. This test runs Xcode, so it can. Only the verdict
/// is stubbed, since which test cases are new is the server's answer rather than Xcode's.
private struct StubVerdictService: CreateStressNewTestsVerdictServicing {
    let repetitions: Int
    let name: String
    let suiteName: String
    let moduleName: String

    func createVerdict(
        fullHandle _: String,
        serverURL _: URL,
        testCases _: [StressNewTestsVerdictTestCase]
    ) async throws -> Components.Schemas.StressNewTestsVerdict {
        .init(
            candidates: [
                .init(
                    excluded_reason: nil,
                    module_name: moduleName,
                    name: name,
                    repetitions: repetitions,
                    suite_name: suiteName
                ),
            ],
            _guard: nil,
            inventory_count: 40,
            parameters: .init(
                bulk_change_floor: 50,
                bulk_change_ratio: 0.3,
                candidate_cap: 200,
                repetition_curve: [.init(max_duration_ms: 5000, repetitions: repetitions)],
                wall_clock_ceiling_ms: 600_000
            )
        )
    }
}

// Serialized: each test drives Xcode against the same derived data and the same mocked
// process environment, which they cannot share concurrently.
@Suite(.serialized)
struct StressNewTestsAcceptanceTests {
    /// Three rather than the curve's ten: each repetition relaunches the test host, so this is
    /// the smallest count that still proves the iteration flags took effect.
    private static let repetitions = 3

    @Test(
        .withFixture("generated_ios_app_with_tests"),
        .inTemporaryDirectory,
        .withMockedEnvironment(inheritingVariables: ["PATH", "DEVELOPER_DIR"]),
        .withMockedLogger()
    ) func stresses_a_test_case_the_requested_number_of_times() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let testProductsPath = temporaryDirectory.appending(component: "MacFrameworkTests.xctestproducts")
        let firstPassBundlePath = temporaryDirectory.appending(component: "first-pass.xcresult")

        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--build-only",
                "--path", fixtureDirectory.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        try await TuistTest.run(
            TestCommand.self,
            [
                "MacFrameworkTests",
                "--without-building",
                "--path", fixtureDirectory.pathString,
                "--result-bundle-path", firstPassBundlePath.pathString,
                "--",
                "-testProductsPath", testProductsPath.pathString,
                "-destination", "platform=macOS",
            ]
        )

        let summary = try #require(await XCResultService().parse(path: firstPassBundlePath, rootDirectory: nil))
        let testCase = try #require(summary.testCases.first { $0.name.contains("testHello") })
        let moduleName = try #require(testCase.module)

        let subject = StressNewTestsService(
            createStressNewTestsVerdictService: StubVerdictService(
                repetitions: Self.repetitions,
                name: testCase.name,
                suiteName: testCase.testSuite ?? "MacFrameworkTests",
                moduleName: moduleName
            )
        )

        let serverURL = try #require(URL(string: "https://tuist.dev"))
        let result = await subject.run(
            mode: .report,
            testSummary: summary,
            firstPassFailed: false,
            fullHandle: "tuist/acceptance",
            serverURL: serverURL,
            mutedTests: [],
            stressPass: { identifiers, repetitions, stressResultBundlePath in
                try await XcodeBuildController().run(
                    arguments: [
                        "test-without-building",
                        "-testProductsPath", testProductsPath.pathString,
                        "-destination", "platform=macOS",
                        "-resultBundlePath", stressResultBundlePath.pathString,
                        "-test-iterations", "\(repetitions)",
                        "-test-repetition-relaunch-enabled", "YES",
                    ] + identifiers.flatMap { ["-only-testing", $0.description] }
                )
            }
        )

        let candidate = try #require(result?.candidates.first)
        // Reading the count back out of the bundle is the assertion: a pass that never ran, or
        // one Xcode ran once because it ignored the flags, reports something other than three.
        #expect(candidate.repetitions == Self.repetitions)
        #expect(candidate.repetitionResults.count == Self.repetitions)
        #expect(candidate.outcome == .passed)
        #expect(result?.outcome == .passed)
    }
}
