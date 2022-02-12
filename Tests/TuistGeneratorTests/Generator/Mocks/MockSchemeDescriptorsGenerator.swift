import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
@testable import TuistGenerator

final class MockSchemeDescriptorsGenerator: SchemeDescriptorsGenerating {
    func generateProjectSchemes(
        project _: Project,
        generatedProject _: GeneratedProject,
        graphTraverser _: GraphTraversing
    ) throws -> [SchemeDescriptor] {
        []
    }

    func generateWorkspaceSchemes(
        workspace _: Workspace,
        generatedProjects _: [AbsolutePath: GeneratedProject],
        graphTraverser _: GraphTraversing
    ) throws -> [SchemeDescriptor] {
        []
    }
}
