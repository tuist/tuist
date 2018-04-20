import Foundation

protocol GeneratorContexting: AnyObject {
    var graphController: GraphController { get }
}

class GeneratorContext: GeneratorContexting {
    let graphController: GraphController

    init(graphController: GraphController) {
        self.graphController = graphController
    }
}
