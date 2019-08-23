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
        super.setUp()

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
            let subject = Generator(modelLoader: try createModelLoader())

            let workspacePath = try subject.generateWorkspace(at: path, workspaceFiles: [])

            let workspace = try XCWorkspace(path: workspacePath.path)
            let xcodeProjs = try findXcodeProjs(in: workspace)
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

    private func findXcodeProjs(in workspace: XCWorkspace) throws -> [XcodeProj] {
        let projectsPaths = workspace.projectPaths.map { path.appending(RelativePath($0)) }
        let xcodeProjs = try projectsPaths.map { try XcodeProj(path: $0.path) }
        return xcodeProjs
    }

    private func setupTestProject() throws {
        try fileHandler.createFolders(["App/Sources"])
    }

    private func createModelLoader() throws -> GeneratorModelLoading {
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
        let projectPath = pathTo("App")
        let dependencies = try createDependencies(relativeTo: projectPath)
        let frameworkTargets = try frameworksNames.map { try createFrameworkTarget(name: $0, depenendencies: dependencies) }
        let appTarget = createAppTarget(settings: targetSettings, dependencies: frameworksNames)
        let project = createProject(path: projectPath,
                                    settings: projectSettings,
                                    targets: [appTarget] + frameworkTargets,
                                    schemes: [])
        let workspace = createWorkspace(projects: ["App"])
        let tuistConfig = createTuistConfig()

        modelLoader.mockProject("App") { _ in project }
        modelLoader.mockWorkspace { _ in workspace }
        modelLoader.mockTuistConfig { _ in tuistConfig }
        return modelLoader
    }

    private func createTuistConfig() -> TuistConfig {
        return TuistConfig(compatibleXcodeVersions: .all,
                           generationOptions: [])
    }

    private func createWorkspace(projects: [String]) -> Workspace {
        return Workspace(name: "Workspace", projects: projects.map { pathTo($0) })
    }

    private func createProject(path: AbsolutePath, settings: Settings, targets: [Target], schemes: [Scheme]) -> Project {
        return Project(path: path,
                       name: "App",
                       settings: settings,
                       filesGroup: .group(name: "Project"),
                       targets: targets,
                       schemes: schemes,
                       additionalFiles: createAdditionalFiles())
    }

    private func createAppTarget(settings: Settings?, dependencies: [String]) -> Target {
        return Target(name: "AppTarget",
                      platform: .iOS,
                      product: .app,
                      productName: "AppTarget",
                      bundleId: "test.bundle",
                      settings: settings,
                      sources: createSources(),
                      resources: createResources(),
                      headers: createHeaders(),
                      filesGroup: .group(name: "ProjectGroup"),
                      dependencies: dependencies.map { Dependency.target(name: $0) })
    }

    private func createSources() -> [Target.SourceFile] {
        let sources: [Target.SourceFile] = (0 ..< 10)
            .map { "/App/Sources/SourceFile\($0).swift" }
            .map { (path: AbsolutePath($0), compilerFlags: nil) }
            .shuffled()
        return sources
    }

    private func createHeaders() -> Headers {
        let publicHeaders = (0 ..< 10)
            .map { "/App/Sources/PublicHeader\($0).h" }
            .map { AbsolutePath($0) }
            .shuffled()

        let privateHeaders = (0 ..< 10)
            .map { "/App/Sources/PrivateHeader\($0).h" }
            .map { AbsolutePath($0) }
            .shuffled()

        let projectHeaders = (0 ..< 10)
            .map { "/App/Sources/ProjectHeader\($0).h" }
            .map { AbsolutePath($0) }
            .shuffled()

        return Headers(public: publicHeaders, private: privateHeaders, project: projectHeaders)
    }

    private func createResources() -> [FileElement] {
        let files = (0 ..< 10)
            .map { "/App/Resources/Resource\($0).png" }
            .map { FileElement.file(path: AbsolutePath($0)) }

        let folderReferences = (0 ..< 10)
            .map { "/App/Resources/Folder\($0)" }
            .map { FileElement.folderReference(path: AbsolutePath($0)) }

        return (files + folderReferences).shuffled()
    }

    private func createAdditionalFiles() -> [FileElement] {
        let files = (0 ..< 10)
            .map { "/App/Files/File\($0).md" }
            .map { FileElement.file(path: AbsolutePath($0)) }

        // When using ** glob patterns (e.g. `Documentation/**`)
        // the results will include the folders in addition to the files
        //
        // e.g.
        //    Documentation
        //    Documentation/a.md
        //    Documentation/Subfolder
        //    Documentation/Subfolder/a.md
        let filesWithFolderPaths = files + [
            .file(path: AbsolutePath("/App/Files")),
        ]

        let folderReferences = (0 ..< 10)
            .map { "/App/Documentation\($0)" }
            .map { FileElement.folderReference(path: AbsolutePath($0)) }

        return (filesWithFolderPaths + folderReferences).shuffled()
    }

    private func createFrameworkTarget(name: String, depenendencies: [Dependency] = []) throws -> Target {
        return Target(name: name,
                      platform: .iOS,
                      product: .framework,
                      productName: name,
                      bundleId: "test.bundle.\(name)",
                      settings: nil,
                      sources: [],
                      filesGroup: .group(name: "ProjectGroup"),
                      dependencies: depenendencies)
    }

    private func createDependencies(relativeTo path: AbsolutePath) throws -> [Dependency] {
        let prebuiltFrameworks = (0 ..< 10).map { "Frameworks/Framework\($0).framework" }
        let frameworks = try fileHandler.createFiles(prebuiltFrameworks)
            .map { Dependency.framework(path: $0.relative(to: path)) }

        let libraries = try createLibraries(relativeTo: path)

        return (frameworks + libraries).shuffled()
    }

    private func createLibraries(relativeTo path: AbsolutePath) throws -> [Dependency] {
        var libraries = [Dependency]()

        for i in 0 ..< 10 {
            let libraryName = "Library\(i)"
            let library = "Libraries/\(libraryName)/lib\(libraryName).a"
            let headers = "Libraries/\(libraryName)/Headers"
            let swiftModuleMap = "Libraries/\(libraryName)/\(libraryName).swiftmodule"

            let files = try fileHandler.createFiles([
                library,
                headers,
                swiftModuleMap,
            ])

            libraries.append(
                .library(path: files[0].relative(to: path),
                         publicHeaders: files[1].relative(to: path),
                         swiftModuleMap: files[2].relative(to: path))
            )
        }

        return libraries
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
