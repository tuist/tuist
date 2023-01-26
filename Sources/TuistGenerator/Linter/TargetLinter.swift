import Foundation
import TuistCore
import TuistGraph
import TuistSupport

protocol TargetLinting: AnyObject {
    func lint(target: Target) -> [LintingIssue]
}

class TargetLinter: TargetLinting {
    // MARK: - Attributes

    private let settingsLinter: SettingsLinting
    private let targetScriptLinter: TargetScriptLinting

    // MARK: - Init

    init(
        settingsLinter: SettingsLinting = SettingsLinter(),
        targetScriptLinter: TargetScriptLinting = TargetScriptLinter()
    ) {
        self.settingsLinter = settingsLinter
        self.targetScriptLinter = targetScriptLinter
    }

    // MARK: - TargetLinting

    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintProductName(target: target))
        issues.append(contentsOf: lintValidPlatformProductCombinations(target: target))
        issues.append(contentsOf: lintBundleIdentifier(target: target))
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintCopiedFiles(target: target))
        issues.append(contentsOf: lintLibraryHasNoResources(target: target))
        issues.append(contentsOf: lintDeploymentTarget(target: target))
        issues.append(contentsOf: settingsLinter.lint(target: target))
        issues.append(contentsOf: lintDuplicateDependency(target: target))
        issues.append(contentsOf: lintValidSourceFileCodeGenAttributes(target: target))
        issues.append(contentsOf: validateCoreDataModelsExist(target: target))
        issues.append(contentsOf: validateCoreDataModelVersionsExist(target: target))
        target.scripts.forEach { script in
            issues.append(contentsOf: targetScriptLinter.lint(script))
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
            let reason =
                "Invalid bundle identifier '\(bundleIdentifier)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."

            return [LintingIssue(reason: reason, severity: .error)]
        }
        return []
    }

    private func lintProductName(target: Target) -> [LintingIssue] {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")

        if target.product == .app {
            allowed.formUnion(CharacterSet(charactersIn: "."))
        }

        if target.productName.unicodeScalars.allSatisfy(allowed.contains) == false {
            let reason = target.product == .app ?
                "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), period (.), and underscore (_) characters." :
                "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), and underscore (_) characters."

            return [LintingIssue(reason: reason, severity: .warning)]
        }

        return []
    }

    private func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let supportsSources = target.supportsSources
        let sources = target.sources

        let hasNoSources = supportsSources && sources.isEmpty
        let hasNoDependencies = target.dependencies.isEmpty
        let hasNoScripts = target.scripts.isEmpty

        if hasNoSources, hasNoDependencies, hasNoScripts {
            return [LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)]
        } else if !supportsSources, !sources.isEmpty {
            return [LintingIssue(
                reason: "Target \(target.name) cannot contain sources. \(target.platform) \(target.product) targets don't support source files",
                severity: .error
            )]
        }

        return []
    }

    private func lintCopiedFiles(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let files = target.resources.map(\.path)
        let entitlements = files.filter { $0.pathString.contains(".entitlements") }

        if let targetInfoPlistPath = target.infoPlist?.path, files.contains(targetInfoPlistPath) {
            let reason = "Info.plist at path \(targetInfoPlistPath) being copied into the target \(target.name) product."
            issues.append(LintingIssue(reason: reason, severity: .warning))
        }

        issues.append(contentsOf: entitlements.map {
            let reason = "Entitlements file at path \($0.pathString) being copied into the target \(target.name) product."
            return LintingIssue(reason: reason, severity: .warning)
        })

        issues.append(contentsOf: lintInfoplistExists(target: target))
        issues.append(contentsOf: lintEntitlementsExist(target: target))
        return issues
    }

    private func validateCoreDataModelsExist(target: Target) -> [LintingIssue] {
        target.coreDataModels.map(\.path)
            .compactMap { path in
                if !FileHandler.shared.exists(path) {
                    let reason = "The Core Data model at path \(path.pathString) does not exist"
                    return LintingIssue(reason: reason, severity: .error)
                } else {
                    return nil
                }
            }
    }

    private func validateCoreDataModelVersionsExist(target: Target) -> [LintingIssue] {
        target.coreDataModels.compactMap { coreDataModel -> LintingIssue? in
            let versionFileName = "\(coreDataModel.currentVersion).xcdatamodel"
            let versionPath = coreDataModel.path.appending(component: versionFileName)

            if !FileHandler.shared.exists(versionPath) {
                let reason =
                    "The default version of the Core Data model at path \(coreDataModel.path.pathString), \(coreDataModel.currentVersion), does not exist. There should be a file at \(versionPath.pathString)"
                return LintingIssue(reason: reason, severity: .error)
            }
            return nil
        }
    }

    private func lintInfoplistExists(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let infoPlist = target.infoPlist,
           case let InfoPlist.file(path: path) = infoPlist,
           !FileHandler.shared.exists(path)
        {
            issues
                .append(LintingIssue(reason: "Info.plist file not found at path \(infoPlist.path!.pathString)", severity: .error))
        }
        return issues
    }

    private func lintEntitlementsExist(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let path = target.entitlements, !FileHandler.shared.exists(path) {
            issues.append(LintingIssue(reason: "Entitlements file not found at path \(path.pathString)", severity: .error))
        }
        return issues
    }

    private func lintLibraryHasNoResources(target: Target) -> [LintingIssue] {
        if target.supportsResources {
            return []
        }

        if target.resources.isEmpty == false {
            return [
                LintingIssue(
                    reason: "Target \(target.name) cannot contain resources. \(target.product) targets do not support resources",
                    severity: .error
                ),
            ]
        }

        return []
    }

    private func lintDeploymentTarget(target: Target) -> [LintingIssue] {
        guard let deploymentTarget = target.deploymentTarget else {
            return []
        }

        let versionFormatIssue = LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)

        let osVersionRegex = "\\b[0-9]+\\.[0-9]+(?:\\.[0-9]+)?\\b"
        if !deploymentTarget.version.matches(pattern: osVersionRegex) { return [versionFormatIssue] }

        let platform = target.platform
        let inconsistentPlatformIssue = LintingIssue(
            reason: "Found an inconsistency between a platform `\(platform.caseValue)` and deployment target `\(deploymentTarget.platform)`",
            severity: .error
        )

        switch deploymentTarget {
        case .iOS: if platform != .iOS { return [inconsistentPlatformIssue] }
        case .macOS: if platform != .macOS { return [inconsistentPlatformIssue] }
        case .watchOS: if platform != .watchOS { return [inconsistentPlatformIssue] }
        case .tvOS: if platform != .tvOS { return [inconsistentPlatformIssue] }
        }

        return []
    }

    private func lintValidPlatformProductCombinations(target: Target) -> [LintingIssue] {
        let invalidProductsForPlatforms: [Platform: [Product]] = [
            .iOS: [.watch2App, .watch2Extension, .tvTopShelfExtension],
        ]

        if let invalidProducts = invalidProductsForPlatforms[target.platform],
           invalidProducts.contains(target.product)
        {
            return [
                LintingIssue(
                    reason: "'\(target.name)' for platform '\(target.platform)' can't have a product type '\(target.product)'",
                    severity: .error
                ),
            ]
        }

        return []
    }

    private func lintDuplicateDependency(target: Target) -> [LintingIssue] {
        typealias Occurence = Int
        var seen: [TargetDependency: Occurence] = [:]
        target.dependencies.forEach { seen[$0, default: 0] += 1 }
        let duplicates = seen.enumerated().filter { $0.element.value > 1 }
        return duplicates.map {
            .init(
                reason: "Target '\(target.name)' has duplicate \($0.element.key.typeName) dependency specified: '\($0.element.key.name)'",
                severity: .warning
            )
        }
    }

    private func lintValidSourceFileCodeGenAttributes(target: Target) -> [LintingIssue] {
        let knownSupportedExtensions = [
            "intentdefinition",
            "mlmodel",
        ]
        let unsupportedSourceFileAttributes = target.sources.filter {
            $0.codeGen != nil && !knownSupportedExtensions.contains($0.path.extension ?? "")
        }

        return unsupportedSourceFileAttributes.map {
            .init(
                reason: "Target '\(target.name)' has a source file at path \($0.path) with unsupported `codeGen` attributes. Only \(knownSupportedExtensions.listed()) are known to support this.",
                severity: .warning
            )
        }
    }
}

extension TargetDependency {
    fileprivate var typeName: String {
        switch self {
        case .target:
            return "target"
        case .project:
            return "project"
        case .framework:
            return "framework"
        case .library:
            return "library"
        case .package:
            return "package"
        case .sdk:
            return "sdk"
        case .xcframework:
            return "xcframework"
        case .xctest:
            return "xctest"
        }
    }

    fileprivate var name: String {
        switch self {
        case let .target(name):
            return name
        case let .project(target, _):
            return target
        case let .framework(path):
            return path.basename
        case let .xcframework(path):
            return path.basename
        case let .library(path, _, _):
            return path.basename
        case let .package(product):
            return product
        case let .sdk(name, _):
            return name
        case .xctest:
            return "xctest"
        }
    }
}
