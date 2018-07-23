import Foundation
import TuistCore

protocol TargetLinting: AnyObject {
    func lint(target: Target) -> [LintingIssue]
}

class TargetLinter: TargetLinting {

    // MARK: - TargetLinting

    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintCopiedFiles(target: target))
        return issues
    }

    // MARK: - Fileprivate

    fileprivate func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let files = target.sources
        var issues: [LintingIssue] = []
        if files.count == 0 {
            issues.append(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning))
        }
        return issues
    }

    fileprivate func lintCopiedFiles(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let files = target.resources
        let infoPlists = files.filter({ $0.asString.contains("Info.plist") })
        let entitlements = files.filter({ $0.asString.contains(".entitlements") })

        issues.append(contentsOf: infoPlists.map({ LintingIssue(reason: "Info.plist at path \($0.asString) being copied into the target \(target.name) product.", severity: .warning) }))
        issues.append(contentsOf: entitlements.map({ LintingIssue(reason: "Entitlements file at path \($0.asString) being copied into the target \(target.name) product.", severity: .warning) }))

        return issues
    }
}
