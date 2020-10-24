import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockProjectDescriptorGenerator: ProjectDescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generatedProjects: [Project] = []
    var generateStub: ((Project, Graph) throws -> ProjectDescriptor)?

    func generate(project: Project, graph: Graph) throws -> ProjectDescriptor {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }
        generatedProjects.append(project)
        return try generateStub(project, graph)
    }
}
