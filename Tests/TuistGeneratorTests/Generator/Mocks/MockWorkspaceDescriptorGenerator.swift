import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockWorkspaceDescriptorGenerator: WorkspaceDescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Graph) throws -> WorkspaceDescriptor)?

    func generate(graph: Graph) throws -> WorkspaceDescriptor {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }
        generateWorkspaces.append(graph.workspace)
        return try generateStub(graph)
    }
}
