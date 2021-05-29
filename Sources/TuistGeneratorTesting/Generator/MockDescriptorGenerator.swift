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

    var generateProjectSub: ((Project, GraphTraversing) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graphTraverser: GraphTraversing) throws -> ProjectDescriptor {
        guard let generateProjectSub = generateProjectSub else {
            throw MockError.stubNotImplemented
        }

        return try generateProjectSub(project, graphTraverser)
    }

    var generateWorkspaceStub: ((GraphTraversing) throws -> WorkspaceDescriptor)?
    func generateWorkspace(graphTraverser: GraphTraversing) throws -> WorkspaceDescriptor {
        guard let generateWorkspaceStub = generateWorkspaceStub else {
            throw MockError.stubNotImplemented
        }

        return try generateWorkspaceStub(graphTraverser)
    }
}
