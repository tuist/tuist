import Foundation
import TuistCore
@testable import TuistGenerator

final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    var installArgs: [Graphable] = []
    var installStub: Error?

    func install(graph: Graphable) throws {
        installArgs.append(graph)
        if let error = installStub { throw error }
    }
}
