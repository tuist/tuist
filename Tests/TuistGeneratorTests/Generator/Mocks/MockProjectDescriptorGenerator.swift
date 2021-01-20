import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockProjectDescriptorGenerator: ProjectDescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generatedProjects: [Project] = []
    var generateStub: ((Project, GraphTraversing) throws -> ProjectDescriptor)?

    func generate(project: Project, graphTraverser: GraphTraversing) throws -> ProjectDescriptor {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }
        generatedProjects.append(project)
        return try generateStub(project, graphTraverser)
    }
}
