import ArgumentParser
import FileSystem
import FileSystemTesting
import Mockable
import Path
import Testing
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGit
import TuistJobSummary
import TuistProcess
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct TrackableCommandProjectPathTests {
    @Test(.withMockedEnvironment(), .inTemporaryDirectory, arguments: [false, true], [false, true])
    func analytics_uses_the_parsed_project_path_even_when_raw_arguments_disagree(
        shouldFail: Bool,
        analyticsRequired: Bool
    ) async throws {
        let sessionDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = sessionDirectory.appending(component: "app")
        let gitController = MockGitControlling()
        let uploadAnalyticsService = MockUploadAnalyticsServicing()
        let jobSummaryService = MockGitHubActionsJobSummaryServicing()
        let backgroundProcessRunner = MockBackgroundProcessRunning()
        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)
        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())
        given(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .willReturn(.test())
        given(jobSummaryService)
            .writeJobSummary(testRunReports: .any, buildRunReports: .any, runURL: .any)
            .willReturn()
        let subject = TrackableCommand(
            command: ProjectCommand(path: projectPath.pathString, shouldFail: shouldFail, analyticsRequired: analyticsRequired),
            commandArguments: ["generate", "--path", "/wrong-directory"],
            commandEventFactory: CommandEventFactory(gitController: gitController),
            backgroundProcessRunner: backgroundProcessRunner,
            uploadAnalyticsService: uploadAnalyticsService,
            gitHubActionsJobSummaryService: jobSummaryService,
            sessionDirectory: sessionDirectory
        )

        do {
            try await subject.run(fullHandle: "tuist/app", serverURL: .test(), shouldTrackAnalytics: true)
            #expect(!shouldFail)
        } catch {
            #expect(shouldFail)
            #expect(error is ProjectCommand.Failure)
        }

        verify(gitController)
            .gitInfo(workingDirectory: .value(projectPath))
            .called(1)
        verify(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .value("tuist/app"), serverURL: .any, sessionDirectory: .any)
            .called(analyticsRequired ? 1 : 0)
        verify(backgroundProcessRunner)
            .runInBackground(
                .matching { arguments in
                    guard let command = try? AnalyticsUploadCommand.parse(Array(arguments.dropFirst(2))) else { return false }
                    return command.projectPath == projectPath.pathString && command.sessionDirectory == sessionDirectory
                        .pathString
                },
                environment: .any
            )
            .called(analyticsRequired ? 0 : 1)
    }
}

private struct ProjectCommand: ParsableCommand, ProjectPathProviding, TrackableParsableCommand {
    enum Failure: Error {
        case failed
    }

    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "generate")
    }

    var path: String?
    var shouldFail: Bool = false
    var analyticsRequired: Bool = true

    func run() throws {
        if shouldFail { throw Failure.failed }
    }
}
