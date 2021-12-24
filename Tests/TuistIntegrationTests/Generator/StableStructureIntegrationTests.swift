import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistLoaderTesting
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class StableXcodeProjIntegrationTests: TuistTestCase {
    func testXcodeProjStructureDoesNotChangeAfterRegeneration() throws {
        // Given
        let temporaryPath = try temporaryPath()
        var capturedProjects = [[XcodeProj]]()
        var capturedWorkspaces = [XCWorkspace]()
        var capturedSharedSchemes = [[XCScheme]]()
        var capturedUserSchemes = [[XCScheme]]()

        // When
        try (0 ..< 10).forEach { _ in
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
            let modelGenerator = TestModelGenerator(rootPath: temporaryPath, config: config)
            let graph = try modelGenerator.generate()
            let graphTraverser = GraphTraverser(graph: graph)

            let workspaceDescriptor = try subject.generateWorkspace(graphTraverser: graphTraverser)

            // Note: While we already have access to the `XcodeProj` models in `workspaceDescriptor`
            // unfortunately they are not equatable, however once serialized & deserialized back they are
            try writer.write(workspace: workspaceDescriptor)
            let xcworkspace = try XCWorkspace(path: workspaceDescriptor.xcworkspacePath.path)
            let xcodeProjs = try findXcodeProjs(in: xcworkspace)
            let sharedSchemes = try findSharedSchemes(in: xcworkspace)
            let userSchemes = try findUserSchemes(in: xcworkspace)

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

        XCTAssertEqual(unstableProjects.count, 0)
        XCTAssertEqual(unstableWorkspaces.count, 0)
        XCTAssertEqual(unstableSharedSchemes.count, 0)
        XCTAssertEqual(unstableUserSchemes.count, 0)
    }

    // MARK: - Helpers

    private func findXcodeProjs(in workspace: XCWorkspace) throws -> [XcodeProj] {
        let temporaryPath = try temporaryPath()
        let projectsPaths = workspace.projectPaths.map { temporaryPath.appending(RelativePath($0)) }
        let xcodeProjs = try projectsPaths.map { try XcodeProj(path: $0.path) }
        return xcodeProjs
    }

    private func findSharedSchemes(in workspace: XCWorkspace) throws -> [XCScheme] {
        try findSchemes(in: workspace, relativePath: RelativePath("xcshareddata"))
    }

    private func findUserSchemes(in workspace: XCWorkspace) throws -> [XCScheme] {
        try findSchemes(in: workspace, relativePath: RelativePath("xcuserdata"))
    }

    private func findSchemes(in workspace: XCWorkspace, relativePath: RelativePath) throws -> [XCScheme] {
        let temporaryPath = try temporaryPath()
        let projectsPaths = workspace.projectPaths.map { temporaryPath.appending(RelativePath($0)) }
        let parentDir = projectsPaths.map { $0.appending(relativePath) }
        let schemes = try parentDir.map { FileHandler.shared.glob($0, glob: "**/*.xcscheme") }
            .flatMap { $0 }
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
