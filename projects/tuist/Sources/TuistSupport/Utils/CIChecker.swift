import Foundation

public protocol CIChecking: AnyObject {
    /// Returns true when the environment in which the tuist process is running is a CI environment.
    func isCI() -> Bool
}

public final class CIChecker: CIChecking {
    static let variables = [
        // GitHub: https://help.github.com/en/actions/automating-your-workflow-with-github-actions/using-environment-variables
        "GITHUB_RUN_ID",
        // CircleCI: https://circleci.com/docs/2.0/env-vars/
        // Bitrise: https://devcenter.bitrise.io/builds/available-environment-variables/
        // Buildkite: https://buildkite.com/docs/pipelines/environment-variables
        // Travis: https://docs.travis-ci.com/user/environment-variables/
        "CI",
        // Jenkins: https://wiki.jenkins.io/display/JENKINS/Building+a+software+project
        "BUILD_NUMBER",
    ]

    /// Default initializer
    public init() {}

    // MARK: - CIChecking

    public func isCI() -> Bool {
        isCI(environment: ProcessInfo.processInfo.environment)
    }

    // MARK: - Internal

    func isCI(environment: [String: String]) -> Bool {
        environment.first(where: {
            CIChecker.variables.contains($0.key) && Constants.trueValues.contains($0.value)
        }) != nil
    }
}
