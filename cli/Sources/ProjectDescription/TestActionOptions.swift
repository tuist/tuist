/// The type `TestActionOptions` represents a set of options for a test action.
public struct TestActionOptions: Equatable, Codable, Sendable {
    /// Language used to run the tests.
    public var language: SchemeLanguage?

    /// Region used to run the tests.
    public var region: String?

    /// Preferred screen capture format for UI tests results in Xcode 15+
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?

    /// Whether the scheme gathers test coverage data. `nil` follows `Tuist.swift`'s
    /// `coverage: .coverage(enabled:)` (and its `TUIST_COVERAGE_ENABLED` override): the scheme gathers
    /// coverage when it's on and doesn't when it's off. Set `true` or `false` to decide for this scheme regardless.
    public var coverage: Bool?

    /// A list of targets you want to gather the test coverage data for them, which are defined in the project.
    public var codeCoverageTargets: [TargetReference]

    /// Returns a set of options for a test action.
    /// - Parameters:
    ///   - language: Language used for running the tests.
    ///   - region: Region used for running the tests.
    ///   - coverage: Whether test coverage should be collected. Leave it `nil` to follow `Tuist.swift`'s
    ///     `coverage: .coverage(enabled:)`.
    ///   - codeCoverageTargets: List of test targets whose code coverage information should be collected.
    /// - Returns: A set of options.
    public static func options(
        language: SchemeLanguage? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        coverage: Bool? = nil,
        codeCoverageTargets: [TargetReference] = []
    ) -> TestActionOptions {
        TestActionOptions(
            language: language,
            region: region,
            preferredScreenCaptureFormat: preferredScreenCaptureFormat,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets
        )
    }
}
