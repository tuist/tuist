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
            cache.add(project: project)

            graph = Graph.test(entryPath: path, cache: cache)

        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    func test_generate_includesManifestFiles() throws {
        
        // Given Workspace.swift and Setup.swift exist
        // When generating the workspace
        // And they are included through additional files
        // I expect both files to be added to the workspace

        let workspace = WorkspaceStructure(name: "test", contents: [
            .file(path: path.appending(component: "Workspace.swift")),
            .file(path: path.appending(component: "Setup.swift"))
        ])
        
        try subject.generate(workspace: workspace, path: path, graph: graph, options: GenerationOptions())
        
        let xcworkspace = try XCWorkspace(path.appending(component: "\(workspace.name).xcworkspace"))
        
        XCTAssertTrue(xcworkspace.data.children.contains(.file(.init(location: .group("Setup.swift")))))
        XCTAssertTrue(xcworkspace.data.children.contains(.file(.init(location: .group("Workspace.swift")))))
        
    }
    
    func test_generate_documentationFolderReference() throws {
        
        // Given a Documentation folder exists
        // When generating the workspace
        // I expect the folder to be added as a folder reference
        
        try fileHandler.touch(path.appending(component: "Documentation").appending(component: "1.md"))
        try fileHandler.touch(path.appending(component: "Documentation").appending(component: "2.md"))
        
        let workspace = WorkspaceStructure(name: "test", contents: [
            .folderReference(path: path.appending(component: "Documentation"))
        ])
        
        try subject.generate(workspace: workspace, path: path, graph: graph, options: GenerationOptions())
        
        let xcworkspace = try XCWorkspace(path.appending(component: "\(workspace.name).xcworkspace"))
        
        XCTAssertTrue(xcworkspace.data.children.contains(.file(.init(location: .group("Documentation")))))
        
    }
    
//
//        try fileHandler.touch(path.appending(component: "Workspace.swift"))
//        try fileHandler.touch(path.appending(component: "Setup.swift"))
//        try fileHandler.touch(path.appending(component: "Project.swift"))
//
//        let testWorkspace = Workspace.test(name: "test", contents: [
//            .file(path: path.appending(component: "Workspace.swift")),
//            .file(path: path.appending(component: "Setup.swift")),
//            .project(path: path),
//        ])
//
//        try subject.generate(workspace: testWorkspace, path: path, graph: graph, options: GenerationOptions())
//
//        let workspace = try readWorkspace(at: path)
//
//        XCTAssertTrue(workspace.contains("Setup.swift"))
//        XCTAssertTrue(workspace.contains("Workspace.swift"))
//    }
//
//    func test_generate_includesManifests_oneFilesExists() throws {
//        // Given only Setup.swift is available
//        // When generating the workspace
//        // I expect Setup.swift to be added to the workspace and Workspace.swift to not be added
//
//        try fileHandler.touch(path.appending(component: "Setup.swift"))
//        try fileHandler.touch(path.appending(component: "Project.swift"))
//
//        let testWorkspace = Workspace.test(name: "test", contents: [
//            .file(path: path.appending(component: "Setup.swift")),
//            .project(path: path),
//        ])
//
//        try subject.generate(workspace: testWorkspace, path: path, graph: graph, options: GenerationOptions())
//
//        let workspace = try readWorkspace(at: path)
//
//        XCTAssertTrue(workspace.contains("Setup.swift"))
//        XCTAssertFalse(workspace.contains("Workspace.swift"))
//    }
//
//    func test_generate_includesManifests_noFilesExists() throws {
//        // Given no manifest files exist
//        // When generating the workspace
//        // I do not expect Setup.swift or Workspace.swift to be added
//
//        try fileHandler.touch(path.appending(component: "Project.swift"))
//
//        let testWorkspace = Workspace.test(name: "test", contents: [
//            .project(path: path),
//        ])
//
//        try subject.generate(workspace: testWorkspace, path: path, graph: graph, options: GenerationOptions())
//
//        let workspace = try readWorkspace(at: path)
//
//        XCTAssertFalse(workspace.contains("Setup.swift"))
//        XCTAssertFalse(workspace.contains("Workspace.swift"))
//    }
//
//    func test_generate_relativeToGroup() throws {
//        // Given the workspace manifest file exists
//        // When generating the workspace
//        // I expect the file to be relative to the workspace
//
//        try fileHandler.touch(path.appending(component: "Workspace.swift"))
//        try fileHandler.touch(path.appending(component: "Project.swift"))
//
//        let testWorkspace = Workspace.test(name: "test", contents: [
//            .file(path: path.appending(component: "Workspace.swift")),
//            .file(path: path.appending(component: "Setup.swift")),
//            .project(path: path),
//        ])
//
//        try subject.generate(workspace: testWorkspace, path: path, graph: graph, options: GenerationOptions())
//
//        let workspace = try readWorkspace(at: path)
//
//        XCTAssertTrue(workspace.contains("location = \"group:Workspace.swift\">"))
//    }
//
//    func test_generate_withNestedGroups() throws {
//        // Given the workspace specifies groups
//        // When generating the workspace
//        // I expect the nested groups to be in the correct order (Outer -> Inner -> Project)
//
//        let testWorkspace = Workspace.test(name: "test", contents: [
//            .group(name: "Outer", contents: [.group(name: "Inner", contents: [.project(path: path)])]),
//        ])
//
//        try fileHandler.touch(path.appending(component: "Workspace.swift"))
//        try fileHandler.touch(path.appending(component: "Project.swift"))
//
//        try subject.generate(workspace: testWorkspace, path: path, graph: graph, options: GenerationOptions())
//
//        let workspace = try readWorkspace(at: path)
//
//        XCTAssertTrue(workspace.contains("<Group\n      location = \"container:\"\n      name = \"Outer\">\n      <Group\n         location = \"container:\"\n         name = \"Inner\">\n         <FileRef\n            location = \"group:Project.xcodeproj\">"))
//    }
//
//    func readWorkspace(at path: AbsolutePath) throws -> XCWorkspace {
//        XCWorkspace(path: path)
//        return try fileHandler.readTextFile(path.appending(component: "test.xcworkspace").appending(component: "contents.xcworkspacedata"))
//    }
}

extension XCWorkspace {
    
    convenience init(_ path: AbsolutePath) throws {
        try self.init(pathString: path.asString)
    }
    
}
