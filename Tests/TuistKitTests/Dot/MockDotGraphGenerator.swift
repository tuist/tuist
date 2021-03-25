import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistGraph
import TuistKit

final class MockGraphToGraphVizMapper: GraphToGraphVizMapping {
    var stubMap: Graph?
    func map(
        graph _: ValueGraph,
        skipTestTargets _: Bool,
        skipExternalDependencies _: Bool,
        targetsToFilter _: [String]
    ) -> Graph {
        stubMap ?? Graph()
    }
}
