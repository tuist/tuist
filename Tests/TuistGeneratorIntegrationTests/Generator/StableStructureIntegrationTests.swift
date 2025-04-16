import FileSystem
import Path
import TuistCore
import TuistCoreTesting
import TuistLoaderTesting
import TuistSupport
import XcodeProj
import Testing
import ServiceContextModule

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

struct StableXcodeProjIntegrationTests {
    private var fileSystem: FileSysteming = FileSystem()

    @Test(.mocked, .temporaryDirectory)
    func testXcodeProjStructureDoesNotChangeAfterRegeneration() async throws {
        // Given
        let temporaryDirectory = ServiceContext.current!.temporaryDirectory!
        var capturedProjects = [[XcodeProj]]()
        var capturedWorkspaces = [XCWorkspace]()
        var capturedSharedSchemes = [[XCScheme]]()
        var capturedUserSchemes = [[XCScheme]]()

        // When
        for _ in 0 ..< 10 {
            let subject = DescriptorGenerator()
            let writer = XcodeProjWriter()
            let config = TestModelGenerator.WorkspaceConfig(
                projects: 4,
                testTargets: 10,
                frameworkTargets: 10,
                staticFrameworkTargets: 10,
                staticLibraryTargets: 10,
                schemes: 10,
                sources: 200,
                resources: 100,
                headers: 100
            )
            let modelGenerator = TestModelGenerator(rootPath: temporaryDirectory, config: config)
            let graph = try await modelGenerator.generate()
            let graphTraverser = GraphTraverser(graph: graph)

            let workspaceDescriptor = try await subject.generateWorkspace(graphTraverser: graphTraverser)

            // Note: While we already have access to the `XcodeProj` models in `workspaceDescriptor`
            // unfortunately they are not equatable, however once serialized & deserialized back they are
            try await writer.write(workspace: workspaceDescriptor)
            let xcworkspace = try XCWorkspace(path: workspaceDescriptor.xcworkspacePath.path)
            let xcodeProjs = try findXcodeProjs(in: xcworkspace, temporaryDirectory: temporaryDirectory)
            let sharedSchemes = try await findSharedSchemes(in: xcworkspace, temporaryDirectory: temporaryDirectory)
            let userSchemes = try await findUserSchemes(in: xcworkspace, temporaryDirectory: temporaryDirectory)

            capturedProjects.append(xcodeProjs)
            capturedWorkspaces.append(xcworkspace)
            capturedSharedSchemes.append(sharedSchemes)
            capturedUserSchemes.append(userSchemes)
        }

        // Then
        let unstableProjects = capturedProjects.dropFirst().filter { $0 != capturedProjects.first }
        let unstableWorkspaces = capturedWorkspaces.dropFirst().filter { $0 != capturedWorkspaces.first }
        let unstableSharedSchemes = capturedSharedSchemes.dropFirst().filter { $0 != capturedSharedSchemes.first }
        let unstableUserSchemes = capturedUserSchemes.dropFirst().filter { $0 != capturedUserSchemes.first }

        #expect(unstableProjects.count == 0)
        #expect(unstableWorkspaces.count == 0)
        #expect(unstableSharedSchemes.count == 0)
        #expect(unstableUserSchemes.count == 0)
    }

    // MARK: - Helpers

    private func findXcodeProjs(in workspace: XCWorkspace, temporaryDirectory: AbsolutePath) throws -> [XcodeProj] {
        let projectsPaths = try workspace.projectPaths.map { temporaryDirectory.appending(try RelativePath(validating: $0)) }
        let xcodeProjs = try projectsPaths.map { try XcodeProj(path: $0.path) }
        return xcodeProjs
    }

    private func findSharedSchemes(in workspace: XCWorkspace, temporaryDirectory: AbsolutePath) async throws -> [XCScheme] {
        try await findSchemes(in: workspace, relativePath: try RelativePath(validating: "xcshareddata"), temporaryDirectory: temporaryDirectory)
    }

    private func findUserSchemes(in workspace: XCWorkspace, temporaryDirectory: AbsolutePath) async throws -> [XCScheme] {
        try await findSchemes(in: workspace, relativePath: try RelativePath(validating: "xcuserdata"), temporaryDirectory: temporaryDirectory)
    }

    private func findSchemes(in workspace: XCWorkspace, relativePath: RelativePath, temporaryDirectory: AbsolutePath) async throws -> [XCScheme] {
        let projectsPaths = try workspace.projectPaths.map { temporaryDirectory.appending(try RelativePath(validating: $0)) }
        let parentDir = projectsPaths.map { $0.appending(relativePath) }
        let schemes: [XCScheme] = try await parentDir.concurrentMap {
            try await self.fileSystem.glob(
                directory: $0,
                include: ["**/*.xcscheme", "*.xcscheme"]
            )
            .collect()
        }
        .flatMap { $0 }
        .sorted()
        .map { try XCScheme(path: $0.path) }
        return schemes
    }
}

extension XCWorkspace {
    var projectPaths: [String] {
        data.children.flatMap(\.projectPaths)
    }
}

extension XCWorkspaceDataElement {
    var projectPaths: [String] {
        switch self {
        case let .file(file):
            let path = file.location.path
            return path.hasSuffix(".xcodeproj") ? [path] : []
        case let .group(elements):
            return elements.children.flatMap(\.projectPaths)
        }
    }
}
