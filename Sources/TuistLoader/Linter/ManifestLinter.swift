import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

public protocol ManifestLinting {
    func lint(project: ProjectDescription.Project) -> [LintingIssue]
    func lint(workspace: ProjectDescription.Workspace) -> [LintingIssue]
}

public class AnyManifestLinter: ManifestLinting {
    let lintProject: ((ProjectDescription.Project) -> [LintingIssue])?
    let lintWorkspace: ((ProjectDescription.Workspace) -> [LintingIssue])?

    public init(
        lintProject: ((ProjectDescription.Project) -> [LintingIssue])? = nil,
        lintWorkspace: ((ProjectDescription.Workspace) -> [LintingIssue])? = nil
    ) {
        self.lintProject = lintProject
        self.lintWorkspace = lintWorkspace
    }

    public func lint(project: ProjectDescription.Project) -> [LintingIssue] {
        if let lintProject {
            return lintProject(project)
        } else {
            return []
        }
    }

    public func lint(workspace: ProjectDescription.Workspace) -> [LintingIssue] {
        if let lintWorkspace {
            return lintWorkspace(workspace)
        } else {
            return []
        }
    }
}

public class ManifestLinter: ManifestLinting {
    public init() {}

    public func lint(project: ProjectDescription.Project) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = project.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: project.name))
        }

        issues.append(contentsOf: lintDuplicates(project: project))
        issues.append(contentsOf: project.targets.flatMap(lint))

        return issues
    }

    public func lint(workspace: ProjectDescription.Workspace) -> [LintingIssue] {
        var issues = [LintingIssue]()

        for scheme in workspace.schemes {
            if let buildAction = scheme.buildAction {
                issues.append(contentsOf: lintWorkspaceSchemeTargets(
                    buildAction.targets,
                    actionType: "buildAction",
                    scheme: scheme
                ))
            }

            if let runAction = scheme.runAction {
                issues.append(contentsOf: lintWorkspaceSchemeTarget(
                    runAction.expandVariableFromTarget,
                    actionType: "runAction",
                    scheme: scheme
                ))
            }

            if let profileAction = scheme.profileAction {
                issues.append(contentsOf: lintWorkspaceSchemeTarget(
                    profileAction.executable,
                    actionType: "profileAction",
                    scheme: scheme
                ))
            }
        }

        return issues
    }

    private func lintWorkspaceSchemeTargets(
        _ targets: [TargetReference],
        actionType: String,
        scheme: Scheme
    ) -> [LintingIssue] {
        var issues = [LintingIssue]()

        for targetReference in targets {
            issues.append(contentsOf: lintWorkspaceSchemeTarget(
                targetReference,
                actionType: actionType,
                scheme: scheme
            ))
        }

        return issues
    }

    private func lintWorkspaceSchemeTarget(
        _ targetReference: TargetReference?,
        actionType: String,
        scheme: Scheme
    ) -> [LintingIssue] {
        var issues = [LintingIssue]()

        guard let targetReference else { return issues }

        guard targetReference.projectPath == nil else { return issues }

        issues.append(
            LintingIssue(
                reason: """
                Workspace.swift: The target '\(targetReference.targetName)' in the \(actionType) of the scheme '\(
                    scheme
                        .name
                )' is missing the project path.
                Please specify the project path using .project(path:, target:).
                """,
                severity: .warning
            )
        )

        return issues
    }

    private func lintDuplicates(project: ProjectDescription.Project) -> [LintingIssue] {
        let targetsNames = project.targets.map(\.name)

        return targetsNames.spm_findDuplicates().map {
            LintingIssue(
                reason: "The target '\($0)' is declared multiple times within '\(project.name)' project.",
                severity: .error
            )
        }
    }

    private func lint(target: ProjectDescription.Target) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = target.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: target.name))
        }

        issues.append(contentsOf: lint(coredataModels: target.coreDataModels, declarationLocation: target.name))

        return issues
    }

    private func lint(settings: ProjectDescription.Settings, declarationLocation: String) -> [LintingIssue] {
        let configurationNames = settings.configurations.map(\.name.rawValue)

        return configurationNames.spm_findDuplicates().map {
            LintingIssue(
                reason: "The configuration '\($0)' is declared multiple times within '\(declarationLocation)' settings. The last declared configuration will be used.",
                severity: .warning
            )
        }
    }

    private func lint(coredataModels: [ProjectDescription.CoreDataModel], declarationLocation: String) -> [LintingIssue] {
        let currentVersions = coredataModels.compactMap(\.currentVersion)

        return currentVersions.map {
            LintingIssue(
                reason: "The current core data model version '\(String(describing: $0))' will be infered automatically in '\(declarationLocation)' settings. It is not need it to set the current version anymore.",
                severity: .warning
            )
        }
    }
}
