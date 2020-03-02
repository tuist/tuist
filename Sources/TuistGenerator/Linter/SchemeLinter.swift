import Foundation
import TuistCore
import TuistSupport

protocol SchemeLinting {
    func lint(project: Project) -> [LintingIssue]
}

class SchemeLinter: SchemeLinting {
    func lint(project: Project) -> [LintingIssue] {
        var issues = [LintingIssue]()
        issues.append(contentsOf: lintReferencedBuildConfigurations(schemes: project.schemes, settings: project.settings))
        issues.append(contentsOf: lintCodeCoverageTargets(schemes: project.schemes, targets: project.targets))
        issues.append(contentsOf: projectSchemeCantReferenceRemoteTargets(schemes: project.schemes, project: project))
        return issues
    }
}

private extension SchemeLinter {
    func lintReferencedBuildConfigurations(schemes: [Scheme], settings: Settings) -> [LintingIssue] {
        let buildConfigurations = Array(settings.configurations.keys)
        return schemes.flatMap { lintScheme(scheme: $0, buildConfigurations: buildConfigurations) }
    }

    func lintScheme(scheme: Scheme, buildConfigurations: [BuildConfiguration]) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let buildConfigurationNames = buildConfigurations.map(\.name)

        if let runAction = scheme.runAction {
            if !buildConfigurationNames.contains(runAction.configurationName) {
                issues.append(
                    missingBuildConfigurationIssue(buildConfigurationName: runAction.configurationName,
                                                   actionDescription: "the scheme's run action")
                )
            }
        }

        if let testAction = scheme.testAction {
            if !buildConfigurationNames.contains(testAction.configurationName) {
                issues.append(
                    missingBuildConfigurationIssue(buildConfigurationName: testAction.configurationName,
                                                   actionDescription: "the scheme's test action")
                )
            }
        }

        if let buildAction = scheme.buildAction {
            if !buildConfigurationNames.contains(buildAction.configurationName) {
                issues.append(
                    missingBuildConfigurationIssue(buildConfigurationName: buildAction.configurationName,
                                                   actionDescription: "the scheme's build action")
                )
            }
        }

        return issues
    }

    func missingBuildConfigurationIssue(buildConfigurationName: String, actionDescription: String) -> LintingIssue {
        let reason = "The build configuration '\(buildConfigurationName)' specified in \(actionDescription) isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }

    func lintCodeCoverageTargets(schemes: [Scheme], targets: [Target]) -> [LintingIssue] {
        let targetNames = targets.map { $0.name }
        var issues: [LintingIssue] = []

        for scheme in schemes {
            for target in scheme.testAction?.codeCoverageTargets ?? [] {
                if !targetNames.contains(target.name) {
                    issues.append(missingCodeCoverageTargetIssue(missingTargetName: target.name, schemaName: scheme.name))
                }
            }
        }

        return issues
    }

    func missingCodeCoverageTargetIssue(missingTargetName: String, schemaName: String) -> LintingIssue {
        let reason = "The target '\(missingTargetName)' specified in \(schemaName) code coverage targets list isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }

    func projectSchemeCantReferenceRemoteTargets(schemes: [Scheme], project: Project) -> [LintingIssue] {
        schemes.flatMap { projectSchemeCantReferenceRemoteTargets(scheme: $0, project: project) }
    }

    func projectSchemeCantReferenceRemoteTargets(scheme: Scheme, project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        scheme.targetDependencies().forEach {
            if $0.projectPath != project.path {
                issues.append(.init(reason: "The target '\($0.name)' specified in scheme '\(scheme.name)' is not defined in the project. Consider using a workspace scheme instead to reference a target in another project.", severity: .error))
            }
        }

        return issues
    }
}
