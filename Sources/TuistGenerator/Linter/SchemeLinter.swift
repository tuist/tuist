import Foundation
import TuistCore
import TuistGraph
import TuistSupport

protocol SchemeLinting {
    func lint(project: Project) -> [LintingIssue]
}

class SchemeLinter: SchemeLinting {
    func lint(project: Project) -> [LintingIssue] {
        var issues = [LintingIssue]()
        issues.append(contentsOf: lintReferencedBuildConfigurations(schemes: project.schemes, settings: project.settings))
        issues.append(contentsOf: lintCodeCoverageTargets(schemes: project.schemes, targets: project.targets))
        issues.append(contentsOf: lintExpandVariableTarget(schemes: project.schemes, targets: project.targets))
        issues.append(contentsOf: projectSchemeCantReferenceRemoteTargets(schemes: project.schemes, project: project))
        return issues
    }
}

extension SchemeLinter {
    private func lintReferencedBuildConfigurations(schemes: [Scheme], settings: Settings) -> [LintingIssue] {
        let buildConfigurations = Array(settings.configurations.keys)
        return schemes.flatMap { lintScheme(scheme: $0, buildConfigurations: buildConfigurations) }
    }

    private func lintScheme(scheme: Scheme, buildConfigurations: [BuildConfiguration]) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let buildConfigurationNames = buildConfigurations.map(\.name)

        if let runAction = scheme.runAction {
            if !buildConfigurationNames.contains(runAction.configurationName) {
                issues.append(
                    missingBuildConfigurationIssue(
                        buildConfigurationName: runAction.configurationName,
                        actionDescription: "the scheme's run action"
                    )
                )
            }

            if let storeKitPath = runAction.options.storeKitConfigurationPath,
               !FileHandler.shared.exists(storeKitPath)
            {
                issues.append(
                    LintingIssue(
                        reason: "StoreKit configuration file not found at path \(storeKitPath.pathString)",
                        severity: .error
                    )
                )
            }
        }

        if let testAction = scheme.testAction {
            if !buildConfigurationNames.contains(testAction.configurationName) {
                issues.append(
                    missingBuildConfigurationIssue(
                        buildConfigurationName: testAction.configurationName,
                        actionDescription: "the scheme's test action"
                    )
                )
            }
            testAction.testPlans?.forEach { testPlan in
                if !FileHandler.shared.exists(testPlan.path) {
                    issues.append(
                        LintingIssue(
                            reason: "Test Plan not found at path \(testPlan.path.pathString)",
                            severity: .warning
                        )
                    )
                }
            }
        }

        return issues
    }

    private func missingBuildConfigurationIssue(buildConfigurationName: String, actionDescription: String) -> LintingIssue {
        let reason =
            "The build configuration '\(buildConfigurationName)' specified in \(actionDescription) isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }

    private func lintExpandVariableTarget(schemes: [Scheme], targets: [Target]) -> [LintingIssue] {
        let targetNames = targets.map(\.name)
        var issues: [LintingIssue] = []

        for scheme in schemes {
            if let testAction = scheme.testAction,
               let target = testAction.expandVariableFromTarget
            {
                if !targetNames.contains(target.name) {
                    issues.append(missingExpandVariablesTargetIssue(missingTargetName: target.name, schemaName: scheme.name))
                }
            }
        }
        return issues
    }

    private func lintCodeCoverageTargets(schemes: [Scheme], targets: [Target]) -> [LintingIssue] {
        let targetNames = targets.map(\.name)
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

    private func missingCodeCoverageTargetIssue(missingTargetName: String, schemaName: String) -> LintingIssue {
        let reason =
            "The target '\(missingTargetName)' specified in \(schemaName) code coverage targets list isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }

    private func missingExpandVariablesTargetIssue(missingTargetName: String, schemaName: String) -> LintingIssue {
        let reason =
            "The target '\(missingTargetName)' specified in \(schemaName) expandVariableFromTarget isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }

    private func projectSchemeCantReferenceRemoteTargets(schemes: [Scheme], project: Project) -> [LintingIssue] {
        schemes.flatMap { projectSchemeCantReferenceRemoteTargets(scheme: $0, project: project) }
    }

    private func projectSchemeCantReferenceRemoteTargets(scheme: Scheme, project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        scheme.targetDependencies().forEach {
            if $0.projectPath != project.path {
                issues.append(.init(
                    reason: "The target '\($0.name)' specified in scheme '\(scheme.name)' is not defined in the project named '\(project.name)'. Consider using a workspace scheme instead to reference a target in another project.",
                    severity: .error
                ))
            }
        }

        return issues
    }
}
