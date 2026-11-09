import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistConstants
import TuistNooraTesting
import TuistOpener
import TuistServer

@testable import TuistProjectCommand

struct ProjectShowServiceTests {
    private let opener = MockOpening()
    private let configLoader = MockConfigLoading()
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let getProjectService = MockGetProjectServicing()
    private let subject: ProjectShowService

    init() {
        subject = ProjectShowService(
            opener: opener,
            configLoader: configLoader,
            serverEnvironmentService: serverEnvironmentService,
            getProjectService: getProjectService
        )

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(Constants.URLs.production)
    }

    @Test func run_with_web_when_theFullHandleIsProvided() async throws {
        // Given
        var expectedURLComponents = URLComponents(
            url: Constants.URLs.production, resolvingAgainstBaseURL: false
        )!
        expectedURLComponents.path = "/tuist/tuist"
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())

        // When
        try await subject.run(fullHandle: "tuist/tuist", web: true, path: nil)

        // Then
        verify(opener).open(url: .value(expectedURLComponents.url!)).called(1)
    }

    @Test(.inTemporaryDirectory) func run_with_web_when_theFullHandleIsNotProvided_and_aConfigWithFullHandleCanBeLoaded()
        async throws
    {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        var expectedURLComponents = URLComponents(
            url: Constants.URLs.production, resolvingAgainstBaseURL: false
        )!
        expectedURLComponents.path = "/tuist/tuist"
        let config = Tuist.test(fullHandle: "tuist/tuist")
        given(configLoader).loadConfig(path: .value(path)).willReturn(config)
        given(opener).open(url: .any).willReturn()

        // When
        try await subject.run(fullHandle: nil, web: true, path: path.pathString)

        // Then
        verify(opener).open(url: .value(expectedURLComponents.url!)).called(1)
    }

    @Test(.inTemporaryDirectory) func run_with_web_when_theFullHandleIsNotProvided_and_aConfigWithoutFullHandleCanBeLoaded()
        async throws
    {
        // Given
        let path = try #require(FileSystem.temporaryTestDirectory)
        var expectedURLComponents = URLComponents(
            url: Constants.URLs.production, resolvingAgainstBaseURL: false
        )!
        expectedURLComponents.path = "/tuist/tuist"
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()
        let config = Tuist.test(fullHandle: nil)
        given(configLoader).loadConfig(path: .value(path)).willReturn(config)

        // When/Then
        await #expect(throws: ProjectShowServiceError.missingFullHandle) {
            try await subject.run(fullHandle: nil, web: false, path: path.pathString)
        }
    }

    @Test(.withMockedNoora) func run_when_full_handle_is_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    fullName: "tuist/tuist",
                    defaultBranch: "main"
                )
            )

        // When
        try await subject.run(fullHandle: "tuist/tuist", web: false, path: nil)

        // Then
        #expect(
            logOutput().contains(
                """
                Full handle: tuist/tuist
                Default branch: main
                """
            )
        )
    }

    @Test(.withMockedNoora) func run_when_project_is_public() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    visibility: .public
                )
            )

        // When
        try await subject.run(fullHandle: "tuist/tuist", web: false, path: nil)

        // Then
        #expect(
            logOutput().contains(
                """
                Visibility: public
                """
            )
        )
    }

    @Test(.withMockedNoora) func run_when_project_is_private() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    visibility: .private
                )
            )

        // When
        try await subject.run(fullHandle: "tuist/tuist", web: false, path: nil)

        // Then
        #expect(
            logOutput().contains(
                """
                Visibility: private
                """
            )
        )
    }

    @Test(.withMockedNoora) func run_when_repositoryURL_is_defined() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    fullName: "tuist/tuist",
                    defaultBranch: "main",
                    repositoryURL: "https://github.com/tuist/tuist"
                )
            )

        // When
        try await subject.run(fullHandle: "tuist/tuist", web: false, path: nil)

        // Then
        #expect(
            logOutput().contains(
                """
                Full handle: tuist/tuist
                Repository: https://github.com/tuist/tuist
                Default branch: main
                """
            )
        )
    }

    @Test(.withMockedNoora) func run_when_full_handle_is_not_provided() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                .test(
                    fullHandle: "tuist/tuist"
                )
            )
        given(getProjectService)
            .getProject(
                fullHandle: .value("tuist/tuist"),
                serverURL: .any
            )
            .willReturn(
                .test(
                    fullName: "tuist/tuist",
                    defaultBranch: "main"
                )
            )

        // When
        try await subject.run(fullHandle: nil, web: false, path: nil)

        // Then
        #expect(
            logOutput().contains(
                """
                Full handle: tuist/tuist
                Default branch: main
                """
            )
        )
    }
}
