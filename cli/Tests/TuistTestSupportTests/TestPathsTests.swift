import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
@testable import TuistTestSupport

struct TestPathsTests {
    @Test func environmentRootTakesPrecedence() throws {
        let root = try TestPaths.resolveRepositoryRoot(
            environment: ["TUIST_CONFIG_SRCROOT": "/relocated/checkout"],
            workingDirectory: AbsolutePath(validating: "/unrelated")
        )
        #expect(root.pathString == "/relocated/checkout")
    }

    @Test func invalidEnvironmentRootFails() throws {
        #expect(throws: (any Error).self) {
            try TestPaths.resolveRepositoryRoot(
                environment: ["TUIST_CONFIG_SRCROOT": "relative/checkout"],
                workingDirectory: AbsolutePath(validating: "/")
            )
        }
    }

    @Test(.inTemporaryDirectory) func discoversCheckoutFromNestedWorkingDirectory() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        try await FileSystem().makeDirectory(at: root.appending(components: "cli", "Tests", "Fixtures"))
        let nestedDirectory = root.appending(components: "cli", "Sources")
        try await FileSystem().makeDirectory(at: nestedDirectory)
        #expect(try TestPaths.resolveRepositoryRoot(environment: [:], workingDirectory: nestedDirectory) == root)
    }

    @Test(.inTemporaryDirectory) func missingCheckoutFails() throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        #expect(throws: TestPaths.ResolutionError.repositoryRootNotFound) {
            try TestPaths.resolveRepositoryRoot(environment: [:], workingDirectory: directory)
        }
    }

    @Test func mappedSnapshotsFollowRelocatedCheckout() throws {
        let directory = try TestPaths.snapshotDirectory(
            filePath: "/^src/cli/Tests/ExampleTests/Nested/ExampleTests.swift",
            repositoryRoot: AbsolutePath(validating: "/relocated/checkout")
        )
        #expect(directory.pathString == "/relocated/checkout/cli/Tests/ExampleTests/Nested/__Snapshots__/ExampleTests")
    }

    @Test(arguments: ["/checkout", "/^src-other"])
    func unmappedSnapshotsKeepTheirSourceLocation(root: String) throws {
        let directory = try TestPaths.snapshotDirectory(
            filePath: "\(root)/cli/Tests/ExampleTests.swift",
            repositoryRoot: AbsolutePath(validating: "/unrelated")
        )
        #expect(directory.pathString == "\(root)/cli/Tests/__Snapshots__/ExampleTests")
    }
}
