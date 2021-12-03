import Foundation
import TSCBasic
import TSCUtility

public struct Workspace: Equatable, Codable {
    // MARK: - Attributes

    /// Path to where the manifest / root directory of this workspace is located
    public var path: AbsolutePath
    /// Path to where the `.xcworkspace` will be generated
    public var xcWorkspacePath: AbsolutePath
    public var name: String
    public var projects: [AbsolutePath]
    public var schemes: [Scheme]
    public var ideTemplateMacros: IDETemplateMacros?
    public var additionalFiles: [FileElement]
    public var lastUpgradeCheck: Version?

    // MARK: - Init

    public init(
        path: AbsolutePath,
        xcWorkspacePath: AbsolutePath,
        name: String,
        projects: [AbsolutePath],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        lastUpgradeCheck: Version? = nil
    ) {
        self.path = path
        self.xcWorkspacePath = xcWorkspacePath
        self.name = name
        self.projects = projects
        self.schemes = schemes
        self.ideTemplateMacros = ideTemplateMacros
        self.additionalFiles = additionalFiles
        self.lastUpgradeCheck = lastUpgradeCheck
    }
}

extension Workspace {
    public func with(name: String) -> Workspace {
        var copy = self
        copy.name = name
        return copy
    }

    public func adding(files: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles + files.map { .file(path: $0) },
            lastUpgradeCheck: lastUpgradeCheck
        )
    }

    public func replacing(projects: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            lastUpgradeCheck: lastUpgradeCheck
        )
    }

    public func merging(projects otherProjects: [AbsolutePath]) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: Array(Set(projects + otherProjects)),
            schemes: schemes,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            lastUpgradeCheck: lastUpgradeCheck
        )
    }

    public func codeCoverageTargets(mode: CodeCoverageMode?, projects: [Project]) -> [TargetReference] {
        switch mode {
        case .all, .none: return []
        case let .targets(targets): return targets
        case .relevant:
            let allSchemes = schemes + projects.flatMap(\.schemes)
            var resultTargets = Set<TargetReference>()

            allSchemes.forEach { scheme in
                // try to add code coverage targets only if code coverage is enabled
                guard let testAction = scheme.testAction, testAction.coverage else { return }

                let schemeCoverageTargets = testAction.codeCoverageTargets

                // having empty `codeCoverageTargets` means that we should gather code coverage for all build targets
                if schemeCoverageTargets.isEmpty, let buildAction = scheme.buildAction {
                    resultTargets.formUnion(buildAction.targets)
                } else {
                    resultTargets.formUnion(schemeCoverageTargets)
                }
            }

            // if we find no schemes that gather code coverage data, there are no relevant targets,
            // so we disable code coverage
            if resultTargets.isEmpty {
                return []
            }

            return Array(resultTargets)
        }
    }
}
