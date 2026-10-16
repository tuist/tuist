import Foundation

public enum PackageManifestEnvironment {
    public struct Configuration: Sendable {
        let usesAutomaticProviderDefaults: Bool
        let includedVariablePatterns: [String]
        let excludedVariablePatterns: [String]

        public init(
            usesAutomaticProviderDefaults: Bool = true,
            includedVariablePatterns: [String] = [],
            excludedVariablePatterns: [String] = []
        ) {
            self.usesAutomaticProviderDefaults = usesAutomaticProviderDefaults
            self.includedVariablePatterns = includedVariablePatterns
            self.excludedVariablePatterns = excludedVariablePatterns
        }
    }

    @TaskLocal public static var configuration = Configuration()

    public static func withConfiguration<T>(
        _ configuration: Configuration,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $configuration.withValue(configuration) {
            try await operation()
        }
    }

    static func filtered(_ variables: [String: String], forDependencyResolution: Bool = false) -> [String: String]? {
        let configuration = configuration
        let automaticPatterns = configuration
            .usesAutomaticProviderDefaults ? automaticExcludedVariablePatterns(in: variables) : []
        let excludedVariablePatterns = automaticPatterns + configuration.excludedVariablePatterns
        guard !excludedVariablePatterns.isEmpty else { return nil }

        return variables.filter { key, _ in
            (!matches(key: key, patterns: automaticPatterns) ||
                automaticallyRetained(key, forDependencyResolution: forDependencyResolution)) &&
                !matches(key: key, patterns: configuration.excludedVariablePatterns) ||
                matches(key: key, patterns: configuration.includedVariablePatterns)
        }
    }

    private static func automaticallyRetained(_ key: String, forDependencyResolution: Bool) -> Bool {
        if ["GITHUB_ACTIONS", "RUNNER_OS", "RUNNER_ARCH"].contains(key) { return true }
        guard forDependencyResolution else { return false }
        return [
            "SSH_AUTH_SOCK",
            "GITHUB_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_URL",
            "ACTIONS_RUNTIME_TOKEN",
            "ACTIONS_RUNTIME_URL",
            "ACTIONS_RESULTS_URL",
        ].contains(key)
    }

    private static func automaticExcludedVariablePatterns(in variables: [String: String]) -> [String] {
        var patterns = [
            "TUIST_CACHE_SIGNING_GRANT",
            "TUIST_RUNNER_POD_NAME",
            "TUIST_RUNNER_POD_UID",
        ].filter { variables[$0] != nil }

        if variables["GITLAB_CI"] == "true" {
            patterns += [
                "CI_CONCURRENT_ID",
                "CI_CONCURRENT_PROJECT_ID",
                "CI_JOB_ID",
                "CI_JOB_RETRY_COUNT",
                "CI_JOB_STARTED_AT",
                "CI_JOB_STARTED_AT_SLUG",
                "CI_JOB_STATUS",
                "CI_JOB_URL",
                "CI_PIPELINE_CREATED_AT",
                "CI_PIPELINE_ID",
                "CI_PIPELINE_IID",
                "CI_PIPELINE_URL",
                "CI_TRACEPARENT",
                "CI_TRACESTATE",
                "CI_UPSTREAM_JOB_ID",
                "CI_UPSTREAM_PIPELINE_ID",
            ]
        }

        if variables["GITHUB_ACTIONS"] == "true" {
            patterns += ["ACTIONS_*", "GITHUB_*", "RUNNER_*", "SSH_AUTH_SOCK"]
        }

        if variables["BITRISE_IO"] == "true" {
            patterns += [
                "BITRISE_BUILD_NUMBER",
                "BITRISE_BUILD_SLUG",
                "BITRISE_BUILD_TRIGGER_TIMESTAMP",
                "BITRISE_BUILD_URL",
                "BITRISE_DEPLOY_DIR",
                "BITRISE_TEST_DEPLOY_DIR",
                "BITRISE_TEST_RESULT_DIR",
                "BITRISEIO_PIPELINE_BUILD_URL",
                "BITRISEIO_PIPELINE_ID",
            ]
        }

        if variables["CM_BUILD_ID"] != nil {
            patterns += [
                "CM_ARTIFACT_LINKS",
                "CM_BUILD_ID",
                "CM_BUILD_OUTPUT_DIR",
                "CM_ENV",
                "CM_EXPORT_DIR",
            ]
        }

        return patterns
    }

    private static func matches(key: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            if pattern.hasSuffix("*") {
                let prefix = pattern.dropLast()
                return !prefix.isEmpty && key.hasPrefix(prefix)
            }
            return key == pattern
        }
    }
}
