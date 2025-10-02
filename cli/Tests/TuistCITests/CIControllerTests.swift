import Foundation
import Testing
import TuistSupport
import TuistTesting

@testable import TuistCI

struct CIControllerTests {
    private var subject: CIController

    init() {
        subject = CIController()
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_github_info() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_RUN_ID": "123456789",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .github,
            runId: "123456789",
            projectHandle: "owner/repo",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_gitlab_info_with_default_host() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITLAB_CI": "true",
            "CI_PROJECT_PATH": "namespace/project",
            "CI_PIPELINE_ID": "987654321",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .gitlab,
            runId: "987654321",
            projectHandle: "namespace/project",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_gitlab_info_with_custom_host() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITLAB_CI": "true",
            "CI_PROJECT_PATH": "namespace/project",
            "CI_PIPELINE_ID": "987654321",
            "CI_SERVER_HOST": "gitlab.example.com",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .gitlab,
            runId: "987654321",
            projectHandle: "namespace/project",
            host: "gitlab.example.com"
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_bitrise_info() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BITRISE_IO": "true",
            "BITRISE_APP_SLUG": "app-slug-123",
            "BITRISE_BUILD_SLUG": "build-slug-456",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .bitrise,
            runId: "build-slug-456",
            projectHandle: "app-slug-123",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_circleci_info() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "CIRCLECI": "true",
            "CIRCLE_PROJECT_USERNAME": "owner",
            "CIRCLE_PROJECT_REPONAME": "repo",
            "CIRCLE_BUILD_NUM": "42",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .circleci,
            runId: "42",
            projectHandle: "owner/repo",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_buildkite_info() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "BUILDKITE": "true",
            "BUILDKITE_ORGANIZATION_SLUG": "org",
            "BUILDKITE_PIPELINE_SLUG": "pipeline",
            "BUILDKITE_BUILD_NUMBER": "1234",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .buildkite,
            runId: "1234",
            projectHandle: "org/pipeline",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_codemagic_info() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "CM_BUILD_ID": "build-id-123",
            "CM_PROJECT_ID": "project-id-456",
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .codemagic,
            runId: "build-id-123",
            projectHandle: "project-id-456",
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_nil_when_no_ci_detected() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [:]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == nil)
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_github_info_with_missing_repository() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_RUN_ID": "123456789",
            // Missing GITHUB_REPOSITORY
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .github,
            runId: "123456789",
            projectHandle: nil,
            host: nil
        ))
    }

    @Test(.withMockedEnvironment()) func ciInfo_returns_github_info_with_missing_run_id() throws {
        // Given
        let environment = try #require(Environment.mocked)
        environment.variables = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_REPOSITORY": "owner/repo",
            // Missing GITHUB_RUN_ID
        ]

        // When
        let ciInfo = subject.ciInfo()

        // Then
        #expect(ciInfo == CIInfo(
            provider: .github,
            runId: nil,
            projectHandle: "owner/repo",
            host: nil
        ))
    }
}
