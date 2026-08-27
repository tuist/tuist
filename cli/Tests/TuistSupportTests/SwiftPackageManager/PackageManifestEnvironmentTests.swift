import Testing

@testable import TuistSupport

struct PackageManifestEnvironmentTests {
    @Test func automatic_defaults_exclude_volatile_gitlab_variables() async throws {
        let variables = [
            "CI_JOB_ID": "job-1",
            "CI_JOB_TOKEN": "token",
            "CI_PIPELINE_ID": "pipeline-1",
            "CI_COMMIT_REF_NAME": "main",
            "GITLAB_CI": "true",
        ]

        let filtered = try await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered(variables)
        }

        #expect(
            filtered == [
                "CI_COMMIT_REF_NAME": "main",
                "CI_JOB_TOKEN": "token",
                "GITLAB_CI": "true",
            ]
        )
    }

    @Test func automatic_defaults_can_restore_a_provider_variable() async throws {
        let variables = [
            "CI_JOB_ID": "job-1",
            "CI_PIPELINE_ID": "pipeline-1",
            "GITLAB_CI": "true",
        ]

        let filtered = try await PackageManifestEnvironment.withConfiguration(
            .init(includedVariablePatterns: ["CI_JOB_ID"])
        ) {
            PackageManifestEnvironment.filtered(variables)
        }

        #expect(filtered == ["CI_JOB_ID": "job-1", "GITLAB_CI": "true"])
    }

    @Test func all_environment_returns_no_filtered_environment() async throws {
        let filtered = try await PackageManifestEnvironment.withConfiguration(
            .init(usesAutomaticProviderDefaults: false)
        ) {
            PackageManifestEnvironment.filtered(["CI_JOB_ID": "job-1", "GITLAB_CI": "true"])
        }

        #expect(filtered == nil)
    }

    @Test func automatic_defaults_exclude_volatile_variables_for_each_supported_provider() async throws {
        let providers = [
            (
                ["GITHUB_ACTIONS": "true", "GITHUB_RUN_ID": "run", "GITHUB_REF": "refs/heads/main"],
                ["GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main"]
            ),
            (
                ["BITRISE_IO": "true", "BITRISE_BUILD_SLUG": "build", "BITRISE_GIT_BRANCH": "main"],
                ["BITRISE_IO": "true", "BITRISE_GIT_BRANCH": "main"]
            ),
            (
                ["CM_BUILD_ID": "build", "BUILD_NUMBER": "1", "CM_BRANCH": "main"],
                ["BUILD_NUMBER": "1", "CM_BRANCH": "main"]
            ),
        ]

        for (variables, expected) in providers {
            let filtered = try await PackageManifestEnvironment.withConfiguration(.init()) {
                PackageManifestEnvironment.filtered(variables)
            }

            #expect(filtered == expected)
        }
    }
}
