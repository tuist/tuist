import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistGraph
import TuistKit

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: GraphViz.Graph?
    func filter(
        graph _: TuistGraph.Graph,
        skipTestTargets _: Bool,
        skipExternalDependencies _: Bool,
        targetsToFilter _: [String]
    ) -> [GraphTarget: Set<GraphDependency>] { [:] }

    func map(
        graph _: TuistGraph.Graph,
        targetsAndDependencies _: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph {
        stubMap ?? GraphViz.Graph()
    }
}
