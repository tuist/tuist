import FileSystem
import Path
import TuistCore
import XcodeGraph

public struct StaticXCFrameworkAppIntentsMetadataGraphMapper: GraphMapping {
    private struct AppIntentsMetadataDependency: Comparable, Hashable {
        let frameworkName: String

        static func < (lhs: AppIntentsMetadataDependency, rhs: AppIntentsMetadataDependency) -> Bool {
            lhs.frameworkName < rhs.frameworkName
        }
    }

    private enum Constants {
        static let scriptName = "Prepare App Intents Metadata for Static XCFrameworks"
        static let metadataFile = "${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyMetadataFileList"
        static let staticMetadataFile = "${TARGET_TEMP_DIR}/${TARGET_NAME}.DependencyStaticMetadataFileList"
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

            let metadataDependencies = try await appIntentsMetadataDependencies(
                graph: graph,
                graphTarget: graphTarget
            )
            guard !metadataDependencies.isEmpty else { continue }
            guard !graphTarget.target.scripts.contains(where: { $0.name == Constants.scriptName }) else { continue }
            guard var project = graph.projects[graphTarget.path] else { continue }

            let updatedTarget = graphTarget.target.with(
                scripts: graphTarget.target.scripts + [metadataInjectionScript(for: metadataDependencies)]
            )
            project.targets[updatedTarget.name] = updatedTarget
            graph.projects[graphTarget.path] = project
        }

        return (graph, [], environment)
    }

    private func metadataInjectionScript(for dependencies: [AppIntentsMetadataDependency]) -> TargetScript {
        let dependenciesScript = dependencies.map { dependency in
            """
            framework_name='\(dependency.frameworkName)'
            framework_metadata="${BUILT_PRODUCTS_DIR}/${framework_name}.framework/Metadata.appintents"
            static_metadata="${BUILT_PRODUCTS_DIR}/${framework_name}.appintents/Metadata.appintents"

            if [ -d "$framework_metadata" ] && [ ! -d "$static_metadata" ]; then
                mkdir -p "$static_metadata"
                cp -R "$framework_metadata/." "$static_metadata/"
            fi

            framework_actions_data="${framework_metadata}/extract.actionsdata"
            [ -f "$framework_actions_data" ] && echo "$framework_actions_data" >> "$METADATA_FILE"

            static_actions_data="${static_metadata}/extract.actionsdata"
            [ -f "$static_actions_data" ] && echo "$static_actions_data" >> "$STATIC_METADATA_FILE"
            """
        }.joined(separator: "\n\n")

        let script = """
        METADATA_FILE="\(Constants.metadataFile)"
        STATIC_METADATA_FILE="\(Constants.staticMetadataFile)"

        : > "$METADATA_FILE"
        : > "$STATIC_METADATA_FILE"

        \(dependenciesScript)
        """
        TargetScript(
            name: Constants.scriptName,
            order: .pre,
            script: .embedded(script),
            showEnvVarsInLog: false,
            basedOnDependencyAnalysis: false
        )
    }

    private func appIntentsMetadataDependencies(
        graph: Graph,
        graphTarget: GraphTarget
    ) async throws -> [AppIntentsMetadataDependency] {
        let staticXCFrameworkDependencies = staticXCFrameworkDependencies(
            graph: graph,
            from: .target(name: graphTarget.target.name, path: graphTarget.path)
        )

        var dependencies: Set<AppIntentsMetadataDependency> = []

        for dependency in staticXCFrameworkDependencies {
            guard case let .xcframework(xcframework) = dependency else { continue }
            dependencies.formUnion(try await appIntentsMetadataDependencies(in: xcframework))
        }

        return dependencies.sorted()
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

    private func appIntentsMetadataDependencies(
        in xcframework: GraphDependency.XCFramework
    ) async throws -> Set<AppIntentsMetadataDependency> {
        var dependencies: Set<AppIntentsMetadataDependency> = []

        for library in xcframework.infoPlist.libraries where library.path.extension == "framework" {
            let metadataPath = xcframework.path
                .appending(component: library.identifier)
                .appending(try RelativePath(validating: library.path.pathString))
                .appending(component: "Metadata.appintents")

            guard try await fileSystem.exists(metadataPath) else { continue }
            dependencies.insert(.init(frameworkName: library.binaryName))
        }

        return dependencies
    }
}
