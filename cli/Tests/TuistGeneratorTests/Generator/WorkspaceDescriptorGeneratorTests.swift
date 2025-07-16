import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import struct TSCUtility.Version
import TuistCore
import TuistSupport
import XcodeGraph
import XcodeProj
@testable import TuistGenerator
@testable import TuistTesting

struct WorkspaceDescriptorGeneratorTests {
    var subject: WorkspaceDescriptorGenerator!

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.2")
        let xcodeControllerMock = try #require(XcodeController.mocked)
        given(xcodeControllerMock)
            .selectedVersion()
            .willReturn(Version(15, 0, 0))

        subject = WorkspaceDescriptorGenerator(config: .init(projectGenerationContext: .serial))
    }

    // MARK: - Tests

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generate_workspaceStructure() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        try await TuistTest.createFiles([
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
        #expect(xcworkspace.data.children == [
            .group(.init(location: .group("Documentation"), name: "Documentation", children: [
                .file(.init(location: .group("README.md"))),
            ])),
            .file(.init(location: .group("README.md"))),
            .file(.init(location: .group("Website"))),
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generate_workspaceStructure_noWorkspaceData() async throws {
        // Given
        let name = "test"
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
            Issue.record("Should not throw")
        }
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generate_workspaceStructureWithProjects() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
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
        #expect(xcworkspace.data.children == [
            .file(.init(location: .group("Test.xcodeproj"))),
        ])
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWorkspaceStructure_withSettingsDescriptorDisablingSchemaGeneration() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)

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
        #expect(result.workspaceSettingsDescriptor == WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: false))
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWorkspaceStructure_withSettingsDescriptorEnablingSchemaGeneration() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)

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
        #expect(result.workspaceSettingsDescriptor == WorkspaceSettingsDescriptor(enableAutomaticXcodeSchemes: true))
    }

    @Test(
        .withMockedSwiftVersionProvider,
        .withMockedXcodeController,
        .inTemporaryDirectory
    ) func generateWorkspaceStructure_withSettingsDescriptorDefaultSchemaGeneration() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)

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
        #expect(result.workspaceSettingsDescriptor == nil)
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
