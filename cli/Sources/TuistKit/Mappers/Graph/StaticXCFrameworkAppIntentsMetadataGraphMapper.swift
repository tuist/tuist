import FileSystem
import TuistCore
import XcodeGraph

public struct StaticXCFrameworkAppIntentsMetadataGraphMapper: GraphMapping {
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
            framework_metadata="\(dependency.frameworkMetadataPath)"
            static_metadata="\(dependency.staticMetadataPath)"

            if [ -d "$framework_metadata" ] && [ ! -d "$static_metadata" ]; then
                mkdir -p "$static_metadata"
                cp -R "$framework_metadata/." "$static_metadata/"
            fi

            framework_actions_data="${framework_metadata}/extract.actionsdata"
            if [ -f "$framework_actions_data" ] && ! grep -qxF "$framework_actions_data" "$METADATA_FILE"; then
                echo "$framework_actions_data" >> "$METADATA_FILE"
            fi

            static_actions_data="${static_metadata}/extract.actionsdata"
            if [ -f "$static_actions_data" ] && ! grep -qxF "$static_actions_data" "$STATIC_METADATA_FILE"; then
                echo "$static_actions_data" >> "$STATIC_METADATA_FILE"
            fi
            """
        }.joined(separator: "\n\n")

        let script = """
        METADATA_FILE="\(Constants.metadataFile)"
        STATIC_METADATA_FILE="\(Constants.staticMetadataFile)"

        mkdir -p "$(dirname "$METADATA_FILE")"
        touch "$METADATA_FILE" "$STATIC_METADATA_FILE"

        \(dependenciesScript)
        """

        // The dependency file lists are also produced by Xcode's native App Intents metadata
        // build phase on targets that contain their own App Intents sources. Declaring them as
        // outputs here would make the build fail with "Multiple commands produce …". We instead
        // append to the existing file lists without declaring them as outputs.
        return TargetScript(
            name: Constants.scriptName,
            order: .pre,
            script: .embedded(script),
            inputPaths: dependencies.flatMap(\.inputPaths),
            outputPaths: [],
            showEnvVarsInLog: false,
            basedOnDependencyAnalysis: false
        )
    }

    private func appIntentsMetadataDependencies(
        graph: Graph,
        graphTarget: GraphTarget
    ) async throws -> [AppIntentsMetadataDependency] {
        let graphTraverser = GraphTraverser(graph: graph)
        let dependencies = try graphTraverser.staticXCFrameworkAppIntentsMetadata(
            path: graphTarget.path,
            name: graphTarget.target.name
        )

        var result: Set<AppIntentsMetadataDependency> = []
        for dependency in dependencies where try await fileSystem.exists(dependency.metadataPath) {
            result.insert(.init(frameworkName: dependency.frameworkName))
        }

        return result.sorted()
    }
}

private struct AppIntentsMetadataDependency: Comparable, Hashable {
    let frameworkName: String

    var frameworkMetadataPath: String {
        "${BUILT_PRODUCTS_DIR}/\(frameworkName).framework/Metadata.appintents"
    }

    var staticMetadataPath: String {
        "${BUILT_PRODUCTS_DIR}/\(frameworkName).appintents/Metadata.appintents"
    }

    var inputPaths: [String] {
        [
            "\(frameworkMetadataPath)/extract.actionsdata",
            "\(frameworkMetadataPath)/version.json",
        ]
    }

    static func < (lhs: AppIntentsMetadataDependency, rhs: AppIntentsMetadataDependency) -> Bool {
        lhs.frameworkName < rhs.frameworkName
    }
}
