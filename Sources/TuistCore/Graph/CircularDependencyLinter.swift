import Foundation
import TSCBasic
import TuistGraph

// MARK: - CircularDependencyLinting

public protocol CircularDependencyLinting {
    func lintWorkspace(workspace: Workspace, projects: [Project]) throws
}

// MARK: - CircularDependencyLinter

public class CircularDependencyLinter: CircularDependencyLinting {
    public init() {}

    public func lintWorkspace(workspace: Workspace, projects: [Project]) throws {
        let cycleDetector = GraphCircularDetector()
        let cache = GraphLoader.Cache(projects: projects)
        for project in workspace.projects {
            try lintProject(
                path: project,
                cache: cache,
                cycleDetector: cycleDetector
            )
        }
    }

    // MARK: - Private

    private func lintProject(
        path: AbsolutePath,
        cache: GraphLoader.Cache,
        cycleDetector: GraphCircularDetector
    ) throws {
        guard !cache.projectLoaded(path: path) else {
            return
        }
        guard let project = cache.allProjects[path] else {
            throw GraphLoadingError.missingProject(path)
        }
        cache.add(project: project)

        for target in project.targets {
            try lintTarget(
                path: path,
                name: target.name,
                cache: cache,
                cycleDetector: cycleDetector
            )
        }
    }

    private func lintTarget(
        path: AbsolutePath,
        name: String,
        cache: GraphLoader.Cache,
        cycleDetector: GraphCircularDetector
    ) throws {
        guard !cache.targetLoaded(path: path, name: name) else {
            return
        }
        guard cache.allProjects[path] != nil else {
            throw GraphLoadingError.missingProject(path)
        }
        guard let referencedTargetProject = cache.allTargets[path],
              let target = referencedTargetProject[name]
        else {
            throw GraphLoadingError.targetNotFound(name, path)
        }

        cache.add(target: target, path: path)

        for item in target.dependencies {
            try lintDependency(
                path: path,
                fromTarget: target.name,
                dependency: item,
                cache: cache,
                cycleDetector: cycleDetector
            )
        }

        try cycleDetector.complete()
    }

    private func lintDependency(
        path: AbsolutePath,
        fromTarget: String,
        dependency: TargetDependency,
        cache: GraphLoader.Cache,
        cycleDetector: GraphCircularDetector
    ) throws {
        switch dependency {
        case let .target(toTarget, _):
            // A target within the same project.
            let circularFrom = GraphCircularDetectorNode(path: path, name: fromTarget)
            let circularTo = GraphCircularDetectorNode(path: path, name: toTarget)
            cycleDetector.start(from: circularFrom, to: circularTo)
            try lintTarget(
                path: path,
                name: toTarget,
                cache: cache,
                cycleDetector: cycleDetector
            )
        case let .project(toTarget, projectPath, _):
            // A target from another project
            let circularFrom = GraphCircularDetectorNode(path: path, name: fromTarget)
            let circularTo = GraphCircularDetectorNode(path: projectPath, name: toTarget)
            cycleDetector.start(from: circularFrom, to: circularTo)
            try lintProject(path: projectPath, cache: cache, cycleDetector: cycleDetector)
            try lintTarget(
                path: projectPath,
                name: toTarget,
                cache: cache,
                cycleDetector: cycleDetector
            )
        case .framework, .xcframework, .library, .package, .sdk, .xctest:
            break
        }
    }
}
