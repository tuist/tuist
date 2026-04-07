import FileSystem
import Path
import TuistCore
import XcodeGraph

public struct StaticXCFrameworkAppIntentsMetadataGraphMapper: GraphMapping {
    private enum Constants {
        static let scriptName = "Inject App Intents Metadata from Cached Frameworks"
        static let script = """
        METADATA_FILE="${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyMetadataFileList"
        STATIC_METADATA_FILE="${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyStaticMetadataFileList"

        for framework_path in "${BUILT_PRODUCTS_DIR}"/*.framework; do
            [ -d "$framework_path" ] || continue

            framework_name="$(basename "$framework_path" .framework)"
            metadata_source="${framework_path}/Metadata.appintents"
            sibling_metadata="${BUILT_PRODUCTS_DIR}/${framework_name}.appintents/Metadata.appintents"

            [ -d "$metadata_source" ] || continue

            if [ ! -d "$sibling_metadata" ]; then
                mkdir -p "$sibling_metadata"
                cp -R "$metadata_source/" "$sibling_metadata/"
            fi

            actions_data="${sibling_metadata}/extract.actionsdata"
            [ -f "$actions_data" ] || continue

            touch "$METADATA_FILE" "$STATIC_METADATA_FILE"

            framework_actions_data="${framework_path}/Metadata.appintents/extract.actionsdata"
            if ! grep -qF "$framework_actions_data" "$METADATA_FILE"; then
                echo "$framework_actions_data" >> "$METADATA_FILE"
            fi

            if ! grep -qF "$actions_data" "$STATIC_METADATA_FILE"; then
                echo "$actions_data" >> "$STATIC_METADATA_FILE"
            fi
        done
        """
    }

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        let graphTraverser = GraphTraverser(graph: graph)
        let targets = try graphTraverser.allTargetsTopologicalSorted()
        var graph = graph

        for graphTarget in targets {
            guard graphTarget.target.product.runnable else { continue }
            guard try await requiresMetadataInjection(graph: graph, graphTarget: graphTarget) else { continue }
            guard !graphTarget.target.scripts.contains(where: { $0.name == Constants.scriptName }) else { continue }
            guard var project = graph.projects[graphTarget.path] else { continue }

            let updatedTarget = graphTarget.target.with(
                scripts: graphTarget.target.scripts + [metadataInjectionScript]
            )
            project.targets[updatedTarget.name] = updatedTarget
            graph.projects[graphTarget.path] = project
        }

        return (graph, [], environment)
    }

    private var metadataInjectionScript: TargetScript {
        TargetScript(
            name: Constants.scriptName,
            order: .pre,
            script: .embedded(Constants.script),
            basedOnDependencyAnalysis: false
        )
    }

    private func requiresMetadataInjection(
        graph: Graph,
        graphTarget: GraphTarget
    ) async throws -> Bool {
        let staticXCFrameworkDependencies = staticXCFrameworkDependencies(
            graph: graph,
            from: .target(name: graphTarget.target.name, path: graphTarget.path)
        )

        for dependency in staticXCFrameworkDependencies {
            guard case let .xcframework(xcframework) = dependency else { continue }
            if try await containsAppIntentsMetadata(at: xcframework.path) {
                return true
            }
        }

        return false
    }

    private func staticXCFrameworkDependencies(
        graph: Graph,
        from root: GraphDependency
    ) -> Set<GraphDependency> {
        var queue = Array(graph.dependencies[root, default: []])
        var visited: Set<GraphDependency> = []
        var result: Set<GraphDependency> = []

        while let dependency = queue.popLast() {
            guard visited.insert(dependency).inserted else { continue }

            if case let .xcframework(xcframework) = dependency, xcframework.linking == .static {
                result.insert(dependency)
            }

            queue.append(contentsOf: graph.dependencies[dependency, default: []])
        }

        return result
    }

    private func containsAppIntentsMetadata(at xcframeworkPath: AbsolutePath) async throws -> Bool {
        let metadataPaths = try await fileSystem.glob(
            directory: xcframeworkPath,
            include: ["**/Metadata.appintents"]
        ).collect()

        return !metadataPaths.isEmpty
    }
}
