import Basic
import TuistCore
import TuistSupport
import XcodeProj
import XCTest

@testable import TuistGenerator
@testable import TuistSupport
@testable import TuistSupportTesting

final class StableXcodeProjIntegrationTests: TuistUnitTestCase {
    override func setUp() {
        super.setUp()

        do {
            try setupTestProject()
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testXcodeProjStructureDoesNotChangeAfterRegeneration() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        var capturedProjects = [[XcodeProj]]()
        var capturesWorkspaces = [XCWorkspace]()
        var capturedSharedSchemes = [[XCScheme]]()
        var capturedUserSchemes = [[XCScheme]]()

        // When
        try (0 ..< 10).forEach { _ in
            let subject = Generator(modelLoader: try createModelLoader())

            let (workspacePath, _) = try subject.generateWorkspace(at: temporaryPath, workspaceFiles: [])

            let workspace = try XCWorkspace(path: workspacePath.path)
            let xcodeProjs = try findXcodeProjs(in: workspace)
            let sharedSchemes = try findSharedSchemes(in: workspace)
            let userSchemes = try findUserSchemes(in: workspace)
            capturedProjects.append(xcodeProjs)
            capturesWorkspaces.append(workspace)
            capturedSharedSchemes.append(sharedSchemes)
            capturedUserSchemes.append(userSchemes)
        }

        // Then
        let unstableProjects = capturedProjects.dropFirst().filter { $0 != capturedProjects.first }
        let unstableWorkspaces = capturesWorkspaces.dropFirst().filter { $0 != capturesWorkspaces.first }
        let unstableSharedSchemes = capturedSharedSchemes.dropFirst().filter { $0 != capturedSharedSchemes.first }
        let unstableUserSchemes = capturedUserSchemes.dropFirst().filter { $0 != capturedUserSchemes.first }

        XCTAssertEqual(unstableProjects.count, 0)
        XCTAssertEqual(unstableWorkspaces.count, 0)
        XCTAssertEqual(unstableSharedSchemes.count, 0)
        XCTAssertEqual(unstableUserSchemes.count, 0)
    }

    // MARK: - Helpers

    private func findXcodeProjs(in workspace: XCWorkspace) throws -> [XcodeProj] {
        let temporaryPath = try self.temporaryPath()
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
        let temporaryPath = try self.temporaryPath()
        let projectsPaths = workspace.projectPaths.map { temporaryPath.appending(RelativePath($0)) }
        let parentDir = projectsPaths.map { $0.appending(relativePath) }
        let schemes = try parentDir.map { FileHandler.shared.glob($0, glob: "**/*.xcscheme") }
            .flatMap { $0 }
            .map { try XCScheme(path: $0.path) }
        return schemes
    }

    private func setupTestProject() throws {
        try createFolders(["App/Sources"])
    }

    private func createModelLoader() throws -> GeneratorModelLoading {
        let temporaryPath = try self.temporaryPath()
        let modelLoader = MockGeneratorModelLoader(basePath: temporaryPath)
        let frameworksNames = (0 ..< 10).map { "Framework\($0)" }
        let unitTestsTargetNames = (0 ..< 10).map { "TestAppTests\($0)" }
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
        let projectPath = try pathTo("App")
        let dependencies = try createDependencies(relativeTo: projectPath)
        let frameworkTargets = try frameworksNames.map { try createFrameworkTarget(name: $0, depenendencies: dependencies) }
        let appTarget = createTarget(name: "AppTarget", settings: targetSettings, dependencies: frameworksNames)
        let appUnitTestsTargets = unitTestsTargetNames.map { createTarget(name: $0,
                                                                          product: .unitTests,
                                                                          settings: nil,
                                                                          dependencies: [appTarget.name]) }
        let schemes = try createSchemes(appTarget: appTarget, frameworkTargets: frameworkTargets)
        let project = createProject(path: projectPath,
                                    settings: projectSettings,
                                    targets: [appTarget] + frameworkTargets + appUnitTestsTargets,
                                    schemes: schemes)
        let workspace = try createWorkspace(projects: ["App"])
        let tuistConfig = createTuistConfig()

        modelLoader.mockProject("App") { _ in project }
        modelLoader.mockWorkspace { _ in workspace }
        modelLoader.mockTuistConfig { _ in tuistConfig }
        return modelLoader
    }

    private func createTuistConfig() -> TuistConfig {
        TuistConfig(compatibleXcodeVersions: .all,
                    generationOptions: [])
    }

    private func createWorkspace(projects: [String]) throws -> Workspace {
        Workspace(path: AbsolutePath("/"), name: "Workspace", projects: try projects.map { try pathTo($0) })
    }

    private func createProject(path: AbsolutePath, settings: Settings, targets: [Target], packages: [Package] = [], schemes: [Scheme]) -> Project {
        Project(path: path,
                name: "App",
                settings: settings,
                filesGroup: .group(name: "Project"),
                targets: targets,
                packages: packages,
                schemes: schemes,
                additionalFiles: createAdditionalFiles())
    }

    private func createTarget(name: String, product: Product = .app, settings: Settings?, dependencies: [String]) -> Target {
        Target(name: name,
               platform: .iOS,
               product: product,
               productName: name,
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
        Target(name: name,
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
        let frameworks = try createFiles(prebuiltFrameworks)
            .map { Dependency.framework(path: $0) }

        let libraries = try createLibraries(relativeTo: path)

        return (frameworks + libraries).shuffled()
    }

    private func createLibraries(relativeTo _: AbsolutePath) throws -> [Dependency] {
        var libraries = [Dependency]()

        for i in 0 ..< 10 {
            let libraryName = "Library\(i)"
            let library = "Libraries/\(libraryName)/lib\(libraryName).a"
            let headers = "Libraries/\(libraryName)/Headers"
            let swiftModuleMap = "Libraries/\(libraryName)/\(libraryName).swiftmodule"

            let files = try createFiles([
                library,
                headers,
                swiftModuleMap,
            ])

            libraries.append(.library(path: files[0], publicHeaders: files[1], swiftModuleMap: files[2]))
        }

        return libraries
    }

    private func createSchemes(appTarget: Target, frameworkTargets: [Target]) throws -> [Scheme] {
        let targets = try ([appTarget] + frameworkTargets).map(targetReference(from:))
        return (0 ..< 10).map {
            let boolStub = $0 % 2 == 0
            return Scheme(
                name: "Scheme \($0)",
                shared: boolStub,
                buildAction: BuildAction(targets: targets,
                                         preActions: createExecutionActions(),
                                         postActions: createExecutionActions()),
                testAction: TestAction(targets: targets.map { TestableTarget(target: $0) },
                                       arguments: createArguments(),
                                       configurationName: "Debug",
                                       coverage: boolStub,
                                       codeCoverageTargets: targets,
                                       preActions: createExecutionActions(),
                                       postActions: createExecutionActions()),
                runAction: RunAction(configurationName: "Debug",
                                     executable: nil,
                                     arguments: createArguments()),
                archiveAction: ArchiveAction(configurationName: "Debug",
                                             revealArchiveInOrganizer: boolStub,
                                             preActions: createExecutionActions(),
                                             postActions: createExecutionActions())
            )
        }
    }

    private func createArguments() -> Arguments {
        let environment = (0 ..< 10).reduce([String: String]()) { acc, value in
            var acc = acc
            acc["Environment\(value)"] = "EnvironmentValue\(value)"
            return acc
        }
        let launch = (0 ..< 10).reduce([String: Bool]()) { acc, value in
            var acc = acc
            acc["Launch\(value)"] = value % 2 == 0
            return acc
        }
        return Arguments(environment: environment, launch: launch)
    }

    private func createExecutionActions() -> [ExecutionAction] {
        (0 ..< 10).map {
            ExecutionAction(title: "ExecutionAction\($0)", scriptText: "ScripText\($0)", target: nil)
        }
    }

    private func pathTo(_ relativePath: String) throws -> AbsolutePath {
        let temporaryPath = try self.temporaryPath()
        return temporaryPath.appending(RelativePath(relativePath))
    }

    private func targetReference(from target: Target) throws -> TargetReference {
        TargetReference(projectPath: try pathTo("App"), name: target.name)
    }
}

extension XCWorkspace {
    var projectPaths: [String] {
        data.children.flatMap { $0.projectPaths }
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
