import FileSystem
import Foundation
import Path
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

final class QueryDepsService {
    private let manifestGraphLoader: ManifestGraphLoading
    private let manifestLoader: ManifestLoading
    private let xcodeGraphMapper: XcodeGraphMapping
    private let configLoader: ConfigLoading

    convenience init() {
        let manifestLoader = ManifestLoader.current
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        self.init(
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            configLoader: configLoader
        )
    }

    init(
        manifestGraphLoader: ManifestGraphLoading,
        manifestLoader: ManifestLoading,
        xcodeGraphMapper: XcodeGraphMapping = XcodeGraphMapper(),
        configLoader: ConfigLoading
    ) {
        self.manifestGraphLoader = manifestGraphLoader
        self.manifestLoader = manifestLoader
        self.xcodeGraphMapper = xcodeGraphMapper
        self.configLoader = configLoader
    }

    func run(
        path: AbsolutePath,
        sourceTargets: [String],
        sinkTargets: [String],
        directOnly: Bool,
        typeFilter: Set<String>,
        format: QueryDepsFormat
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)
        let graph: XcodeGraph.Graph
        if try await manifestLoader.hasRootManifest(at: path) {
            (graph, _, _, _) = try await manifestGraphLoader.load(
                path: path,
                disableSandbox: config.project.disableSandbox
            )
        } else {
            graph = try await xcodeGraphMapper.map(at: path)
        }

        let filteredTargetsAndDependencies = graph.filter(
            skipTestTargets: false,
            skipExternalDependencies: false,
            platformToFilter: nil,
            targetsToFilter: [],
            sourceTargets: sourceTargets,
            sinkTargets: sinkTargets,
            directOnly: directOnly,
            typeFilter: typeFilter
        )

        let output = formatOutput(
            targetsAndDependencies: filteredTargetsAndDependencies,
            format: format,
            sourceTargets: sourceTargets,
            sinkTargets: sinkTargets
        )
        print(output)
    }

    private func formatOutput(
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>],
        format: QueryDepsFormat,
        sourceTargets: [String],
        sinkTargets: [String]
    ) -> String {
        switch format {
        case .list:
            return formatList(
                targetsAndDependencies: targetsAndDependencies,
                sourceTargets: sourceTargets,
                sinkTargets: sinkTargets
            )
        case .tree:
            return formatTree(
                targetsAndDependencies: targetsAndDependencies,
                sourceTargets: sourceTargets,
                sinkTargets: sinkTargets
            )
        case .json:
            return formatJSON(targetsAndDependencies: targetsAndDependencies)
        }
    }

    private func formatList(
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>],
        sourceTargets: [String],
        sinkTargets: [String]
    ) -> String {
        var lines: [String] = []
        let sortedTargets = targetsAndDependencies.keys.sorted { $0.target.name < $1.target.name }

        for target in sortedTargets {
            let dependencies = targetsAndDependencies[target] ?? []
            let sortedDeps = dependencies.sorted { $0.name < $1.name }

            let isSource = sourceTargets.contains(target.target.name)
            let isSink = sinkTargets.contains(target.target.name)
            let marker = if isSource, isSink {
                " [source, sink]"
            } else if isSource {
                " [source]"
            } else if isSink {
                " [sink]"
            } else {
                ""
            }

            lines.append("\(target.target.name)\(marker)")
            for dep in sortedDeps {
                lines.append("  - \(dep.name) (\(dep.labelName))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatTree(
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>],
        sourceTargets: [String],
        sinkTargets: [String]
    ) -> String {
        var lines: [String] = []
        let rootTargets: [GraphTarget]

        if !sourceTargets.isEmpty {
            rootTargets = targetsAndDependencies.keys
                .filter { sourceTargets.contains($0.target.name) }
                .sorted { $0.target.name < $1.target.name }
        } else if !sinkTargets.isEmpty {
            rootTargets = targetsAndDependencies.keys
                .filter { sinkTargets.contains($0.target.name) }
                .sorted { $0.target.name < $1.target.name }
        } else {
            rootTargets = targetsAndDependencies.keys.sorted { $0.target.name < $1.target.name }
        }

        for target in rootTargets {
            var visited = Set<String>()
            formatTreeNode(
                target: target,
                targetsAndDependencies: targetsAndDependencies,
                lines: &lines,
                prefix: "",
                isLast: true,
                visited: &visited
            )
        }

        return lines.joined(separator: "\n")
    }

    private func formatTreeNode(
        target: GraphTarget,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>],
        lines: inout [String],
        prefix: String,
        isLast: Bool,
        visited: inout Set<String>
    ) {
        let connector = isLast ? "└── " : "├── "
        let nodePrefix = prefix.isEmpty ? "" : prefix + connector
        lines.append("\(nodePrefix)\(target.target.name)")

        if visited.contains(target.target.name) {
            return
        }
        visited.insert(target.target.name)

        let dependencies = targetsAndDependencies[target] ?? []
        let targetDeps = dependencies.compactMap { dep -> GraphTarget? in
            if case let .target(name, path, _) = dep {
                return targetsAndDependencies.keys.first { $0.target.name == name && $0.path == path }
            }
            return nil
        }.sorted { $0.target.name < $1.target.name }

        let newPrefix = prefix + (isLast ? "    " : "│   ")
        for (index, dep) in targetDeps.enumerated() {
            let isLastDep = index == targetDeps.count - 1
            formatTreeNode(
                target: dep,
                targetsAndDependencies: targetsAndDependencies,
                lines: &lines,
                prefix: newPrefix,
                isLast: isLastDep,
                visited: &visited
            )
        }
    }

    private func formatJSON(
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) -> String {
        var result: [[String: Any]] = []

        let sortedTargets = targetsAndDependencies.keys.sorted { $0.target.name < $1.target.name }

        for target in sortedTargets {
            let dependencies = targetsAndDependencies[target] ?? []
            let sortedDeps = dependencies.sorted { $0.name < $1.name }

            let depsArray: [[String: String]] = sortedDeps.map { dep in
                ["name": dep.name, "type": dep.labelName]
            }

            result.append([
                "name": target.target.name,
                "path": target.path.pathString,
                "dependencies": depsArray,
            ])
        }

        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: result,
            options: [.prettyPrinted, .sortedKeys]
        ),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return "[]"
        }

        return jsonString
    }
}

extension GraphDependency {
    var name: String {
        switch self {
        case let .target(name, _, _):
            return name
        case let .packageProduct(_, name, _, _, _, _):
            return name
        case let .framework(path, _, _, _, _, _, _, _):
            return path.basenameWithoutExt
        case let .xcframework(path, _, _, _, _):
            return path.basenameWithoutExt
        case let .sdk(name, _, _, _):
            return name
        case let .bundle(path, _):
            return path.basenameWithoutExt
        case let .library(path, _, _, _, _, _):
            return path.basenameWithoutExt
        case let .macro(path, _):
            return path.basenameWithoutExt
        }
    }
}
