import Testing

@testable import TuistSupport

struct PackageManifestEnvironmentTests {
    @Test func automatic_defaults_stabilize_manifest_inputs_across_github_jobs_without_overrides() async {
        let packageInputs = [
            "GITHUB_ACTIONS": "true",
            "RUNNER_OS": "macOS",
            "RUNNER_ARCH": "ARM64",
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
            "SDKROOT": "/sdk",
            "SWIFT_EXEC": "/toolchain/swiftc",
            "TUIST_EE": "1",
        ]
        let executionVariables = [
            "ACTIONS_ORCHESTRATION_ID", "GITHUB_RUN_ID", "GITHUB_STATE",
            "RUNNER_NAME", "RUNNER_TRACKING_ID", "TUIST_CACHE_SIGNING_GRANT",
            "TUIST_RUNNER_POD_NAME", "TUIST_RUNNER_POD_UID",
            "GITHUB_REF", "GITHUB_HEAD_REF", "GITHUB_BASE_REF", "GITHUB_SHA", "GITHUB_WORKFLOW_SHA",
            "GITHUB_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_TOKEN", "ACTIONS_ID_TOKEN_REQUEST_URL",
            "ACTIONS_RUNTIME_TOKEN", "ACTIONS_RUNTIME_URL", "ACTIONS_RESULTS_URL", "SSH_AUTH_SOCK",
            "RUNNER_TEMP", "GITHUB_WORKSPACE", "GITHUB_EVENT_PATH",
            "MISE_GITHUB_TOKEN", "SHLVL", "_", "OLDPWD", "TUIST_CACHE_ENDPOINT", "TUIST_CACHE_MAX_BYTES",
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

    @Test(arguments: ["RUNNER_ARCH", "RUNNER_OS", "DEVELOPER_DIR", "SDKROOT", "SWIFT_EXEC", "TUIST_EE"])
    func automatic_defaults_preserve_changes_to_package_inputs(variable: String) async {
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

    @Test(arguments: ["GITHUB_REF", "GITHUB_SHA", "SSH_AUTH_SOCK", "GITHUB_TOKEN"])
    func explicit_includes_restore_inputs_and_their_invalidation(variable: String) async {
        await PackageManifestEnvironment.withConfiguration(.init(includedVariablePatterns: [variable])) {
            let first = PackageManifestEnvironment.filtered(["GITHUB_ACTIONS": "true", variable: "first"])
            let second = PackageManifestEnvironment.filtered(["GITHUB_ACTIONS": "true", variable: "second"])
            #expect(first?[variable] == "first")
            #expect(second?[variable] == "second")
            #expect(first != second)
        }
    }

    @Test func native_resolution_keeps_authentication_but_excludes_job_metadata() async {
        let credentials = [
            "SSH_AUTH_SOCK": "/agent.sock",
            "GITHUB_TOKEN": "git-token",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN": "oidc-token",
            "ACTIONS_ID_TOKEN_REQUEST_URL": "https://issuer.example/token",
            "ACTIONS_RUNTIME_TOKEN": "runtime-token",
            "ACTIONS_RUNTIME_URL": "https://runtime.example",
            "ACTIONS_RESULTS_URL": "https://results.example",
        ]
        let variables = credentials.merging([
            "GITHUB_ACTIONS": "true", "GITHUB_REF": "main", "GITHUB_SHA": "commit",
            "RUNNER_NAME": "runner", "TUIST_CACHE_SIGNING_GRANT": "grant", "MISE_GITHUB_TOKEN": "mise-token",
        ], uniquingKeysWith: { _, new in new })
        await PackageManifestEnvironment.withConfiguration(.init()) {
            #expect(PackageManifestEnvironment.filtered(variables) == ["GITHUB_ACTIONS": "true"])
            #expect(PackageManifestEnvironment.filtered(variables, forDependencyResolution: true)
                == credentials.merging(["GITHUB_ACTIONS": "true"], uniquingKeysWith: { _, new in new }))
        }
        await PackageManifestEnvironment.withConfiguration(.init(excludedVariablePatterns: ["GITHUB_TOKEN", "SSH_*"])) {
            let native = PackageManifestEnvironment.filtered(variables, forDependencyResolution: true)
            #expect(native?["GITHUB_TOKEN"] == nil)
            #expect(native?["SSH_AUTH_SOCK"] == nil)
            #expect(native?["ACTIONS_ID_TOKEN_REQUEST_TOKEN"] == "oidc-token")
        }
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

    @Test func automatic_defaults_exclude_shell_bookkeeping_and_tuist_cache_settings_without_a_provider_marker() async {
        let filtered = await PackageManifestEnvironment.withConfiguration(.init()) {
            PackageManifestEnvironment.filtered([
                "SHLVL": "5",
                "_": "/usr/local/bin/tuist",
                "OLDPWD": "/previous",
                "TUIST_CACHE_ENDPOINT": "http://cache.local",
                "TUIST_CACHE_MAX_BYTES": "12884901888",
                "TUIST_EE": "1",
                "PATH": "/usr/bin",
            ])
        }
        #expect(filtered == ["TUIST_EE": "1", "PATH": "/usr/bin"])
    }

    @Test func automatic_defaults_stabilize_manifest_inputs_across_local_sessions_and_worktrees() async {
        let packageInputs = [
            "HOME": "/Users/developer",
            "PATH": "/usr/bin",
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
            "TUIST_EE": "1",
        ]
        let sessionVariables = [
            "PWD", "OLDPWD", "SHLVL", "_", "TERM_SESSION_ID", "ITERM_SESSION_ID", "SECURITYSESSIONID",
            "TMUX_PANE", "XPC_SERVICE_NAME", "__MISE_ORIG_PATH", "__MISE_ZSH_PRECMD_RUN",
            "CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "CLAUDE_PID",
        ]

        for session in ["first", "second"] {
            let variables = packageInputs.merging(
                Dictionary(uniqueKeysWithValues: sessionVariables.map { ($0, "\(session)-\($0)") }),
                uniquingKeysWith: { _, new in new }
            )
            let filtered = await PackageManifestEnvironment.withConfiguration(.init()) {
                PackageManifestEnvironment.filtered(variables)
            }
            #expect(filtered == packageInputs)
        }
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
                ["GITHUB_ACTIONS": "true"]
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
