import Testing

@testable import TuistSupport

struct PackageManifestEnvironmentTests {
    @Test func automatic_defaults_ignore_execution_identities_across_github_jobs() async {
        let packageInputs = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": "commit",
            "RUNNER_OS": "macOS",
            "RUNNER_ARCH": "ARM64",
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
            "SDKROOT": "/sdk",
            "SWIFT_EXEC": "/toolchain/swiftc",
            "TUIST_EE": "1",
            "SSH_AUTH_SOCK": "/agent.sock",
            "GITHUB_TOKEN": "git-credential",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "oidc-credential",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://issuer.example/token",
        ]
        let executionVariables = [
            "ACTIONS_ORCHESTRATION_ID", "GITHUB_RUN_ID", "GITHUB_STATE",
            "RUNNER_NAME", "RUNNER_TRACKING_ID", "TUIST_CACHE_SIGNING_GRANT",
            "TUIST_RUNNER_POD_NAME", "TUIST_RUNNER_POD_UID",
        ]

        for job in ["first", "second"] {
            let variables = packageInputs.merging(
                Dictionary(uniqueKeysWithValues: executionVariables.map { ($0, "\(job)-\($0)") }),
                uniquingKeysWith: { _, new in new }
            )
            let filtered = await PackageManifestEnvironment.withConfiguration(.init()) {
                PackageManifestEnvironment.filtered(variables)
            }
            #expect(filtered == packageInputs)
        }
    }

    @Test(arguments: [
        "GITHUB_REF",
        "GITHUB_SHA",
        "RUNNER_ARCH",
        "SSH_AUTH_SOCK",
        "GITHUB_TOKEN",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
        "ACTIONS_ID_TOKEN_REQUEST_URL"
    ])
    func automatic_defaults_preserve_changes_to_package_and_authentication_inputs(variable: String) async {
        let first = await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered(["GITHUB_ACTIONS": "true", variable: "first"])
        }
        let second = await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered(["GITHUB_ACTIONS": "true", variable: "second"])
        }
        #expect(first?[variable] == "first")
        #expect(second?[variable] == "second")
        #expect(first != second)
    }

    @Test func automatic_defaults_exclude_tuist_metadata_without_a_provider_marker() async {
        let filtered = await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered([
                "TUIST_CACHE_SIGNING_GRANT": "grant",
                "TUIST_RUNNER_POD_NAME": "pod",
                "TUIST_RUNNER_POD_UID": "uid",
                "TUIST_EE": "1",
                "SSH_AUTH_SOCK": "/agent.sock",
            ])
        }
        #expect(filtered == ["TUIST_EE": "1", "SSH_AUTH_SOCK": "/agent.sock"])
    }

    @Test func automatic_defaults_do_not_filter_unrecognized_local_environments() async {
        let filtered = await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered([
                "RUNNER_NAME": "local-name",
                "GITHUB_STATE": "/local/state",
                "SSH_AUTH_SOCK": "/agent.sock",
            ])
        }
        #expect(filtered == nil)
    }

    @Test func explicit_includes_restore_runner_and_tuist_metadata() async {
        let variables = [
            "GITHUB_ACTIONS": "true",
            "GITHUB_STATE": "/job/state",
            "RUNNER_NAME": "runner",
            "RUNNER_TRACKING_ID": "tracking",
            "TUIST_CACHE_SIGNING_GRANT": "grant",
        ]
        let filtered = await PackageManifestEnvironment.withConfiguration(
            .init(includedVariablePatterns: ["RUNNER_*", "TUIST_CACHE_SIGNING_GRANT"])
        ) {
            PackageManifestEnvironment.filtered(variables)
        }
        #expect(filtered == variables.filter { $0.key != "GITHUB_STATE" })
    }

    @Test func all_environment_preserves_runner_and_tuist_metadata() async {
        let filtered = await PackageManifestEnvironment.withConfiguration(.init(usesAutomaticProviderDefaults: false)) {
            PackageManifestEnvironment.filtered([
                "GITHUB_ACTIONS": "true",
                "RUNNER_NAME": "runner",
                "TUIST_CACHE_SIGNING_GRANT": "grant",
                "TUIST_RUNNER_POD_UID": "uid",
            ])
        }
        #expect(filtered == nil)
    }

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
