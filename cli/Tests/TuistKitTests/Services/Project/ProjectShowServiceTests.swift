import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting
import XCTest

@testable import TuistKit

final class ProjectShowServiceTests: TuistUnitTestCase {
    private var opener: MockOpening!
    private var configLoader: MockConfigLoading!
    private var serverEnvironmentService: MockServerEnvironmentServicing!
    private var getProjectService: MockGetProjectServicing!
    private var subject: ProjectShowService!

    override func setUp() {
        super.setUp()
        opener = MockOpening()
        configLoader = MockConfigLoading()
        serverEnvironmentService = MockServerEnvironmentServicing()
        getProjectService = MockGetProjectServicing()
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

    override func tearDown() {
        opener = nil
        configLoader = nil
        serverEnvironmentService = nil
        getProjectService = nil
        subject = nil
        super.tearDown()
    }

    func test_run_with_web_when_theFullHandleIsProvided() async throws {
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

    func test_run_with_web_when_theFullHandleIsNotProvided_and_aConfigWithFullHandleCanBeLoaded()
        async throws
    {
        // Given
        let path = try temporaryPath()
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

    func test_run_with_web_when_theFullHandleIsNotProvided_and_aConfigWithoutFullHandleCanBeLoaded()
        async throws
    {
        // Given
        let path = try temporaryPath()
        var expectedURLComponents = URLComponents(
            url: Constants.URLs.production, resolvingAgainstBaseURL: false
        )!
        expectedURLComponents.path = "/tuist/tuist"
        given(opener).open(url: .value(expectedURLComponents.url!)).willReturn()
        let config = Tuist.test(fullHandle: nil)
        given(configLoader).loadConfig(path: .value(path)).willReturn(config)

        // When/Then
        await XCTAssertThrowsSpecific(
            {
                try await subject.run(fullHandle: nil, web: false, path: path.pathString)
            }, ProjectShowServiceError.missingFullHandle
        )
    }

    func test_run_when_full_handle_is_provided() async throws {
        try await withMockedDependencies {
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
            XCTAssertStandardOutput(
                pattern: """
                Full handle: tuist/tuist
                Default branch: main
                """
            )
        }
    }

    func test_run_when_project_is_public() async throws {
        try await withMockedDependencies {
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
            XCTAssertStandardOutput(
                pattern: """
                Visibility: public
                """
            )
        }
    }

    func test_run_when_project_is_private() async throws {
        try await withMockedDependencies {
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
            XCTAssertStandardOutput(
                pattern: """
                Visibility: private
                """
            )
        }
    }

    func test_run_when_repositoryURL_is_defined() async throws {
        try await withMockedDependencies {
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
            XCTAssertStandardOutput(
                pattern: """
                Full handle: tuist/tuist
                Repository: https://github.com/tuist/tuist
                Default branch: main
                """
            )
        }
    }

    func test_run_when_full_handle_is_not_provided() async throws {
        try await withMockedDependencies {
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
            XCTAssertStandardOutput(
                pattern: """
                Full handle: tuist/tuist
                Default branch: main
                """
            )
        }
    }
}
