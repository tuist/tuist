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

@testable import TuistCoverageCommand

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
    func requiresAFullHandle() async throws {
        try await givenProject(fullHandle: nil)
        given(configLoader).loadCargoConfig(path: .any).willReturn(Tuist.test(fullHandle: nil))

        await #expect(throws: CoverageReadCommandServiceError.missingFullHandle) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1", json: false)
        }
    }

    @Test(.withMockedEnvironment())
    func readsACargoWorkspacesProjectAndServerFromItsManifest() async throws {
        try await givenProject(fullHandle: nil)
        let cargoURL = try #require(URL(string: "https://tuist.example.com"))
        let cargoConfig = Tuist.test(fullHandle: "acme/rust", url: cargoURL)
        let directoryPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        given(configLoader).loadCargoConfig(path: .value(directoryPath)).willReturn(cargoConfig)
        given(serverEnvironmentService).url(configServerURL: .value(cargoURL)).willReturn(cargoURL)
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.pending)

        try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)

        verify(completeCommitCoverageService)
            .completeCommitCoverage(
                fullHandle: .value("acme/rust"),
                serverURL: .value(cargoURL),
                gitCommitSHA: .value("abcdef1234567")
            )
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func requiresACommitWhenTheCheckoutHasNone() async throws {
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
        #expect(success.message.plain() == "Coverage of commit abcdef1 is complete: 82.5% over App, Core.")
        #expect(
            success.takeaways.map { $0.plain() } == [
                "See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef1234567",
            ]
        )
    }

    @Test(.withMockedEnvironment())
    func saysWhenTheFigureIsIncomplete() async throws {
        try await givenProject()
        // No gap reasons, as servers deployed before them report.
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

    @Test(.withMockedEnvironment())
    func explainsThatDirtyRunsDontCountInsteadOfTheGenericGap() async throws {
        try await givenProject()
        let dirty = CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 0,
            coveredLines: 0,
            executableLines: 0,
            schemes: ["App"],
            partialSchemes: ["App"],
            complete: true,
            incomplete: true,
            gapReasons: ["dirty_run_excluded"]
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.complete(dirty))
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(
            success.message.plain() ==
                "Coverage of commit abcdef1 is complete: 0.0% over App (partial: App). Some runs came from a checkout with uncommitted changes and don't count, because they measured code that isn't the commit's, so the actual coverage may be higher."
        )
        #expect(success.takeaways.map { $0.plain() } == [
            "Keep the checkout clean while the tests run, or keep the files the CI job writes out of it",
            "See which runs count with 'tuist coverage runs --commit abcdef1234567'",
            "See the commit's coverage at https://tuist.dev/acme/app/tests/coverage/commits/abcdef1234567",
        ])
    }

    @Test(.withMockedEnvironment())
    func keepsTheGenericGapForAReasonItDoesNotKnow() async throws {
        try await givenProject()
        let incomplete = CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 42.0,
            coveredLines: 61800,
            executableLines: 147_122,
            schemes: ["App"],
            partialSchemes: ["App"],
            complete: true,
            incomplete: true,
            gapReasons: ["some_future_reason"]
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.complete(incomplete))
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(success.message.plain().hasSuffix("The figure is incomplete, so the actual coverage may be higher."))
        #expect(success.takeaways.count == 1)
    }

    @Test(.withMockedEnvironment())
    func leavesOutTheSchemesOfABuildSystemWithoutThem() async throws {
        try await givenProject()
        let schemeless = CommitCoverage(
            gitCommitSHA: "abcdef1234567",
            coverage: 80.3,
            coveredLines: 50913,
            executableLines: 63385,
            schemes: [""],
            partialSchemes: [""],
            complete: true,
            incomplete: true
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.complete(schemeless))
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(
            success.message.plain() ==
                "Coverage of commit abcdef1 is complete: 80.3%. The figure is incomplete, so the actual coverage may be higher."
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsTheCompleteCoverageAsJSON() async throws {
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
        #expect(output.contains("\"gap_reasons\":[]"))
        verify(gitController).gitInfo(workingDirectory: .any).called(0)
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsTheGapReasonsAsJSON() async throws {
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willReturn(.complete(CommitCoverage(
                gitCommitSHA: "abcdef1234567",
                coverage: 0,
                coveredLines: 0,
                executableLines: 0,
                schemes: ["App"],
                partialSchemes: ["App"],
                complete: true,
                incomplete: true,
                gapReasons: ["dirty_run_excluded"]
            )))

        try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: true)

        let output = ui().filter { !$0.isWhitespace }
        #expect(output.contains("\"gap_reasons\":[\"dirty_run_excluded\"]"))
        #expect(output.contains("\"incomplete\":true"))
    }

    @Test(.withMockedEnvironment())
    func saysTheSignalIsKeptWhenNoRunReportedCoverageYet() async throws {
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

    @Test(.withMockedEnvironment())
    func namesTheCheckoutsCommitAndHowToSignalAnotherWhenNoRunReportedCoverageYet() async throws {
        try await givenProject()
        given(gitController).gitInfo(workingDirectory: .any).willReturn(
            GitInfo(ref: "refs/pull/42/merge", branch: "feature", sha: "abcdef1234567", remoteURLOrigin: nil)
        )
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .value("abcdef1234567"))
            .willReturn(.pending)
        let alertController = AlertController()

        try await AlertController.$current.withValue(alertController) {
            try await subject.run(path: nil, fullHandle: nil, commit: nil, json: false)
        }

        let success = try #require(alertController.success().last)
        #expect(success.message.plain().contains("No run of commit abcdef1, the checkout's HEAD, has reported coverage yet"))
        #expect(success.takeaways.map { $0.plain() }.contains { $0.contains("tuist coverage complete --commit <sha>") })
        #expect(
            success.takeaways.map { $0.plain() }
                .contains("See the commits your runs reported coverage for at https://tuist.dev/acme/app/tests/coverage/commits")
        )
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func printsAPendingSignalAsJSON() async throws {
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
        try await givenProject()
        given(completeCommitCoverageService)
            .completeCommitCoverage(fullHandle: .any, serverURL: .any, gitCommitSHA: .any)
            .willThrow(NSError(domain: "server", code: 403))

        await #expect(throws: NSError.self) {
            try await subject.run(path: nil, fullHandle: nil, commit: "abcdef1234567", json: false)
        }
    }
}
