import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

protocol SettingsLinting: AnyObject {
    func lint(project: Project) async throws -> [LintingIssue]
    func lint(target: Target) async throws -> [LintingIssue]
}

final class SettingsLinter: SettingsLinting {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - SettingsLinting

    func lint(project: Project) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []
        try await issues.append(contentsOf: lintConfigFilesExist(settings: project.settings))
        issues.append(contentsOf: lintValidDefaultConfigurationName(settings: project.settings))
        issues.append(contentsOf: lintNonEmptyConfig(project: project))
        return issues
    }

    func lint(target: Target) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if let settings = target.settings {
            try await issues.append(contentsOf: lintConfigFilesExist(settings: settings))
            issues.append(contentsOf: lintValidDefaultConfigurationName(settings: settings))
        }

        issues.append(contentsOf: lintDestinations(for: target.supportedPlatforms, and: target.deploymentTargets))

        return issues
    }

    // MARK: - Fileprivate

    private func lintConfigFilesExist(settings: Settings) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let lintPath: (AbsolutePath) async throws -> Void = { path in
            if try await !self.fileSystem.exists(path) {
                issues.append(LintingIssue(reason: "Configuration file not found at path \(path.pathString)", severity: .error))
            }
        }

        for configFilePath in settings.configurations.xcconfigs() {
            try await lintPath(configFilePath)
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

    private func lintDestinations(
        for targetPlatforms: Set<Platform>,
        and deploymentTargets: DeploymentTargets
    ) -> [LintingIssue] {
        var missingPlatforms: [Platform] = []

        for deploymentTarget in deploymentTargets.configuredVersions {
            let platform = deploymentTarget.0
            if !targetPlatforms.contains(platform) {
                missingPlatforms.append(platform)
            }
        }

        if !missingPlatforms.isEmpty {
            return [LintingIssue(
                reason: "Found deployment platforms (\(missingPlatforms.map(\.caseValue).joined(separator: ", "))) missing corresponding destination",
                severity: .error
            )]
        } else {
            return []
        }
    }

    private func lintValidDefaultConfigurationName(settings: Settings) -> [LintingIssue] {
        guard let defaultConfigurationName = settings.defaultConfiguration else { return [] }

        guard settings.configurations.keys.first(where: { config in config.name == defaultConfigurationName }) != nil else {
            return [
                LintingIssue(
                    reason: "We couldn't find the default configuration '\(defaultConfigurationName)'. The configurations available are: \(settings.configurations.keys.map(\.name).joined(separator: ", "))",
                    severity: .error
                )
            ]
        }

        return []
    }
}
