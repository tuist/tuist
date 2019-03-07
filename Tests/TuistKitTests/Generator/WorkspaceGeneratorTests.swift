import Basic
import Foundation
import ProjectDescription
import xcodeproj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class WorkspaceGeneratorTests: XCTestCase {
    var subject: WorkspaceGenerator!

    var path: AbsolutePath!
    var target: TuistKit.Target!
    var project: TuistKit.Project!
    var graph: Graph!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()

        do {
            fileHandler = try MockFileHandler()
            path = fileHandler.currentPath

            target = Target.test(name: "App")
            project = Project.test(path: path)

            let projectDirectoryHelper = ProjectDirectoryHelper(environmentController: try MockEnvironmentController(), fileHandler: fileHandler)

            subject = WorkspaceGenerator(
                system: MockSystem(),
                printer: MockPrinter(),
                resourceLocator: MockResourceLocator(),
                projectDirectoryHelper: projectDirectoryHelper,
                fileHandler: fileHandler
            )

            let targetNode = TargetNode(project: project, target: target, dependencies: [])
            let cache = GraphLoaderCache()
            cache.add(targetNode: targetNode)

            graph = Graph.test(entryPath: path, cache: cache)

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func test_generate_includesManifests_bothFilesExist() throws {
        // Given both files are available
        // When generating the workspace
        // I expect both files to be added to the workspace

        try fileHandler.touch(path.appending(component: "Workspace.swift"))
        try fileHandler.touch(path.appending(component: "Setup.swift"))

        try subject.generate(path: path, graph: graph, options: GenerationOptions())

        let workspace = try readWorkspace(at: path)

        XCTAssertTrue(workspace.contains("Setup.swift"))
        XCTAssertTrue(workspace.contains("Workspace.swift"))
    }

    func test_generate_includesManifests_oneFilesExists() throws {
        // Given only Setup.swift is available
        // When generating the workspace
        // I expect Setup.swift to be added to the workspace and Workspace.swift to not be added

        try fileHandler.touch(path.appending(component: "Setup.swift"))

        try subject.generate(path: path, graph: graph, options: GenerationOptions())

        let workspace = try readWorkspace(at: path)

        XCTAssertTrue(workspace.contains("Setup.swift"))
        XCTAssertFalse(workspace.contains("Workspace.swift"))
    }

    func test_generate_includesManifests_noFilesExists() throws {
        // Given no manifest files exist
        // When generating the workspace
        // I do not expect Setup.swift or Workspace.swift to be added

        try subject.generate(path: path, graph: graph, options: GenerationOptions())

        let workspace = try readWorkspace(at: path)

        XCTAssertFalse(workspace.contains("Setup.swift"))
        XCTAssertFalse(workspace.contains("Workspace.swift"))
    }

    func test_generate_relativeToGroup() throws {
        try fileHandler.touch(path.appending(component: "Workspace.swift"))

        // Given the workspace manifest file exists
        // When generating the workspace
        // I expect the file to be relative to the workspace

        try subject.generate(path: path, graph: graph, options: GenerationOptions())

        let workspace = try readWorkspace(at: path)

        XCTAssertTrue(workspace.contains("location = \"group:Workspace.swift\">"))
    }

    func readWorkspace(at path: AbsolutePath) throws -> String {
        return try fileHandler.readTextFile(path.appending(component: "test.xcworkspace").appending(component: "contents.xcworkspacedata"))
    }
}
