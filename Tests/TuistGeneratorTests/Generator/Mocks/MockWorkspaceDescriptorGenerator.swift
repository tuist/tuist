import Foundation
import Path
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

final class MockWorkspaceDescriptorGenerator: WorkspaceDescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateWorkspaces: [Workspace] = []
    var generateStub: ((GraphTraversing) throws -> WorkspaceDescriptor)?

    func generate(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
        guard let generateStub else {
            throw MockError.stubNotImplemented
        }
        generateWorkspaces.append(graphTraverser.workspace)
        return try generateStub(graphTraverser)
    }
}
