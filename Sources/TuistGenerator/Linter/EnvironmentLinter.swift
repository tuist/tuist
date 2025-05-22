import Foundation
import TuistCore
import TuistSupport

public protocol EnvironmentLinting {
    func lint(configGeneratedProjectOptions: TuistGeneratedProjectOptions) async throws -> [LintingIssue]
}

public class EnvironmentLinter: EnvironmentLinting {
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func lint(configGeneratedProjectOptions: TuistGeneratedProjectOptions) async throws -> [LintingIssue] {
        var issues = [LintingIssue]()

        issues.append(contentsOf: try await lintXcodeVersion(configGeneratedProjectOptions: configGeneratedProjectOptions))

        return issues
    }

    func lintXcodeVersion(configGeneratedProjectOptions: TuistGeneratedProjectOptions) async throws -> [LintingIssue] {
        let xcode = try await XcodeController.current.selected()

        let version = xcode.infoPlist.version

        if !configGeneratedProjectOptions.compatibleXcodeVersions.isCompatible(versionString: version) {
            let versions = configGeneratedProjectOptions.compatibleXcodeVersions
            let message =
                "The selected Xcode version is \(version), which is not compatible with this project's Xcode version requirement of \(versions)."
            return [LintingIssue(reason: message, severity: .error)]
        } else {
            return []
        }
    }
}
