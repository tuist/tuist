import Foundation
import Mockable

@Mockable
public protocol GitRefReading {
    /// - Returns: A git ref based on the CI environment value. Returns `nil` in non-CI environments.
    func read() -> String?
}

public final class GitRefReader: GitRefReading {
    public init() {}

    private static let pullRequestIDEnvironmentVariables = [
        // Codemagic
        "CM_PULL_REQUEST_NUMBER",
        // GitLab
        "CI_EXTERNAL_PULL_REQUEST_IID",
        // Bitrise
        "BITRISE_PULL_REQUEST",
        // AppCircle
        "AC_PULL_NUMBER",
        // Xcode Cloud
        "CI_PULL_REQUEST_NUMBER",
        // CircleCI
        "CIRCLE_PR_NUMBER",
        // Buildkite
        "BUILDKITE_PULL_REQUEST",
    ]

    public func read() -> String? {
        if let githubRef = ProcessInfo.processInfo.environment["GITHUB_REF"] {
            return githubRef
        } else if let pullRequestID = Self.pullRequestIDEnvironmentVariables
            .first(where: { ProcessInfo.processInfo.environment[$0]?.isEmpty == false })
        {
            // We're aligning the pull request ID with the PR GITHUB_REF environment variable
            return "refs/pull/\(pullRequestID)/merge"
        } else {
            return nil
        }
    }
}
