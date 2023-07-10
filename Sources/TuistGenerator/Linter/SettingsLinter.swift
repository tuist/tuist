import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

protocol SettingsLinting: AnyObject {
    func lint(project: Project) -> [LintingIssue]
    func lint(target: Target) -> [LintingIssue]
}

final class SettingsLinter: SettingsLinting {
    // MARK: - SettingsLinting

    func lint(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintConfigFilesExist(settings: project.settings))
        issues.append(contentsOf: lintNonEmptyConfig(project: project))
        return issues
    }

    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let settings = target.settings {
            issues.append(contentsOf: lintConfigFilesExist(settings: settings))
        }

        if let deploymentTarget = target.deploymentTarget {
            issues.append(contentsOf: lint(platform: target.platform, isCompatibleWith: deploymentTarget))
        }
        return issues
    }

    // MARK: - Fileprivate

    private func lintConfigFilesExist(settings: Settings) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let lintPath: (AbsolutePath) -> Void = { path in
            if !FileHandler.shared.exists(path) {
                issues.append(LintingIssue(reason: "Configuration file not found at path \(path.pathString)", severity: .error))
            }
        }

        settings.configurations.xcconfigs().forEach { configFilePath in
            lintPath(configFilePath)
        }

        return issues
    }

    private func lintNonEmptyConfig(project: Project) -> [LintingIssue] {
        guard !project.settings.configurations.isEmpty else {
            return [LintingIssue(
                reason: "The project at path \(project.path.pathString) has no configurations",
                severity: .error
            )]
        }
        return []
    }

    // TODO_MAJOR_CHANGE: Merge deploymentTarget and platform arguments together.
    private func lint(platform: Platform, isCompatibleWith deploymentTarget: DeploymentTarget) -> [LintingIssue] {
        let issue = LintingIssue(
            reason: "Found an inconsistency between a platform `\(platform.caseValue)` and deployment target `\(deploymentTarget.platform)`",
            severity: .error
        )

        switch deploymentTarget {
        case .iOS: if platform != .iOS { return [issue] }
        case .macOS: if platform != .macOS { return [issue] }
        case .watchOS: if platform != .watchOS { return [issue] }
        case .tvOS: if platform != .tvOS { return [issue] }
        case .visionOS: if platform != .visionOS { return [issue] }
        }
        return []
    }
}
