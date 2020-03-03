import Foundation
import TuistCore
import TuistSupport

public protocol EnvironmentLinting {
    /// Lints a given Tuist configuration.
    ///
    /// - Parameter config: Tuist configuration to be linted against the system.
    /// - Returns: A list of linting issues.
    func lint(config: TuistConfig) throws -> [LintingIssue]
}

public class EnvironmentLinter: EnvironmentLinting {
    /// Default constructor.
    public init() {}

    public func lint(config: TuistConfig) throws -> [LintingIssue] {
        var issues = [LintingIssue]()

        issues.append(contentsOf: try lintXcodeVersion(config: config))

        return issues
    }

    /// Returns a linting issue if the selected version of Xcode is not compatible with the
    /// compatibility defined using the compatibleXcodeVersions attribute.
    ///
    /// - Parameter config: Tuist configuration.
    /// - Returns: An array with a linting issue if the selected version is not compatible.
    /// - Throws: An error if there's an error obtaining the selected Xcode version.
    func lintXcodeVersion(config: TuistConfig) throws -> [LintingIssue] {
        guard case let CompatibleXcodeVersions.list(compatibleVersions) = config.compatibleXcodeVersions else {
            return []
        }

        guard let xcode = try XcodeController.shared.selected() else {
            return []
        }

        let version = xcode.infoPlist.version

        if !compatibleVersions.contains(version) {
            let versions = compatibleVersions.joined(separator: ", ")
            let message = "The project, which only supports the versions of Xcode \(versions), is not compatible with your selected version of Xcode, \(version)"
            return [LintingIssue(reason: message, severity: .error)]
        } else {
            return []
        }
    }
}
