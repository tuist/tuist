import Foundation
import TuistCore

protocol SchemeLinting {
    func lint(project: Project) -> [LintingIssue]
}

class SchemeLinter: SchemeLinting {
    func lint(project: Project) -> [LintingIssue] {
        var issues = [LintingIssue]()
        issues.append(contentsOf: lintReferencedBuildConfigurations(schemes: project.schemes, settings: project.settings))
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

        return issues
    }

    func missingBuildConfigurationIssue(buildConfigurationName: String, actionDescription: String) -> LintingIssue {
        let reason = "The build configuration '\(buildConfigurationName)' specified in \(actionDescription) isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }
}
