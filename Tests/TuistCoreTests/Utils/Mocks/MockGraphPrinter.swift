import Foundation
import TuistGenerator

@testable import TuistKit

final class MockGraphPrinter: GraphPrinting {
    var printArgs: [Graph] = []

    func print(graph: Graph) {
        printArgs.append(graph)
    }
}
