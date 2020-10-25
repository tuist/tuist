import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockSchemeDescriptorsGenerator: SchemeDescriptorsGenerating {
    func generateProjectSchemes(project _: Project, projectDescriptor _: ProjectDescriptor, graph _: Graph) throws -> [SchemeDescriptor] {
        []
    }

    func generateWorkspaceSchemes(workspace _: Workspace, projectDescriptors _: [AbsolutePath: ProjectDescriptor], graph _: Graph) throws -> [SchemeDescriptor] {
        []
    }
}
