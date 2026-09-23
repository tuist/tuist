import Command
import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer
import TuistTesting

@testable import TuistBazelCommand

struct BazelTestCommandServiceTests {
    @Test func parses_wrapper_options_and_preserves_bazel_arguments() throws {
        let command = try BazelTestCommand.parse([
            "--no-quarantine", "--bazel", "bazelisk", "--", "--config=ci", "--", "//:suite", "-//:excluded",
        ])
        #expect(!command.quarantine)
        #expect(command.bazel == "bazelisk")
        #expect(command.arguments == ["--config=ci", "--", "//:suite", "-//:excluded"])
    }

    @Test func exclusions_follow_user_patterns_and_expand_suites() throws {
        #expect(try BazelTestCommandService.excluding(["//app:tests"], from: ["--config=ci", "--", "//:suite"]) == [
            "--config=ci", "--expand_test_suites", "--target_pattern_file=", "--", "//:suite", "-//app:tests",
        ])
        #expect(try BazelTestCommandService.excluding(["//app:tests"], from: ["//...", "--test_arg=a b"]) == [
            "//...", "--test_arg=a b", "--expand_test_suites", "--target_pattern_file=", "--", "-//app:tests",
        ])
    }

    @Test(arguments: ["//app:all", "//app:*", "//app/...:tests", "AppTests", "//app:bad\nlabel"])
    func rejects_patterns_that_could_exclude_healthy_targets(target: String) {
        #expect(throws: BazelTestCommandServiceError.invalidTarget(target)) {
            try BazelTestCommandService.excluding([target], from: ["//..."])
        }
    }

    @Test func rejects_target_files_that_override_exclusions() {
        #expect(throws: BazelTestCommandServiceError.targetPatternFile) {
            try BazelTestCommandService.excluding(["//app:tests"], from: ["--target_pattern_file=targets.txt"])
        }
    }

    @Test(.withMockedEnvironment(), .withMockedDependencies(), .withMockedNoora, arguments: [0, 4])
    func loads_all_pages_and_deduplicates_targets_without_weakening_the_policy(exitStatus: Int) async throws {
        let configLoader = MockConfigLoading()
        let serverEnvironment = MockServerEnvironmentServicing()
        let cases = MockListTestCasesServicing()
        let runner = MockCommandRunner()
        let serverURL = URL(string: "https://tuist.example.com")!
        given(configLoader).loadConfig(path: .any).willReturn(Tuist.test(fullHandle: "org/project", url: serverURL))
        given(serverEnvironment).url(configServerURL: .any).willReturn(serverURL)
        for (page, targets) in [(1, ["//app:tests", "//app:tests"]), (2, ["//deleted:tests", "//other:tests"])] {
            given(cases).listTestCases(
                fullHandle: .value("org/project"), serverURL: .value(serverURL), flaky: .value(nil),
                quarantined: .value(true), state: .value(nil), page: .value(page), pageSize: .value(500)
            ).willReturn(.init(
                pagination_metadata: .init(
                    current_page: page, has_next_page: page == 1, has_previous_page: page == 2,
                    page_size: 500, total_count: 4, total_pages: 2
                ),
                test_cases: targets.map { target in
                    .init(
                        avg_duration: 0, id: UUID().uuidString, is_flaky: true, is_quarantined: true,
                        module: .init(id: UUID().uuidString, name: target), name: "test", state: "skipped", url: ""
                    )
                }
            ))
        }
        let command = [
            "/usr/bin/env", "bazel", "test", "//...", "--expand_test_suites", "--target_pattern_file=", "--",
            "-//app:tests", "-//deleted:tests", "-//other:tests",
        ]
        runner.defaultCaptureStubs = (stderror: nil, stdout: nil, exitstatus: exitStatus)
        let service = BazelTestCommandService(
            configLoader: configLoader, serverEnvironmentService: serverEnvironment,
            listTestCasesService: cases, commandRunner: runner
        )
        do {
            try await service.run(directory: nil, bazel: "bazel", arguments: ["//..."], quarantine: true)
            #expect(exitStatus == 0)
        } catch let error as CommandError {
            guard case .terminated(4, _, _) = error, exitStatus == 4 else { throw error }
        }
        let recorded = try #require(runner.calls.first).split(separator: " ").map(String.init)
        #expect(recorded.filter {
            !$0.hasPrefix("--build_event_json_file=") && $0 != "--nobuild_event_json_file_path_conversion"
        } == command)
        #expect(runner.calls.count == 1)
        let output = ui()
        #expect(output.contains("Skipping 3 Bazel target(s)"))
        #expect(output.contains("  //app:tests\n  //deleted:tests\n  //other:tests"))
    }

    @Test(.withMockedEnvironment()) func disabling_quarantine_does_not_contact_server() async throws {
        let runner = MockCommandRunner()
        let command = ["/usr/bin/env", "bazelisk", "test", "//...", "--test_arg=hello world"]
        runner.succeedCommand(command)
        try await BazelTestCommandService(
            configLoader: MockConfigLoading(), listTestCasesService: MockListTestCasesServicing(), commandRunner: runner
        ).run(directory: nil, bazel: "bazelisk", arguments: ["//...", "--test_arg=hello world"], quarantine: false)
        #expect(runner.calls == [command.joined(separator: " ")])
    }
}
