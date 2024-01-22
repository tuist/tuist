import Foundation

/// The type `TestActionOptions` represents a set of options for a test action.
public struct TestActionOptions: Equatable, Codable {
    /// Language used to run the tests.
    public var language: SchemeLanguage? = nil

    /// Region used to run the tests.
    public var region: String? = nil

    /// Preferred screen capture format for UI tests results in Xcode 15+
    public var preferredScreenCaptureFormat: ScreenCaptureFormat? = nil

    /// Whether the scheme should or not gather the test coverage data.
    public var coverage: Bool = false

    /// A list of targets you want to gather the test coverage data for them, which are defined in the project.
    public var codeCoverageTargets: [TargetReference] = []
}
