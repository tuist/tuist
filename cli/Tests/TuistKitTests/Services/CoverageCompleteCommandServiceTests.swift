import Foundation
import Mockable
import Testing
import TuistAlert
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGit
import TuistNooraTesting
import TuistServer
import TuistTesting

@testable import TuistKit

struct CoverageCompleteCommandServiceTests {
    private let completeCommitCoverageService = MockCompleteCommitCoverageServicing()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let gitController = MockGitControlling()
    private let subject: CoverageCompleteCommandService
    private let serverURL = URL(string: "https://tuist.dev")!

    init() {
        subject = CoverageCompleteCommandService(
            completeCommitCoverageService: completeCommitCoverageService,
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            gitController: gitController
        )
    }

    private func givenProject(fullHandle: String? = "acme/app") async throws {
        let config = Tuist.test(fullHandle: fullHandle)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadConfig(path: .value(directoryPath)).willReturn(config)
        given(serverEnvironmentService).url(configServerURL: .value(config.url)).willReturn(serverURL)
    }

    private let coverage = CommitCoverage(
        gitCommitSHA: "abcdef1234567",
        coverage: 82.5,
        coveredLines: 165,
        executableLines: 200,
        schemes: ["App", "Core"],
        partialSchemes: ["Core"],
        complete: true
    )

    @Test(.withMockedEnvironment())
    func refusesWithoutTheCoverageFlag() async throws {
        await #expect(throws: CoverageCompleteCommandServiceError.earlyAccess) {
            try await subject.run(path: nil, fullHandle: "acme/app", commit: "abcdef1", json: false)
        }
    }

    @Test(.withMockedEnvironment())
    func requiresAFullHandle() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject(fullHandle: nil)

        await #expect(throws: CoverageCompleteCommandServiceError.missingFullHandle) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1", json: false)
        }
    }

    @Test(.withMockedEnvironment())
    func requiresACommitWhenTheCheckoutHasNone() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(gitController).gitInfo(workingDirectory: .any).willThrow(NSError(domain: "git", code: 128))

        await #expect(throws: CoverageCompleteCommandServiceError.missingCommit) {
            try await subject.run(path: nil, fullHandle: nil, commit: nil, json: false)
        }
        verify(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func signalsTheCheckoutsCommitAndReportsTheCompleteCoverage() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(gitController).gitInfo(workingDirectory: .any).willReturn(
            GitInfo(ref: nil, branch: "main", sha: "abcdef1234567", remoteURLOrigin: nil)
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(
                fullHandle: .value("acme/app"),
                serverURL: .value(serverURL),
                gitCommitSHA: .value("abcdef1234567")
            )
            .willReturn(.complete(coverage))
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: nil, json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(success.message.plain() == "Coverage of commit abcdef1 is complete: 82.5% over App, Core (partial: Core).")
    }

    @Test(.withMockedEnvironment())
    func saysWhenTheFigureIsIncomplete() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        let incomplete = CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 42.0,
            coveredLines: 61800,
            executableLines: 147_122,
            schemes: ["App"],
            partialSchemes: ["App"],
            complete: true,
            incomplete: true
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.complete(incomplete))
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(
            success.message.plain() ==
                "Coverage of commit abcdef1 is complete: 42.0% over App (partial: App). The figure is incomplete, so the actual coverage may be higher."
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsTheCompleteCoverageAsJSON() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .value("other/app"), serverURL: .any, gitCommitSHA: .value("abcdef1234567"))
            .willReturn(.complete(coverage))

        try await subject.run(path: nil, fullHandle: "other/app", commit: "abcdef1234567", json: true)

        let output = ui().filter { !$0.isWhitespace }
        #expect(output.contains("\"git_commit_sha\":\"abcdef1234567\""))
        #expect(output.contains("\"covered_lines\":165"))
        #expect(output.contains("\"partial_schemes\":[\"Core\"]"))
        #expect(output.contains("\"complete\":true"))
        #expect(output.contains("\"incomplete\":false"))
        verify(gitController).gitInfo(workingDirectory: .any).called(0)
    }

    @Test(.withMockedEnvironment())
    func saysTheSignalIsKeptWhenNoRunReportedCoverageYet() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.pending)
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(success.message.plain().contains("No run of commit abcdef1 has reported coverage yet"))
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsAPendingSignalAsJSON() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.pending)

        try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: true)

        let output = ui().filter { !$0.isWhitespace }
        #expect(output.contains("\"pending\":true"))
        #expect(output.contains("\"complete\":false"))
    }

    @Test(.withMockedEnvironment())
    func passesTheServersErrorOn() async throws {
        Environment.mocked?.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willThrow(NSError(domain: "server", code: 403))

        await #expect(throws: NSError.self) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }
    }
}
