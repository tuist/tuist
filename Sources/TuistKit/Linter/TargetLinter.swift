import Foundation
import TuistCore

protocol TargetLinting: AnyObject {
    func lint(target: Target) -> [LintingIssue]
}

class TargetLinter: TargetLinting {
    // MARK: - Attributes

    private let fileHandler: FileHandling
    private let settingsLinter: SettingsLinting
    private let targetActionLinter: TargetActionLinting

    // MARK: - Init

    init(settingsLinter: SettingsLinting = SettingsLinter(),
         fileHandler: FileHandling = FileHandler(),
         targetActionLinter: TargetActionLinting = TargetActionLinter()) {
        self.settingsLinter = settingsLinter
        self.fileHandler = fileHandler
        self.targetActionLinter = targetActionLinter
    }

    // MARK: - TargetLinting

    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintBundleIdentifier(target: target))
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintCopiedFiles(target: target))
        issues.append(contentsOf: lintLibraryHasNoResources(target: target))

        if let settings = target.settings {
            issues.append(contentsOf: settingsLinter.lint(settings: settings))
        }
        target.actions.forEach { action in
            issues.append(contentsOf: targetActionLinter.lint(action))
        }
        return issues
    }

    // MARK: - Fileprivate

    /// Verifies that the bundle identifier doesn't include characters that are not supported.
    ///
    /// - Parameter target: Target whose bundle identified will be linted.
    /// - Returns: An array with a linting issue if the bundle identifier contains invalid characters.
    fileprivate func lintBundleIdentifier(target: Target) -> [LintingIssue] {
        let bundleIdentifier = target.bundleId

        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.formUnion(CharacterSet(charactersIn: "-."))

        if !bundleIdentifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            let reason = "Invalid bundle identifier '\(bundleIdentifier)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."

            return [LintingIssue(reason: reason, severity: .error)]
        }
        return []
    }

    fileprivate func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let files = target.sources
        var issues: [LintingIssue] = []
        if files.isEmpty {
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

        issues.append(contentsOf: lintInfoplistExists(target: target))
        issues.append(contentsOf: lintEntitlementsExist(target: target))
        return issues
    }

    fileprivate func lintInfoplistExists(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if !fileHandler.exists(target.infoPlist) {
            issues.append(LintingIssue(reason: "Info.plist file not found at path \(target.infoPlist.asString)", severity: .error))
        }
        return issues
    }

    fileprivate func lintEntitlementsExist(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let path = target.entitlements, !fileHandler.exists(path) {
            issues.append(LintingIssue(reason: "Entitlements file not found at path \(path.asString)", severity: .error))
        }
        return issues
    }

    fileprivate func lintLibraryHasNoResources(target: Target) -> [LintingIssue] {
        let productsNotAllowingResources: [Product] = [
            .dynamicLibrary,
            .staticLibrary,
            .staticFramework,
        ]

        if productsNotAllowingResources.contains(target.product) == false {
            return []
        }

        if target.resources.isEmpty == false {
            return [LintingIssue(reason: "Target \(target.name) cannot contain resources. Libraries don't support resources", severity: .error)]
        }

        return []
    }
}
