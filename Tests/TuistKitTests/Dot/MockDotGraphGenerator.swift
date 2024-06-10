import Foundation
import GraphViz
import Path
import TuistGenerator
import TuistKit
import XcodeGraph

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: GraphViz.Graph?
    func map(
        graph _: XcodeGraph.Graph,
        targetsAndDependencies _: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph {
        stubMap ?? GraphViz.Graph()
    }
}
