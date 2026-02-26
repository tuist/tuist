import Foundation
import XcodeGraph

/// A protocol defining methods for determining the variant of a build configuration
/// and validating configuration names.
protocol ConfigurationMatching {
    /// Returns the build configuration variant for a given configuration name.
    ///
    /// This method checks for keywords that identify known variants and defaults to `.debug` if none match.
    ///
    /// - Parameter name: The name of the build configuration.
    /// - Returns: The determined `BuildConfiguration.Variant` for the given name.
    func variant(for name: String) -> BuildConfiguration.Variant

    /// Validates that a configuration name is non-empty and contains no whitespace.
    ///
    /// - Parameter name: The configuration name to validate.
    /// - Returns: `true` if the name is valid; `false` otherwise.
    func validateConfigurationName(_ name: String) -> Bool
}

/// A concrete implementation of `ConfigurationMatching` that uses predefined keyword patterns
/// to determine configuration variants.
struct ConfigurationMatcher: ConfigurationMatching {
    /// Represents a pattern mapping a set of keywords to a configuration variant.
    struct Pattern {
        let keywords: Set<String>
        let variant: BuildConfiguration.Variant
    }

    /// Common patterns for identifying build configuration variants.
    let patterns: [Pattern]

    /// Initializes a new `ConfigurationMatcher` with default patterns.
    ///
    /// - Parameter patterns: An optional array of `Pattern` to override defaults.
    init(patterns: [Pattern]? = nil) {
        self.patterns = patterns ?? [
            Pattern(keywords: ["debug", "development", "dev"], variant: .debug),
            Pattern(keywords: ["release", "prod", "production"], variant: .release),
        ]
    }

    func variant(for name: String) -> BuildConfiguration.Variant {
        let lowercased = name.lowercased()
        return patterns.first { pattern in
            pattern.keywords.contains(where: { lowercased.contains($0) })
        }?.variant ?? .debug
    }

    func validateConfigurationName(_ name: String) -> Bool {
        !name.isEmpty && name.rangeOfCharacter(from: .whitespaces) == nil
    }
}
