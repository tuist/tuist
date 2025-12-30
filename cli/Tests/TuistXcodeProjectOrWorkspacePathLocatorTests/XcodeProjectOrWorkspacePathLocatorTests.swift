import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import TuistTesting

@testable import TuistXcodeProjectOrWorkspacePathLocator

struct XcodeProjectOrWorkspacePathLocatorTests {
    private let fileSystem = FileSystem()
    private let subject: XcodeProjectOrWorkspacePathLocator

    init() {
        subject = XcodeProjectOrWorkspacePathLocator(fileSystem: fileSystem)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_when_workspace_path_is_set() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspacePath = temporaryDirectory.appending(component: "project.xcworkspace")
        try await fileSystem.makeDirectory(at: workspacePath)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = workspacePath

        // When
        let result = try await subject.locate(from: temporaryDirectory.appending(component: "other"))

        // Then
        #expect(result == workspacePath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_when_workspace_path_is_xcodeproj_subdirectory() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let xcodeprojPath = temporaryDirectory.appending(component: "project.xcodeproj")
        let workspacePath = xcodeprojPath.appending(component: "project.xcworkspace")
        try await fileSystem.makeDirectory(at: workspacePath)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = workspacePath

        // When
        let result = try await subject.locate(from: temporaryDirectory.appending(component: "other"))

        // Then
        #expect(result == xcodeprojPath)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_finds_xcworkspace_when_no_workspace_path_set() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let expectedWorkspace = temporaryDirectory.appending(component: "MyApp.xcworkspace")
        try await fileSystem.makeDirectory(at: expectedWorkspace)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = nil

        // When
        let result = try await subject.locate(from: temporaryDirectory)

        // Then
        #expect(result == expectedWorkspace)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_finds_xcodeproj_when_no_workspace_found() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let expectedProject = temporaryDirectory.appending(component: "MyApp.xcodeproj")
        try await fileSystem.makeDirectory(at: expectedProject)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = nil

        // When
        let result = try await subject.locate(from: temporaryDirectory)

        // Then
        #expect(result == expectedProject)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_prefers_xcworkspace_over_xcodeproj() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspace = temporaryDirectory.appending(component: "MyApp.xcworkspace")
        let project = temporaryDirectory.appending(component: "MyApp.xcodeproj")
        try await fileSystem.makeDirectory(at: workspace)
        try await fileSystem.makeDirectory(at: project)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = nil

        // When
        let result = try await subject.locate(from: temporaryDirectory)

        // Then
        #expect(result == workspace)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func locate_throws_when_no_project_or_workspace_found() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let environment = try #require(Environment.mocked)
        environment.workspacePath = nil

        // When/Then
        await #expect(throws: XcodeProjectOrWorkspacePathLocatingError.xcodeProjectOrWorkspaceNotFound(temporaryDirectory)) {
            _ = try await subject.locate(from: temporaryDirectory)
        }
    }
}
