import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

public protocol ManifestLinting {
    func lint(project: ProjectDescription.Project, path: AbsolutePath) async throws -> [LintingIssue]
    func lint(workspace: ProjectDescription.Workspace, path: AbsolutePath) async throws -> [LintingIssue]
}

public struct AnyManifestLinter: ManifestLinting {
    let lintProject: ((ProjectDescription.Project, AbsolutePath) async throws -> [LintingIssue])?
    let lintWorkspace: ((ProjectDescription.Workspace, AbsolutePath) async throws -> [LintingIssue])?

    public init(
        lintProject: ((ProjectDescription.Project, AbsolutePath) async throws -> [LintingIssue])? = nil,
        lintWorkspace: ((ProjectDescription.Workspace, AbsolutePath) async throws -> [LintingIssue])? = nil
    ) {
        self.lintProject = lintProject
        self.lintWorkspace = lintWorkspace
    }

    public func lint(project: ProjectDescription.Project, path: AbsolutePath) async throws -> [LintingIssue] {
        if let lintProject {
            return try await lintProject(project, path)
        } else {
            return []
        }
    }

    public func lint(workspace: ProjectDescription.Workspace, path: AbsolutePath) async throws -> [LintingIssue] {
        if let lintWorkspace {
            return try await lintWorkspace(workspace, path)
        } else {
            return []
        }
    }
}

public struct ManifestLinter: ManifestLinting {
    private let fileSystem: FileSysteming
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(
        fileSystem: FileSysteming = FileSystem(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.fileSystem = fileSystem
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func lint(project: ProjectDescription.Project, path: AbsolutePath) async throws -> [LintingIssue] {
        var issues = [LintingIssue]()
        let rootDirectory = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path, rootDirectory: rootDirectory)

        if let settings = project.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: project.name))
        }

        issues.append(contentsOf: lintDuplicates(project: project))

        for target in project.targets {
            issues.append(contentsOf: lint(target: target))
            try await issues.append(contentsOf: lintFileElements(target: target, generatorPaths: generatorPaths))
        }

        for fileElement in project.additionalFiles {
            try await issues.append(contentsOf: lintFileElement(fileElement, generatorPaths: generatorPaths))
        }

        return issues
    }

    public func lint(workspace: ProjectDescription.Workspace, path: AbsolutePath) async throws -> [LintingIssue] {
        var issues = [LintingIssue]()
        let rootDirectory = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path, rootDirectory: rootDirectory)

        for scheme in workspace.schemes {
            issues.append(contentsOf: lintSchemeActions(
                buildAction: scheme.buildAction,
                runAction: scheme.runAction,
                profileAction: scheme.profileAction,
                testAction: scheme.testAction,
                scheme: scheme
            ))
        }

        try await issues.append(contentsOf: lintWorkspaceProjects(workspace, generatorPaths: generatorPaths))

        for fileElement in workspace.additionalFiles {
            try await issues.append(contentsOf: lintFileElement(fileElement, generatorPaths: generatorPaths))
        }

        return issues
    }

    // MARK: - File Element Linting

    private func lintFileElements(
        target: ProjectDescription.Target,
        generatorPaths: GeneratorPaths
    ) async throws -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let resources = target.resources {
            for element in resources.resources {
                try await issues.append(contentsOf: lintResourceFileElement(element, generatorPaths: generatorPaths))
            }
        }

        if let copyFiles = target.copyFiles {
            for action in copyFiles {
                for element in action.files {
                    try await issues.append(contentsOf: lintCopyFileElement(element, generatorPaths: generatorPaths))
                }
            }
        }

        for fileElement in target.additionalFiles {
            try await issues.append(contentsOf: lintFileElement(fileElement, generatorPaths: generatorPaths))
        }

        return issues
    }

    private func lintFileElement(
        _ element: ProjectDescription.FileElement,
        generatorPaths: GeneratorPaths
    ) async throws -> [LintingIssue] {
        switch element {
        case let .glob(pattern, _):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try await lintGlobPattern(resolvedPath)
        case let .folderReference(path):
            let resolvedPath = try generatorPaths.resolve(path: path)
            return try await lintFolderReference(resolvedPath)
        }
    }

    private func lintResourceFileElement(
        _ element: ProjectDescription.ResourceFileElement,
        generatorPaths: GeneratorPaths
    ) async throws -> [LintingIssue] {
        switch element {
        case let .glob(pattern, _, _, _):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try await lintGlobPattern(resolvedPath)
        case let .folderReference(path, _, _):
            let resolvedPath = try generatorPaths.resolve(path: path)
            return try await lintFolderReference(resolvedPath)
        }
    }

    private func lintCopyFileElement(
        _ element: ProjectDescription.CopyFileElement,
        generatorPaths: GeneratorPaths
    ) async throws -> [LintingIssue] {
        switch element {
        case let .glob(pattern, _, _):
            let resolvedPath = try generatorPaths.resolve(path: pattern)
            return try await lintGlobPattern(resolvedPath)
        case let .folderReference(path, _, _):
            let resolvedPath = try generatorPaths.resolve(path: path)
            return try await lintFolderReference(resolvedPath)
        }
    }

    private func lintGlobPattern(_ path: AbsolutePath) async throws -> [LintingIssue] {
        if try await fileSystem.exists(path), !FileHandler.shared.isFolder(path) {
            return []
        }

        let files: [AbsolutePath]
        do {
            files = try await fileSystem.throwingGlob(
                directory: AbsolutePath.root,
                include: [String(path.pathString.dropFirst())]
            )
            .collect()
        } catch GlobError.nonExistentDirectory {
            files = []
        }

        if files.isEmpty {
            if FileHandler.shared.isFolder(path) {
                return [LintingIssue(
                    reason: "'\(path.pathString)' is a directory, try using: '\(path.pathString)/**' to list its files",
                    severity: .warning
                )]
            } else if !path.isGlobPath {
                return [LintingIssue(
                    reason: "No files found at: \(path.pathString)",
                    severity: .warning
                )]
            }
        }

        return []
    }

    private func lintFolderReference(_ path: AbsolutePath) async throws -> [LintingIssue] {
        guard try await fileSystem.exists(path) else {
            return [LintingIssue(
                reason: "\(path.pathString) does not exist",
                severity: .warning
            )]
        }

        guard FileHandler.shared.isFolder(path) else {
            return [LintingIssue(
                reason: "\(path.pathString) is not a directory - folder reference paths need to point to directories",
                severity: .warning
            )]
        }

        return []
    }

    private func lintWorkspaceProjects(
        _ workspace: ProjectDescription.Workspace,
        generatorPaths: GeneratorPaths
    ) async throws -> [LintingIssue] {
        var issues = [LintingIssue]()

        for projectPath in workspace.projects {
            let resolvedPath = try generatorPaths.resolve(path: projectPath)
            let projects = try await fileSystem.glob(
                directory: AbsolutePath.root,
                include: [
                    String(resolvedPath.appending(component: "Package.swift").pathString.dropFirst()),
                    String(resolvedPath.appending(component: "Project.swift").pathString.dropFirst()),
                ]
            )
            .collect()
            .map(\.parentDirectory)
            .uniqued()

            if projects.isEmpty {
                issues.append(LintingIssue(
                    reason: "No projects found at: \(projectPath.pathString)",
                    severity: .warning
                ))
            }
        }

        return issues
    }

    // MARK: - Scheme Linting

    private func lintSchemeActions(
        buildAction: BuildAction?,
        runAction: RunAction?,
        profileAction: ProfileAction?,
        testAction: TestAction?,
        scheme: Scheme
    ) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let buildAction {
            issues.append(contentsOf: lintExecutionActionTargets(
                buildAction.preActions,
                actionType: "buildAction",
                scheme: scheme
            ))
            issues.append(contentsOf: lintExecutionActionTargets(
                buildAction.postActions,
                actionType: "buildAction",
                scheme: scheme
            ))
            issues.append(contentsOf: lintSchemeTargets(buildAction.targets, actionType: "buildAction", scheme: scheme))
        }

        if let runAction {
            issues.append(contentsOf: lintExecutionActionTargets(runAction.preActions, actionType: "runAction", scheme: scheme))
            issues.append(contentsOf: lintExecutionActionTargets(runAction.postActions, actionType: "runAction", scheme: scheme))
            issues.append(contentsOf: lintSchemeTarget(runAction.executable, actionType: "runAction", scheme: scheme))
            issues.append(contentsOf: lintSchemeTarget(
                runAction.expandVariableFromTarget,
                actionType: "runAction",
                scheme: scheme
            ))
        }

        if let profileAction {
            issues.append(contentsOf: lintExecutionActionTargets(
                profileAction.preActions,
                actionType: "profileAction",
                scheme: scheme
            ))
            issues.append(contentsOf: lintExecutionActionTargets(
                profileAction.postActions,
                actionType: "profileAction",
                scheme: scheme
            ))
            issues.append(contentsOf: lintSchemeTarget(profileAction.executable, actionType: "profileAction", scheme: scheme))
        }

        if let testAction {
            issues.append(contentsOf: lintExecutionActionTargets(testAction.preActions, actionType: "testAction", scheme: scheme))
            issues.append(contentsOf: lintExecutionActionTargets(
                testAction.postActions,
                actionType: "testAction",
                scheme: scheme
            ))
            issues.append(contentsOf: lintSchemeTargets(
                testAction.targets.map(\.target),
                actionType: "testAction",
                scheme: scheme
            ))
        }

        return issues
    }

    private func lintExecutionActionTargets(
        _ actions: [ExecutionAction],
        actionType: String,
        scheme: Scheme
    ) -> [LintingIssue] {
        let targets = actions.compactMap(\.target)
        return lintSchemeTargets(targets, actionType: actionType, scheme: scheme)
    }

    private func lintSchemeTargets(
        _ targets: [TargetReference],
        actionType: String,
        scheme: Scheme
    ) -> [LintingIssue] {
        return targets.flatMap { lintSchemeTarget($0, actionType: actionType, scheme: scheme) }
    }

    private func lintSchemeTarget(
        _ targetReference: TargetReference?,
        actionType: String,
        scheme: Scheme
    ) -> [LintingIssue] {
        guard let targetReference else { return [] }
        guard targetReference.projectPath == nil else { return [] }

        return [
            LintingIssue(
                reason: """
                Workspace.swift: The target '\(targetReference.targetName)' in the \(actionType) of the scheme '\(
                    scheme
                        .name
                )' is missing the project path.
                Please specify the project path using .project(path:, target:).
                """,
                severity: .error
            ),
        ]
    }

    // MARK: - Project Linting

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
                reason: "The current core data model version '\(String(describing: $0))' will be inferred automatically in '\(declarationLocation)' settings. It is not need it to set the current version anymore.",
                severity: .warning
            )
        }
    }
}
