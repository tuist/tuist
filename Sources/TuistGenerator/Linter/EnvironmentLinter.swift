import Foundation
import TuistCore

protocol EnvironmentLinting {
    /// Lints a given Tuist configuration.
    ///
    /// - Parameter config: Tuist configuration to be linted against the system.
    /// - Throws: An error if the validation fails.
    func lint(config: TuistConfig) throws
}

class EnvironmentLinter: EnvironmentLinting {
    /// Xcode controller.
    let xcodeController: XcodeControlling

    /// Printer to output messages to the user.
    let printer: Printing

    /// Initialies the linter.
    ///
    /// - Parameters:
    ///     - xcodeController: Xcode controller.
    ///     - printer: Printer to output messages to the user.
    init(xcodeController: XcodeControlling = XcodeController(),
         printer: Printing = Printer()) {
        self.xcodeController = xcodeController
        self.printer = printer
    }

    /// Lints a given Tuist configuration.
    ///
    /// - Parameter config: Tuist configuration to be linted against the system.
    /// - Throws: An error if the validation fails.
    func lint(config: TuistConfig) throws {
        var issues = [LintingIssue]()

        issues.append(contentsOf: try lintXcodeVersion(config: config))

        try issues.printAndThrowIfNeeded(printer: printer)
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

        guard let xcode = try xcodeController.selected() else {
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
