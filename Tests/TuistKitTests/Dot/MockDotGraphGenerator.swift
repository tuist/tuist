import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistGraph
import TuistKit

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: GraphViz.Graph?
    func filter(
        graph: TuistGraph.Graph,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        targetsToFilter: [String]
    ) -> [GraphTarget: Set<GraphDependency>] { [:] }
    
    func map(
        graph: TuistGraph.Graph,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph {
        stubMap ?? GraphViz.Graph()
    }
}
