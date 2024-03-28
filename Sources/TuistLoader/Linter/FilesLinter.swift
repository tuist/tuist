import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol FilesLinting {
    func lint(project: LoadedWorkspace, convertedProjects: [TuistGraph.Project]) -> [LintingIssue]
}

public class FilesLinter: FilesLinting {
    public init() {}

    public func lint(project: LoadedWorkspace, convertedProjects: [TuistGraph.Project]) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        for item in convertedProjects {
            issues.append(contentsOf: lint(project: project.projects[item.path], convertedProject: item))
        }
        return issues
    }

    // MARK: - Private

    private func lint(project: ProjectDescription.Project?, convertedProject: TuistGraph.Project) -> [LintingIssue] {
        guard let project else { return [] }
        var issues: [LintingIssue] = []
        for target in convertedProject.targets {
            issues.append(contentsOf: lint(project: project, convertedTarget: target))
        }
        return issues
    }

    private func lint(project: ProjectDescription.Project, convertedTarget: TuistGraph.Target) -> [LintingIssue] {
        guard let target = project.targets.first(where: { $0.name == convertedTarget.name }) else { return [] }
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lint(fileList: target.sources, sources: convertedTarget.sources))
        issues.append(contentsOf: lint(resourceList: target.resources, resources: convertedTarget.resources))
        return issues
    }

    private func lint(fileList: SourceFilesList?, sources: [SourceFile]) -> [LintingIssue] {
        guard let fileList else { return [] }
        let sourcePaths = fileList.globs.filter { !$0.glob.pathString.isGlobComponent }
        var issues: [LintingIssue] = []
        for glob in sourcePaths {
            if sources.first(where: { $0.path.pathString.contains(glob.glob.pathString) }) == nil {
                issues.append(LintingIssue(reason: "No files found at: \(glob.glob.pathString)", severity: .warning))
            }
        }
        return issues
    }

    private func lint(resourceList: ResourceFileElements?, resources: [TuistGraph.ResourceFileElement]) -> [LintingIssue] {
        func check(resources: [TuistGraph.ResourceFileElement], path: String) -> TuistGraph.ResourceFileElement? {
            resources.first(where: { $0.path.pathString.contains(path) })
        }
        guard let resourceList else { return [] }
        var issues: [LintingIssue] = []
        for resource in resourceList.resources {
            switch resource {
            case let .glob(pattern, _, _, _):
                if !pattern.pathString.isGlobComponent, check(resources: resources, path: pattern.pathString) == nil {
                    issues.append(LintingIssue(reason: "No resources found at: \(pattern.pathString)", severity: .warning))
                }
            case let .folderReference(path, _, _):
                if check(resources: resources, path: path.pathString) == nil {
                    issues.append(LintingIssue(reason: "No resources found at: \(path.pathString)", severity: .warning))
                }
            }
        }
        return issues
    }
}
