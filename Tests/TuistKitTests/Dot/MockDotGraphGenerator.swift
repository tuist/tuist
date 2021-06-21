import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistGraph
import TuistKit

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: GraphViz.Graph?
    func map(
        graph _: TuistGraph.Graph,
        skipTestTargets _: Bool,
        skipExternalDependencies _: Bool,
        targetsToFilter _: [String]
    ) -> GraphViz.Graph {
        stubMap ?? GraphViz.Graph()
    }
}
