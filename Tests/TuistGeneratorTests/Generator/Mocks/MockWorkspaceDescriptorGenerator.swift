import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import XcodeProjectGenerator
import XcodeProjectGeneratorTesting
import TuistSupport
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
