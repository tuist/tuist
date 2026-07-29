import Foundation

/// A locally-captured summary of a test run, used to render the GitHub Actions job summary
/// without waiting for the server to finish processing the uploaded result bundle.
public struct RunReportTestRun: Sendable, Equatable {
    public let scheme: String
    public let totalTests: Int
    public let skippedTests: Int
    public let failedTestNames: [String]

    public init(
        scheme: String,
        totalTests: Int,
        skippedTests: Int,
        failedTestNames: [String]
    ) {
        self.scheme = scheme
        self.totalTests = totalTests
        self.skippedTests = skippedTests
        self.failedTestNames = failedTestNames
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
