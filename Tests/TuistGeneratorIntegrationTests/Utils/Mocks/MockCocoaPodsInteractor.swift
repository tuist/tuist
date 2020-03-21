import Foundation
import TuistCore
@testable import TuistGenerator

final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    var installArgs: [Graph] = []
    var installStub: Error?

    func install(graph: Graph) throws {
        installArgs.append(graph)
        if let error = installStub { throw error }
    }
}
