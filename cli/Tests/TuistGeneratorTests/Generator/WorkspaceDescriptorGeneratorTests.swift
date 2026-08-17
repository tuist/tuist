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
        try await FileSystem().makeDirectory(at: temporaryPath.appending(component: "\(name).xcworkspace"))
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
    ) func generate_workspaceStructureWithManifestProjectOrder() async throws {
        // Given
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        let mainPath = temporaryPath.appending(component: "Main")
        let featureBPath = temporaryPath.appending(components: "Features", "B")
        let featureAPath = temporaryPath.appending(components: "Features", "A")
        let dataPath = temporaryPath.appending(components: "Data", "Data")
        let unlistedPath = temporaryPath.appending(component: "Unlisted")
        let dependencyBPath = temporaryPath.appending(
            components: "Tuist", ".build", "tuist-derived", "Projects", "B"
        )
        let dependencyAPath = temporaryPath.appending(
            components: "Tuist", ".build", "tuist-derived", "Projects", "A"
        )
        let manifestProjects = [
            Project.test(
                path: mainPath,
                sourceRootPath: mainPath,
                xcodeProjPath: mainPath.appending(component: "Main.xcodeproj"),
                name: "Main",
                targets: []
            ),
            Project.test(
                path: featureBPath,
                sourceRootPath: featureBPath,
                xcodeProjPath: featureBPath.appending(component: "B.xcodeproj"),
                name: "B",
                targets: []
            ),
            Project.test(
                path: featureAPath,
                sourceRootPath: featureAPath,
                xcodeProjPath: featureAPath.appending(component: "A.xcodeproj"),
                name: "A",
                targets: []
            ),
            Project.test(
                path: dataPath,
                sourceRootPath: dataPath,
                xcodeProjPath: dataPath.appending(component: "Data.xcodeproj"),
                name: "Data",
                targets: []
            ),
        ]
        let graphOnlyProjects = [
            Project.test(
                path: unlistedPath,
                sourceRootPath: unlistedPath,
                xcodeProjPath: unlistedPath.appending(component: "Unlisted.xcodeproj"),
                name: "Unlisted",
                targets: []
            ),
            Project.test(
                path: dependencyBPath,
                sourceRootPath: dependencyBPath,
                xcodeProjPath: dependencyBPath.appending(component: "B.xcodeproj"),
                name: "B",
                targets: []
            ),
            Project.test(
                path: dependencyAPath,
                sourceRootPath: dependencyAPath,
                xcodeProjPath: dependencyAPath.appending(component: "A.xcodeproj"),
                name: "A",
                targets: []
            ),
        ]
        let projects = manifestProjects + graphOnlyProjects
        let readmePath = temporaryPath.appending(component: "README.md")
        try await FileSystem().touch(readmePath)
        let manifestProjectPaths = manifestProjects.map(\.path)
        let workspace = Workspace.test(
            xcWorkspacePath: temporaryPath.appending(component: "Test.xcworkspace"),
            projects: projects.map(\.path).sorted(),
            manifestProjectPaths: manifestProjectPaths,
            additionalFiles: [.file(path: readmePath)],
            generationOptions: .test(projectsOrder: .manifestOrder)
        )
        let graph = Graph.test(
            workspace: workspace,
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        )

        // When
        let result = try await subject.generate(graphTraverser: GraphTraverser(graph: graph))

        // Then
        #expect(result.xcworkspace.data.children == [
            .file(.init(location: .group("Main/Main.xcodeproj"))),
            .group(.init(location: .group("Features"), name: "Features", children: [
                .file(.init(location: .group("B/B.xcodeproj"))),
                .file(.init(location: .group("A/A.xcodeproj"))),
            ])),
            .group(.init(location: .group("Data"), name: "Data", children: [
                .file(.init(location: .group("Data/Data.xcodeproj"))),
            ])),
            .file(.init(location: .group("Unlisted/Unlisted.xcodeproj"))),
            .file(.init(location: .group("README.md"))),
            .group(.init(location: .container(""), name: "Dependencies", children: [
                .file(.init(location: .group("Tuist/.build/tuist-derived/Projects/A/A.xcodeproj"))),
                .file(.init(location: .group("Tuist/.build/tuist-derived/Projects/B/B.xcodeproj"))),
            ])),
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
