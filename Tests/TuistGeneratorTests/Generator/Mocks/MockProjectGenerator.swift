import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

final class MockProjectGenerator: ProjectGenerating {
    var generatedProjects: [Project] = []
    var generateStub: ((Project, Graphing, AbsolutePath?, AbsolutePath?) throws -> GeneratedProject)?

    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?,
                  xcodeprojPath: AbsolutePath?) throws -> GeneratedProject {
        generatedProjects.append(project)
        return try generateStub?(project, graph, sourceRootPath, xcodeprojPath) ?? GeneratedProject.test()
    }

    func generateDescriptor(project _: Project, graph _: Graphing, sourceRootPath _: AbsolutePath?, xcodeprojPath _: AbsolutePath?) throws -> GeneratedProjectDescriptor {
        fatalError("Not yet implemented")
    }
}
