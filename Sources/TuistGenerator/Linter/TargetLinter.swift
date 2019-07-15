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
        issues.append(contentsOf: lintProductName(target: target))
        issues.append(contentsOf: lintBundleIdentifier(target: target))
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintCopiedFiles(target: target))
        issues.append(contentsOf: lintLibraryHasNoResources(target: target))
        issues.append(contentsOf: settingsLinter.lint(target: target))

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
    private func lintBundleIdentifier(target: Target) -> [LintingIssue] {
        var bundleIdentifier = target.bundleId

        // Remove any interpolated variables
        bundleIdentifier = bundleIdentifier.replacingOccurrences(of: "\\$\\{.+\\}", with: "", options: .regularExpression)
        bundleIdentifier = bundleIdentifier.replacingOccurrences(of: "\\$\\(.+\\)", with: "", options: .regularExpression)

        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.formUnion(CharacterSet(charactersIn: "-."))

        if !bundleIdentifier.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            let reason = "Invalid bundle identifier '\(bundleIdentifier)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."

            return [LintingIssue(reason: reason, severity: .error)]
        }
        return []
    }

    private func lintProductName(target: Target) -> [LintingIssue] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

        if target.productName.unicodeScalars.allSatisfy(allowed.contains) == false {
            let reason = "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9) and underscore (_) characters."

            return [LintingIssue(reason: reason, severity: .error)]
        }

        return []
    }

    private func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let supportsSources = target.supportsSources
        let sources = target.sources

        if supportsSources, sources.isEmpty {
            return [LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)]
        } else if !supportsSources, !sources.isEmpty {
            return [LintingIssue(reason: "Target \(target.name) cannot contain sources. \(target.platform) \(target.product) targets don't support source files", severity: .error)]
        }

        return []
    }

    private func lintCopiedFiles(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let files = target.resources.map(\.path)
        let infoPlists = files.filter { $0.pathString.contains("Info.plist") }
        let entitlements = files.filter { $0.pathString.contains(".entitlements") }

        issues.append(contentsOf: infoPlists.map {
            let reason = "Info.plist at path \($0.pathString) being copied into the target \(target.name) product."
            return LintingIssue(reason: reason, severity: .warning)
        })
        issues.append(contentsOf: entitlements.map {
            let reason = "Entitlements file at path \($0.pathString) being copied into the target \(target.name) product."
            return LintingIssue(reason: reason, severity: .warning)
        })

        issues.append(contentsOf: lintInfoplistExists(target: target))
        issues.append(contentsOf: lintEntitlementsExist(target: target))
        return issues
    }

    private func lintInfoplistExists(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let infoPlist = target.infoPlist, let path = infoPlist.path, !fileHandler.exists(path) {
            issues.append(LintingIssue(reason: "Info.plist file not found at path \(infoPlist.path!.pathString)", severity: .error))
        }
        return issues
    }

    private func lintEntitlementsExist(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let path = target.entitlements, !fileHandler.exists(path) {
            issues.append(LintingIssue(reason: "Entitlements file not found at path \(path.pathString)", severity: .error))
        }
        return issues
    }

    private func lintLibraryHasNoResources(target: Target) -> [LintingIssue] {
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
