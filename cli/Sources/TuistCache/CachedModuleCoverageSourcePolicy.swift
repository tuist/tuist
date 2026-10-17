import FileSystem
import Foundation
import Path
import TuistCore
import XcodeGraph

/// Ordinary artifacts cannot supply counters for a coverage build. Keep sources until an explicitly
/// instrumented variant can be requested and verified; do not reinterpret an ordinary cache hit.
public struct CachedModuleCoverageSourcePolicy {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func sourceTargets(in graph: Graph, schemeName: String? = nil) async throws -> Set<TargetReference> {
        try Task.checkCancellation()
        let schemes = graph.workspace.schemes + graph.projects.values.flatMap(\.schemes)
        var pending = [GraphDependency]()
        for scheme in schemes where schemeName == nil || scheme.name == schemeName {
            guard let action = scheme.testAction, try await requiresCoverage(action) else { continue }
            let targets = action.targets + (action.testPlans ?? []).flatMap(\.testTargets)
            pending.append(contentsOf: (targets.map(\.target) + action.codeCoverageTargets).map {
                .target(name: $0.name, path: $0.projectPath)
            })
        }
        var visited = Set<GraphDependency>()
        var sources = Set<TargetReference>()
        while let dependency = pending.popLast() {
            try Task.checkCancellation()
            guard visited.insert(dependency).inserted else { continue }
            if case let .target(name, path, _) = dependency {
                sources.insert(TargetReference(projectPath: path, name: name))
            }
            pending.append(contentsOf: graph.dependencies[dependency, default: []])
        }
        return sources
    }

    private func requiresCoverage(_ action: TestAction) async throws -> Bool {
        guard let plans = action.testPlans, !plans.isEmpty else { return action.coverage }
        for plan in plans {
            if plan.kind == .generated {
                if action.coverage { return true }
                continue
            }
            do {
                try Task.checkCancellation()
                guard let file = try await fileSystem.fileMetadata(at: plan.path),
                      file.size <= 4 * 1024 * 1024 else { return true }
                let data = try await fileSystem.readFile(at: plan.path)
                guard data.count <= 4 * 1024 * 1024 else { return true }
                let options = try JSONDecoder().decode(Plan.self, from: data)
                guard options.version == 1 else { return true }
                let defaultCoverage = options.defaultOptions?.codeCoverage ?? action.coverage
                if let configurations = options.configurations, !configurations.isEmpty {
                    if configurations.contains(where: { $0.options?.codeCoverage ?? defaultCoverage }) { return true }
                } else if defaultCoverage {
                    return true
                }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                return true
            }
        }
        return false
    }
}

private struct Plan: Decodable {
    struct Options: Decodable {
        let codeCoverage: Bool?
    }

    struct Configuration: Decodable {
        let options: Options?
    }

    let version: Int
    let defaultOptions: Options?
    let configurations: [Configuration]?
}
