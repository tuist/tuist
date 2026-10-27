import Path
import XcodeGraph

// MARK: - CircularDependencyLinting

public protocol CircularDependencyLinting {
    func lintWorkspace(workspace: Workspace, projects: [Project]) throws
}

// MARK: - CircularDependencyLinter

public struct CircularDependencyLinter: CircularDependencyLinting {
    public init() {}

    public func lintWorkspace(workspace: Workspace, projects: [Project]) throws {
        let cycleDetector = GraphCircularDetector()
        let cache = GraphLoader.Cache(projects: projects)

        var stack = workspace.projects
            .reversed()
            .map { LintFrame.project(path: $0) }

        while let frame = stack.popLast() {
            switch frame {
            case let .project(path):
                try lintProject(path: path, cache: cache, stack: &stack)

            case let .target(path, name):
                try lintTarget(path: path, name: name, cache: cache, stack: &stack)

            case let .dependency(path, fromTarget, dependency):
                lintDependency(
                    path: path,
                    fromTarget: fromTarget,
                    dependency: dependency,
                    stack: &stack,
                    cycleDetector: cycleDetector
                )

            case .completeTarget:
                try cycleDetector.complete()
            }
        }
    }

    // MARK: - Private

    private enum LintFrame {
        case project(path: AbsolutePath)
        case target(path: AbsolutePath, name: String)
        case dependency(path: AbsolutePath, fromTarget: String, dependency: TargetDependency)
        case completeTarget
    }

    private func lintProject(
        path: AbsolutePath,
        cache: GraphLoader.Cache,
        stack: inout [LintFrame]
    ) throws {
        guard !cache.projectLoaded(path: path) else {
            return
        }
        guard let project = cache.allProjects[path] else {
            throw GraphLoadingError.missingProject(path)
        }
        cache.add(project: project)

        for target in project.targets.values.sorted(by: >) {
            stack.append(.target(path: path, name: target.name))
        }
    }

    private func lintTarget(
        path: AbsolutePath,
        name: String,
        cache: GraphLoader.Cache,
        stack: inout [LintFrame]
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

        stack.append(.completeTarget)
        for item in target.dependencies.reversed() {
            stack.append(
                .dependency(
                    path: path,
                    fromTarget: target.name,
                    dependency: item
                )
            )
        }
    }

    private func lintDependency(
        path: AbsolutePath,
        fromTarget: String,
        dependency: TargetDependency,
        stack: inout [LintFrame],
        cycleDetector: GraphCircularDetector
    ) {
        switch dependency {
        case let .target(toTarget, _, _):
            // A target within the same project.
            let circularFrom = GraphCircularDetectorNode(path: path, name: fromTarget)
            let circularTo = GraphCircularDetectorNode(path: path, name: toTarget)
            cycleDetector.start(from: circularFrom, to: circularTo)
            stack.append(.target(path: path, name: toTarget))

        case let .project(toTarget, projectPath, _, _):
            // A target from another project.
            let circularFrom = GraphCircularDetectorNode(path: path, name: fromTarget)
            let circularTo = GraphCircularDetectorNode(path: projectPath, name: toTarget)
            cycleDetector.start(from: circularFrom, to: circularTo)
            stack.append(.target(path: projectPath, name: toTarget))
            stack.append(.project(path: projectPath))

        case .framework, .xcframework, .library, .package, .sdk, .xctest:
            break
        }
    }
}
