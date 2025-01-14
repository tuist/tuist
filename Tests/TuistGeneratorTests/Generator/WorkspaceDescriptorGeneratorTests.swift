import Foundation
import Mockable
import Path
import struct TSCUtility.Version
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeGraph
import XcodeProj
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class WorkspaceDescriptorGeneratorTests: TuistUnitTestCase {
    var subject: WorkspaceDescriptorGenerator!

    override func setUp() {
        super.setUp()

        given(swiftVersionProvider)
            .swiftVersion()
            .willReturn("5.2")

        given(xcodeController)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        subject = WorkspaceDescriptorGenerator(config: .init(projectGenerationContext: .serial))
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_generate_workspaceStructure() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        try await createFiles([
            "README.md",
            "Documentation/README.md",
            "Website/index.html",
            "Website/about.html",
        ])

        let additionalFiles: [FileElement] = [
            .file(path: temporaryPath.appending(try RelativePath(validating: "README.md"))),
            .file(path: temporaryPath.appending(try RelativePath(validating: "Documentation/README.md"))),
            .folderReference(path: temporaryPath.appending(try RelativePath(validating: "Website"))),
        ]

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            additionalFiles: additionalFiles
        )
        let graph = Graph.test(
            path: temporaryPath,
            workspace: workspace
        )

        // When
        let graphTraverser = GraphTraverser(graph: graph)
        let result = try await subject.generate(graphTraverser: graphTraverser)

        // Then
        let xcworkspace = result.xcworkspace
        XCTAssertEqual(xcworkspace.data.children, [
            .group(.init(location: .group("Documentation"), name: "Documentation", children: [
                .file(.init(location: .group("README.md"))),
            ])),
            .file(.init(location: .group("README.md"))),
            .file(.init(location: .group("Website"))),
        ])
    }

    func test_generate_workspaceStructure_noWorkspaceData() async throws {
        // Given
        let name = "test"
        let temporaryPath = try temporaryPath()
        try FileHandler.shared.createFolder(temporaryPath.appending(component: "\(name).xcworkspace"))
        let workspace = Workspace.test(name: name)
        let graph = Graph.test(
            path: temporaryPath,
            workspace: workspace
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        do {
            _ = try await subject.generate(graphTraverser: graphTraverser)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func test_generate_workspaceStructureWithProjects() async throws {
        // Given
        let temporaryPath = try temporaryPath()
        let target = anyTarget()
        let project = Project.test(
            path: temporaryPath,
            sourceRootPath: temporaryPath,
            xcodeProjPath: temporaryPath.appending(component: "Test.xcodeproj"),
            name: "Test",
            settings: .default,
            targets: [target]
        )

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: [project.path]
        )

        let graph = Graph.test(
            workspace: workspace,
            projects: [project.path: project]
        )
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try await subject.generate(graphTraverser: graphTraverser)

        // Then
        let xcworkspace = result.xcworkspace
        XCTAssertEqual(xcworkspace.data.children, [
            .file(.init(location: .group("Test.xcodeproj"))),
        ])
    }

    func test_generateWorkspaceStructure_withSettingsDescriptorDisablingSchemaGeneration() async throws {
        // Given
        let temporaryPath = try temporaryPath()

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: [],
            generationOptions: .test(enableAutomaticXcodeSchemes: false)
        )

        let graph = Graph.test(workspace: workspace)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try await subject.generate(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(result.workspaceSettingsDescriptor, WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: false))
    }

    func test_generateWorkspaceStructure_withSettingsDescriptorEnablingSchemaGeneration() async throws {
        // Given
        let temporaryPath = try temporaryPath()

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: [],
            generationOptions: .test(enableAutomaticXcodeSchemes: true)
        )

        let graph = Graph.test(workspace: workspace)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try await subject.generate(graphTraverser: graphTraverser)

        // Then
        XCTAssertEqual(result.workspaceSettingsDescriptor, WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: true))
    }

    func test_generateWorkspaceStructure_withSettingsDescriptorDefaultSchemaGeneration() async throws {
        // Given
        let temporaryPath = try temporaryPath()

        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: [],
            generationOptions: .test(enableAutomaticXcodeSchemes: nil)
        )

        let graph = Graph.test(workspace: workspace)
        let graphTraverser = GraphTraverser(graph: graph)

        // When
        let result = try await subject.generate(graphTraverser: graphTraverser)

        // Then
        XCTAssertNil(result.workspaceSettingsDescriptor)
    }

    // MARK: - Helpers

    func anyTarget(dependencies: [TargetDependency] = []) -> Target {
        Target.test(
            infoPlist: nil,
            entitlements: nil,
            settings: nil,
            dependencies: dependencies
        )
    }
}

extension XCWorkspaceDataElement: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case let .file(file):
            return file.location.path
        case let .group(group):
            return group.debugDescription
        }
    }
}

extension XCWorkspaceDataGroup: CustomDebugStringConvertible {
    public var debugDescription: String {
        children.debugDescription
    }
}
