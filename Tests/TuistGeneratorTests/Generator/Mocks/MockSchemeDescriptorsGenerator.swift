import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockSchemeDescriptorsGenerator: SchemeDescriptorsGenerating {
    func generateProjectSchemes(project _: Project, generatedProject _: GeneratedProject, graph _: Graph) throws -> [SchemeDescriptor] {
        []
    }

    func generateWorkspaceSchemes(workspace _: Workspace, generatedProjects _: [AbsolutePath: GeneratedProject], graph _: Graph) throws -> [SchemeDescriptor] {
        []
    }
}
