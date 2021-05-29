import Foundation
import TSCBasic
import TuistCore
@testable import TuistGenerator

final class MockCocoaPodsInteractor: CocoaPodsInteracting {
    var invokedInstall = false
    var invokedInstallCount = 0
    var invokedInstallParameters: GraphTraversing?
    var invokedInstallParametersList = [GraphTraversing]()
    var stubbedInstallError: Error?

    func install(graphTraverser: GraphTraversing) throws {
        invokedInstall = true
        invokedInstallCount += 1
        invokedInstallParameters = graphTraverser
        invokedInstallParametersList.append(graphTraverser)
        if let error = stubbedInstallError {
            throw error
        }
    }
}
