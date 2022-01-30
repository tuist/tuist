import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import XcodeProj

@testable import TuistGenerator

final class MockDescriptorGenerator: DescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateWorkspaceStub: ((GraphTraversing) throws -> WorkspaceDescriptor)?
    func generateWorkspace(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
        guard let generateWorkspaceStub = generateWorkspaceStub else {
            throw MockError.stubNotImplemented
        }

        return try generateWorkspaceStub(graphTraverser)
    }
}
