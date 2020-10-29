import Foundation
import GraphViz
import TSCBasic
import TuistGenerator

final class MockGraphVizGenerator: GraphVizGenerating {
    var generateProjectArgs: [AbsolutePath] = []
    var generateWorkspaceArgs: [AbsolutePath] = []
    var generateProjectStub = GraphViz.Graph()
    var generateWorkspaceStub = GraphViz.Graph()

    func generateProject(at path: AbsolutePath, skipTestTargets _: Bool, skipExternalDependencies _: Bool) throws -> GraphViz.Graph {
        generateProjectArgs.append(path)
        return generateProjectStub
    }

    func generateWorkspace(at path: AbsolutePath, skipTestTargets _: Bool, skipExternalDependencies _: Bool) throws -> GraphViz.Graph {
        generateWorkspaceArgs.append(path)
        return generateWorkspaceStub
    }
}
