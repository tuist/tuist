import Foundation
import TuistCore
@testable import TuistGenerator

final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    var installArgs: [Graphing] = []
    var installStub: Error?

    func install(graph: Graphing) throws {
        installArgs.append(graph)
        if let error = installStub { throw error }
    }
}
