/// The type `TestActionOptions` represents a set of options for a test action.
public struct TestActionOptions: Equatable, Codable, Sendable {
    /// Whether a test action gathers test coverage data.
    public enum CoverageMode: Equatable, Sendable {
        /// Follows `Tuist.swift`'s `coverage: .coverage(enabled:)` (and its `TUIST_COVERAGE_ENABLED` override): the
        /// scheme gathers coverage when it's on and doesn't when it's off.
        case inherit
        /// Gathers coverage regardless of `Tuist.swift`.
        case enabled
        /// Doesn't gather coverage regardless of `Tuist.swift`.
        case disabled
    }

    /// Language used to run the tests.
    public var language: SchemeLanguage?

    /// Region used to run the tests.
    public var region: String?

    /// Preferred screen capture format for UI tests results in Xcode 15+
    public var preferredScreenCaptureFormat: ScreenCaptureFormat?

    /// Whether the scheme gathers test coverage data.
    public var codeCoverage: CoverageMode

    /// Whether the scheme gathers test coverage data. It reads `false` for a scheme that inherits `Tuist.swift`'s
    /// coverage option, even when the option turns coverage on.
    @available(*, deprecated, message: "Use codeCoverage, which tells apart a scheme that inherits Tuist.swift's coverage.")
    public var coverage: Bool {
        get { codeCoverage == .enabled }
        set { codeCoverage = newValue ? .enabled : .disabled }
    }

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
            codeCoverage: coverage.map { $0 ? .enabled : .disabled } ?? .inherit,
            codeCoverageTargets: codeCoverageTargets
        )
    }
}

extension TestActionOptions {
    /// `codeCoverage` is encoded as the optional Boolean `coverage` key, absent when the scheme inherits, so the
    /// manifest JSON keeps the shape it had when `coverage` was a stored Boolean.
    private enum CodingKeys: String, CodingKey {
        case language, region, preferredScreenCaptureFormat, coverage, codeCoverageTargets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(SchemeLanguage.self, forKey: .language)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        preferredScreenCaptureFormat = try container.decodeIfPresent(
            ScreenCaptureFormat.self,
            forKey: .preferredScreenCaptureFormat
        )
        codeCoverage = try container.decodeIfPresent(Bool.self, forKey: .coverage).map { $0 ? .enabled : .disabled }
            ?? .inherit
        codeCoverageTargets = try container.decode([TargetReference].self, forKey: .codeCoverageTargets)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(region, forKey: .region)
        try container.encodeIfPresent(preferredScreenCaptureFormat, forKey: .preferredScreenCaptureFormat)
        switch codeCoverage {
        case .inherit: break
        case .enabled: try container.encode(true, forKey: .coverage)
        case .disabled: try container.encode(false, forKey: .coverage)
        }
        try container.encode(codeCoverageTargets, forKey: .codeCoverageTargets)
    }
}
