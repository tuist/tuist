import Foundation

/// A locally-captured summary of a test run, used to render the GitHub Actions job summary
/// without waiting for the server to finish processing the uploaded result bundle.
public struct RunReportTestRun: Sendable, Equatable {
    public let scheme: String
    public let totalTests: Int
    public let skippedTests: Int
    public let failedTestNames: [String]
    public let ranTestModules: Int
    /// Test modules selective testing skipped. `nil` when selective testing didn't apply.
    public let skippedTestModules: Int?

    public init(
        scheme: String,
        totalTests: Int,
        skippedTests: Int,
        failedTestNames: [String],
        ranTestModules: Int,
        skippedTestModules: Int?
    ) {
        self.scheme = scheme
        self.totalTests = totalTests
        self.skippedTests = skippedTests
        self.failedTestNames = failedTestNames
        self.ranTestModules = ranTestModules
        self.skippedTestModules = skippedTestModules
    }

    public var ranTests: Int { max(0, totalTests - skippedTests) }
    public var succeeded: Bool { failedTestNames.isEmpty }
}

/// A locally-captured summary of a build run, used to render the GitHub Actions job summary
/// without waiting for the server to finish processing the uploaded activity log.
public struct RunReportBuildRun: Sendable, Equatable {
    public let scheme: String
    public let succeeded: Bool
    public let duration: TimeInterval

    public init(
        scheme: String,
        succeeded: Bool,
        duration: TimeInterval
    ) {
        self.scheme = scheme
        self.succeeded = succeeded
        self.duration = duration
    }
}
