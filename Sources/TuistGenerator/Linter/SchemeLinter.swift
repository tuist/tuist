
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

        if let runAction = scheme.runAction {
            if !buildConfigurations.contains(runAction.config) {
                issues.append(
                    missingBuildConfigurationIssue(buildConfigurations: runAction.config,
                                                   actionDescription: "the scheme's run action")
                )
            }
        }

        if let testAction = scheme.testAction {
            if !buildConfigurations.contains(testAction.config) {
                issues.append(
                    missingBuildConfigurationIssue(buildConfigurations: testAction.config,
                                                   actionDescription: "the scheme's test action")
                )
            }
        }

        return issues
    }

    func missingBuildConfigurationIssue(buildConfigurations: BuildConfiguration, actionDescription: String) -> LintingIssue {
        let reason = "The \(buildConfigurations.linterDescription) specified in \(actionDescription) isn't defined in the project."
        return LintingIssue(reason: reason, severity: .error)
    }
}

private extension BuildConfiguration {
    var linterDescription: String {
        return "\(variant) configuration '\(name)'"
    }
}
