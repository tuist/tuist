import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class WorkspaceGeneratorIntegrationTests: TuistTestCase {
    var subject: WorkspaceDescriptorGenerator!

    override func setUp() {
        super.setUp()
        subject = WorkspaceDescriptorGenerator(config: .init(projectGenerationContext: .concurrent))
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_generate_stressTest() throws {
        // Given
        let temporaryPath = try temporaryPath()
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
        try (0 ..< 50).forEach { _ in
            _ = try subject.generate(graphTraverser: graphTraverser)
        }
    }
}
