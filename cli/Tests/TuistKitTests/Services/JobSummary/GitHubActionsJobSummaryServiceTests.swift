import FileSystem
import Foundation
import Mockable
import Path
import Testing
import TuistCI
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer

@testable import TuistKit

struct GitHubActionsJobSummaryServiceTests {
    private let fileSystem = FileSystem()
    private let ciController = MockCIControlling()
    private let getRunJobSummaryService = MockGetRunJobSummaryServicing()
    private let subject: GitHubActionsJobSummaryService

    init() {
        subject = GitHubActionsJobSummaryService(
            fileSystem: fileSystem,
            ciController: ciController,
            getRunJobSummaryService: getRunJobSummaryService,
            maxAttempts: 1,
            retryDelay: 0
        )
    }

    @Test(.withMockedEnvironment())
    func writes_markdown_to_github_step_summary() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString
        given(getRunJobSummaryService)
            .getRunJobSummary(fullHandle: .any, gitRef: .any, serverURL: .any)
            .willReturn("### 🛠️ Tuist Run Report 🛠️\nbody")

        await subject.writeJobSummary(
            gitRef: "refs/heads/gh-readonly-queue/main/pr-1-abc",
            hasReport: true,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "### 🛠️ Tuist Run Report 🛠️\nbody\n")
    }

    @Test(.withMockedEnvironment())
    func appends_to_existing_summary_content() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_existing")
        try await fileSystem.writeText("previous\n", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString
        given(getRunJobSummaryService)
            .getRunJobSummary(fullHandle: .any, gitRef: .any, serverURL: .any)
            .willReturn("report")

        await subject.writeJobSummary(
            gitRef: "refs/heads/main",
            hasReport: true,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "previous\nreport\n")
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_not_github_actions() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_gitlab")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        // Not stubbing getRunJobSummaryService asserts it is never called for non-GitHub providers.
        given(ciController).ciInfo().willReturn(.test(provider: .gitlab))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            gitRef: "refs/heads/main",
            hasReport: true,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "")
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_command_produced_no_report() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_no_report")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString

        await subject.writeJobSummary(
            gitRef: "refs/heads/main",
            hasReport: false,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "")
    }

    @Test(.withMockedEnvironment())
    func does_not_write_when_there_is_nothing_to_report() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        let summaryPath = cwd.appending(component: "step_summary_empty_report")
        try await fileSystem.writeText("", at: summaryPath, encoding: .utf8)

        given(ciController).ciInfo().willReturn(.test(provider: .github))
        Environment.mocked?.variables["GITHUB_STEP_SUMMARY"] = summaryPath.pathString
        given(getRunJobSummaryService)
            .getRunJobSummary(fullHandle: .any, gitRef: .any, serverURL: .any)
            .willReturn(nil)

        await subject.writeJobSummary(
            gitRef: "refs/heads/main",
            hasReport: true,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!
        )

        let content = try await fileSystem.readTextFile(at: summaryPath)
        #expect(content == "")
    }
}
