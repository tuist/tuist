import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
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
        let temporaryPath = try self.temporaryPath()
        let projects = (0 ..< 20).map {
            Project.test(path: temporaryPath.appending(component: "Project\($0)"),
                         name: "Test",
                         settings: .default,
                         targets: [Target.test(name: "Project\($0)_Target")])
        }
        let graph = Graph.create(projects: projects,
                                 dependencies: projects.flatMap { project in
                                     project.targets.map { target in
                                         (project: project, target: target, dependencies: [])
                                     }
                                 })
        let workspace = Workspace.test(path: temporaryPath, projects: projects.map(\.path))

        // When / Then
        try (0 ..< 50).forEach { _ in
            _ = try subject.generate(workspace: workspace,
                                     path: temporaryPath,
                                     graph: graph)
        }
    }
}
