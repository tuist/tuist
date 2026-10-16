import Foundation
import Path
import Testing
import XcodeGraph
@testable import TuistCore

struct GraphLoaderDynamicPackageTests {
    @Test(arguments: [false, true])
    func preservesDynamicHintsFromTargetsToGraph(embedded: Bool) async throws {
        let path: AbsolutePath = "/project"
        let target = Target.test(
            name: "App",
            product: .app,
            dependencies: [.package(product: "Dynamic", type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic)]
        )
        let project = Project.test(path: path, targets: [target])
        let graph = try await GraphLoader().loadWorkspace(
            workspace: .test(path: path, projects: [path]),
            projects: [project]
        )

        #expect(graph.dependencies[.target(name: target.name, path: path)] == [
            .packageProduct(path: path, product: "Dynamic", type: embedded ? .runtimeDynamicEmbedded : .runtimeDynamic),
        ])
        let data = try JSONEncoder().encode(graph)
        let restored = try JSONDecoder().decode(Graph.self, from: data)
        #expect(restored.dependencies == graph.dependencies)
    }
}
