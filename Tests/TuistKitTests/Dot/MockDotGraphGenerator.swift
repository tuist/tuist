import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import XcodeProjectGenerator
import TuistKit

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: GraphViz.Graph?
    func map(
        graph _: XcodeProjectGenerator.Graph,
        targetsAndDependencies _: [GraphTarget: Set<GraphDependency>]
    ) -> GraphViz.Graph {
        stubMap ?? GraphViz.Graph()
    }
}
