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

    static func filtered(_ variables: [String: String]) -> [String: String]? {
        let configuration = configuration
        let automaticPatterns = configuration
            .usesAutomaticProviderDefaults ? automaticExcludedVariablePatterns(in: variables) : []
        let excludedVariablePatterns = automaticPatterns + configuration.excludedVariablePatterns
        guard !excludedVariablePatterns.isEmpty else { return nil }

        return variables.filter { key, _ in
            !matches(key: key, patterns: excludedVariablePatterns) ||
                matches(key: key, patterns: configuration.includedVariablePatterns)
        }
    }

    private static func automaticExcludedVariablePatterns(in variables: [String: String]) -> [String] {
        var patterns: [String] = []

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
            patterns += [
                "GITHUB_ACTION",
                "GITHUB_ARTIFACTS",
                "GITHUB_ARTIFACTS_LIST",
                "GITHUB_ENV",
                "GITHUB_OUTPUT",
                "GITHUB_PATH",
                "GITHUB_RUN_ATTEMPT",
                "GITHUB_RUN_ID",
                "GITHUB_RUN_NUMBER",
                "GITHUB_STEP_SUMMARY",
            ]
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
