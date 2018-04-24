import Foundation

protocol GeneratorContexting: AnyObject {
    var graph: Graphing { get }
}

class GeneratorContext: GeneratorContexting {
    let graph: Graphing

    init(graph: Graphing) {
        self.graph = graph
    }
}
