import Testing
import Path
import FileSystem
import Foundation

@testable import TuistWorkflows

struct WorkflowsLoaderTests {
    let fileSystem: FileSystem
    let subject: WorkflowsLoader
    
    init() {
        self.fileSystem = FileSystem()
        self.subject = WorkflowsLoader(fileSystem: fileSystem)
    }
    
    @Test func test_load_loadsAllWorkflowsFromWorkflowsDirectory() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let workflowsDirectory = temporaryDirectory
            let buildWorkflowPath = workflowsDirectory.appending(component: "build.swift")
            try await fileSystem.touch(buildWorkflowPath)
            let testWorkflowPath = workflowsDirectory.appending(component: "test.swift")
            try await fileSystem.touch(testWorkflowPath)
            
            // When
            let workflows = try await subject.load(workflowsDirectory: workflowsDirectory).sorted()
            
            // Then
            #expect(workflows == [
                Workflow(path: buildWorkflowPath, name: buildWorkflowPath.basename.replacing(".swift", with: "")),
                Workflow(path: testWorkflowPath, name: testWorkflowPath.basename.replacing(".swift", with: ""))
            ])
        }
    }
}
