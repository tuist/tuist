import Foundation

/// The type `TestActionOptions` represents a set of options for a test action.
public struct TestActionOptions: Equatable, Codable {
    /// Language used to run the tests.
    public let language: SchemeLanguage?

    /// Region used to run the tests.
    public let region: String?

    /// Preferred screen capture format for UI tests results in Xcode 15+
    public let preferredScreenCaptureFormat: ScreenCaptureFormat?

    /// Whether the scheme should or not gather the test coverage data.
    public let coverage: Bool

    /// A list of targets you want to gather the test coverage data for them, which are defined in the project.
    public let codeCoverageTargets: [TargetReference]

    init(
        language: SchemeLanguage?,
        region: String?,
        preferredScreenCaptureFormat: ScreenCaptureFormat?,
        coverage: Bool,
        codeCoverageTargets: [TargetReference]
    ) {
        self.language = language
        self.region = region
        self.preferredScreenCaptureFormat = preferredScreenCaptureFormat
        self.coverage = coverage
        self.codeCoverageTargets = codeCoverageTargets
    }

    /// Returns a set of options for a test action.
    /// - Parameters:
    ///   - language: Language used for running the tests.
    ///   - region: Region used for running the tests.
    ///   - coverage: Whether test coverage should be collected.
    ///   - codeCoverageTargets: List of test targets whose code coverage information should be collected.
    /// - Returns: A set of options.
    public static func options(
        language: SchemeLanguage? = nil,
        region: String? = nil,
        preferredScreenCaptureFormat: ScreenCaptureFormat? = nil,
        coverage: Bool = false,
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
