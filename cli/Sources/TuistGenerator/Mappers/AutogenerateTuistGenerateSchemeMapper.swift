import Foundation
import Logging
import TuistCore
import TuistSupport
import XcodeGraph

public final class AutogenerateTuistGenerateSchemeMapper: GraphMapping { // swiftlint:disable:this type_name
    private let includeGenerateScheme: Bool

    // MARK: - Init

    public init(
        includeGenerateScheme: Bool,
    ) {
        self.includeGenerateScheme = includeGenerateScheme
    }

    public func map(
        graph: Graph,
        environment: MapperEnvironment
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        guard includeGenerateScheme else { return (graph, [], environment) }

        let schemes: [Scheme]
        let executablePath = Environment.current.currentExecutablePath()
        schemes = [
            Scheme(
                name: "Generate Project",
                shared: true,
                runAction: RunAction(
                    configurationName: "Debug",
                    attachDebugger: false,
                    customLLDBInitFile: nil,
                    executable: nil,
                    filePath: executablePath,
                    arguments: Arguments(launchArguments: [LaunchArgument(
                        name: "generate --no-open",
                        isEnabled: true
                    )]),
                    diagnosticsOptions: SchemeDiagnosticsOptions(),
                    customWorkingDirectory: graph.path,
                    useCustomWorkingDirectory: true
                ),
            ),
        ]

        var graph = graph
        var workspace = graph.workspace
        workspace.schemes.append(contentsOf: schemes)
        graph.workspace = workspace
        return (graph, [], environment)
    }
}
