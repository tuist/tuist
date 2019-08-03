import Foundation
import TuistCore

protocol TuistConfigLinting {
    /// Lints a given Tuist configuration.
    ///
    /// - Parameter config: Tuist configuration to be linted against the system.
    /// - Throws: An error if the validation fails.
    func lint(config: TuistConfig) throws
}

class TuistConfigLinter: TuistConfigLinting {
    /// Instance to run system commands.
    let system: Systeming

    /// Instance to output messages to the user.
    let printer: Printing

    /// Initializes the linter.
    ///
    /// - Parameters
    ///   - system: Instance to run system commands.
    ///   - printer: Instance to output messages to the user.
    init(system: Systeming = System(),
         printer: Printing = Printer()) {
        self.system = system
        self.printer = printer
    }

    /// Lints a given Tuist configuration.
    ///
    /// - Parameter config: Tuist configuration to be linted against the system.
    /// - Throws: An error if the validation fails.
    func lint(config: TuistConfig) throws {
        var issues = [LintingIssue]()

        issues.append(contentsOf: lintXcodeVersion(config: config))

        try issues.printAndThrowIfNeeded(printer: printer)
    }

    func lintXcodeVersion(config _: TuistConfig) -> [LintingIssue] {
        // TODO:
        return []
    }
}
