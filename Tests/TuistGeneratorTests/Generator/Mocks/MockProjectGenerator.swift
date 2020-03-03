import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockProjectGenerator: ProjectGenerating {
    var generatedProjects: [Project] = []
    var generateStub: ((Project, Graphing, AbsolutePath?, AbsolutePath?) throws -> ProjectDescriptor)?

    func generate(project: Project, graph: Graphing, sourceRootPath: AbsolutePath?, xcodeprojPath: AbsolutePath?) throws -> ProjectDescriptor {
        generatedProjects.append(project)
        return try generateStub?(project, graph, sourceRootPath, xcodeprojPath) ?? stub
    }

    private var stub: ProjectDescriptor {
        ProjectDescriptor(path: "/test",
                          xcodeProj: XcodeProj(workspace: XCWorkspace(), pbxproj: PBXProj()),
                          schemes: [],
                          sideEffects: [])
    }
}
