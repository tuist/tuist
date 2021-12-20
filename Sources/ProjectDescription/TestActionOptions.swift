import Foundation

/// Options for the `TestAction` action
public struct TestActionOptions: Equatable, Codable {
    /// App Language.
    public let language: SchemeLanguage?

    /// Region.
    public let region: String?

    /// True to collect the test coverage results.
    public let coverage: Bool

    /// List of targets for which Xcode will collect the coverage results.
    public let codeCoverageTargets: [TargetReference]

    init(language: SchemeLanguage?,
         region: String?,
         coverage: Bool,
         codeCoverageTargets: [TargetReference])
    {
        self.language = language
        self.region = region
        self.coverage = coverage
        self.codeCoverageTargets = codeCoverageTargets
    }

    /// Initializes set of options for a test action.
    /// - Parameters:
    ///   - language: Language used for running the tests.
    ///   - region: Region used for running the tests.
    ///   - coverage: Whether test coverage should be collected.
    ///   - codeCoverageTargets: List of tests whose code coverage information should be collected.
    /// - Returns: Initialized set of options.
    public static func options(language: SchemeLanguage? = nil,
                               region: String? = nil,
                               coverage: Bool = false,
                               codeCoverageTargets: [TargetReference] = []) -> TestActionOptions
    {
        TestActionOptions(
            language: language,
            region: region,
            coverage: coverage,
            codeCoverageTargets: codeCoverageTargets
        )
    }
}
