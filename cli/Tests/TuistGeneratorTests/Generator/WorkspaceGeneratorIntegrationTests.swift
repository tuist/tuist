import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
import FileSystemTesting
import Testing
@testable import TuistGenerator
@testable import TuistTesting

struct WorkspaceGeneratorIntegrationTests {
    let subject: WorkspaceDescriptorGenerator
    init() {
        subject = WorkspaceDescriptorGenerator(config: .init(projectGenerationContext: .concurrent))
    }

    // MARK: - Tests

    @Test(.inTemporaryDirectory)
    func test_generate_stressTest() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let projects: [AbsolutePath: Project] = (0 ..< 20).reduce(into: [:]) { acc, index in
            let path = temporaryPath.appending(component: "Project\(index)")
            acc[path] = Project.test(
                path: path,
                xcodeProjPath: temporaryPath.appending(components: "Project\(index)", "Project.xcodeproj"),
                name: "Test",
                settings: .default,
                targets: [Target.test(name: "Project\(index)_Target")]
            )
        }
        let graph = Graph.test(
            workspace: Workspace.test(
                path: temporaryPath,
                projects: projects.map(\.key)
            ),
            projects: projects
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When / Then
        for _ in 0 ..< 50 {
            _ = try await subject.generate(graphTraverser: graphTraverser)
        }
    }
}
