import Foundation

public enum PackageManifestEnvironment {
    @TaskLocal public static var excludedVariablePatterns: [String] = []

    public static func withExcludedVariables<T>(
        _ patterns: [String],
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $excludedVariablePatterns.withValue(patterns) {
            try await operation()
        }
    }

    static func filtered(_ variables: [String: String]) -> [String: String]? {
        let patterns = excludedVariablePatterns
        guard !patterns.isEmpty else { return nil }
        return variables.filter { key, _ in
            !matches(key: key, patterns: patterns)
        }
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
