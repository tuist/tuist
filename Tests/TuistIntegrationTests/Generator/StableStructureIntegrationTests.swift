import Basic
import XcodeProj
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting
@testable import TuistGenerator

final class StableXcodeProjIntegrationTests: XCTestCase {
    private var fileHandler: MockFileHandler!
    private var path: AbsolutePath {
        return fileHandler.currentPath
    }

    override func setUp() {
        do {
            fileHandler = try MockFileHandler()
            try setupTestProject()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    override func tearDown() {
        fileHandler = nil
    }

    func testXcodeProjStructureDoesNotChangeAfterRegeneration() throws {
        // Given
        var capturedProjects = [[XcodeProj]]()
        var capturesWorkspaces = [XCWorkspace]()

        // When
        try (0 ..< 10).forEach { _ in
            let modelLoader = createModelLoader()
            let subject = Generator(printer: MockPrinter(), modelLoader: modelLoader)
            _ = try subject.generateWorkspace(at: path, config: .default, workspaceFiles: [])
            let workspace = try XCWorkspace(path: path.appending(component: "Workspace.xcworkspace").path)
            let projectsPaths = workspace.data.children
                .flatMap { $0.projectPaths }
                .map { path.appending(RelativePath($0)) }
            let xcodeProjs = try projectsPaths.map { try XcodeProj(path: $0.path) }
            capturedProjects.append(xcodeProjs)
            capturesWorkspaces.append(workspace)
        }

        // Then
        let unstableProjects = capturedProjects.dropFirst().filter { $0 != capturedProjects.first }
        let unstableWorkspaces = capturesWorkspaces.dropFirst().filter { $0 != capturesWorkspaces.first }

        XCTAssertEqual(unstableProjects.count, 0)
        XCTAssertEqual(unstableWorkspaces.count, 0)
    }

    // MARK: - Helpers

    private func setupTestProject() throws {
        try fileHandler.createFolders(["App/Sources"])
    }

    private func createModelLoader() -> GeneratorModelLoading {
        let modelLoader = MockGeneratorModelLoader(basePath: path)
        let frameworksNames = (0 ..< 10).map { "Framework\($0)" }
        let targetSettings = Settings(base: ["A1": "A_VALUE",
                                             "B1": "B_VALUE",
                                             "C1": "C_VALUE"],
                                      configurations: [.debug: nil,
                                                       .release: nil,
                                                       .debug("CustomDebug"): nil,
                                                       .release("CustomRelease"): nil])
        let projectSettings = Settings(base: ["A2": "A_VALUE",
                                              "B2": "B_VALUE",
                                              "C2": "C_VALUE"],
                                       configurations: [.debug: nil,
                                                        .release: nil,
                                                        .debug("CustomDebug2"): nil,
                                                        .release("CustomRelease2"): nil])
        let frameworkTargets = frameworksNames.map { createFrameworkTarget(name: $0) }
        let appTarget = createAppTarget(settings: targetSettings, dependencies: frameworksNames)
        let project = createProject(path: pathTo("App"),
                                    settings: projectSettings,
                                    targets: [appTarget] + frameworkTargets,
                                    schemes: [])
        let workspace = createWorkspace(projects: ["App"])
        modelLoader.mockProject("App") { _ in project }
        modelLoader.mockWorkspace { _ in workspace }
        return modelLoader
    }

    private func createWorkspace(projects: [String]) -> Workspace {
        return Workspace(name: "Workspace", projects: projects.map { pathTo($0) })
    }

    private func createProject(path: AbsolutePath, settings: Settings, targets: [Target], schemes: [Scheme]) -> Project {
        let additionalFiles = (0 ..< 10)
            .map { "/A\($0).txt" }
            .map { FileElement.file(path: AbsolutePath($0)) }
        return Project(path: path,
                       name: "App",
                       settings: settings,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
                       schemes: schemes,
                       additionalFiles: additionalFiles)
    }

    private func createAppTarget(settings: Settings?, dependencies: [String]) -> Target {
        let sources = (0 ..< 10)
            .map { "/App/Sources/SourceFile\($0).swift" }
            .map { AbsolutePath($0) }
        return Target(name: "AppTarget",
                      platform: .iOS,
                      product: .app,
                      bundleId: "test.bundle",
                      settings: settings,
                      sources: sources,
                      filesGroup: .group(name: "ProjectGroup"),
                      dependencies: dependencies.map { Dependency.target(name: $0) })
    }

    private func createFrameworkTarget(name: String) -> Target {
        return Target(name: name,
                      platform: .iOS,
                      product: .framework,
                      bundleId: "test.bundle.\(name)",
                      settings: nil,
                      sources: [],
                      filesGroup: .group(name: "ProjectGroup"))
    }

    private func pathTo(_ relativePath: String) -> AbsolutePath {
        return path.appending(RelativePath(relativePath))
    }
}

extension XCWorkspace {
    var projectPaths: [String] {
        return data.children.flatMap { $0.projectPaths }
    }
}

extension XCWorkspaceDataElement {
    var projectPaths: [String] {
        switch self {
        case let .file(file):
            let path = file.location.path
            return path.hasSuffix(".xcodeproj") ? [path] : []
        case let .group(elements):
            return elements.children.flatMap { $0.projectPaths }
        }
    }
}
