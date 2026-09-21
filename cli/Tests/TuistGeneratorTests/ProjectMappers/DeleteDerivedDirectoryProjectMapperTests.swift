import FileSystem
import FileSystemTesting
import Testing
import TuistConstants
import TuistCore
import XcodeGraph
@testable import TuistGenerator

struct DeleteDerivedDirectoryProjectMapperTests {
    @Test(.inTemporaryDirectory) func map_preservesGeneratedInputsDuringEarlyCleanup() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let derivedDirectory = projectPath.appending(component: Constants.DerivedDirectory.name)
        let fileSystem = FileSystem()
        let preservedDirectories = [
            Constants.DerivedDirectory.moduleMaps,
            Constants.DerivedDirectory.frameworkSearchPaths,
            Constants.DerivedDirectory.sources,
            Constants.DerivedDirectory.infoPlists,
            Constants.DerivedDirectory.entitlements,
        ]
        for directory in preservedDirectories {
            try await fileSystem.makeDirectory(at: derivedDirectory.appending(component: directory))
        }
        try await fileSystem.touch(derivedDirectory.appending(component: "TargetA.modulemap"))
        let obsoleteDirectory = derivedDirectory.appending(component: "Obsolete")
        try await fileSystem.makeDirectory(at: obsoleteDirectory)
        let obsoleteFile = derivedDirectory.appending(component: "obsolete.txt")
        try await fileSystem.touch(obsoleteFile)

        let (_, sideEffects) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))

        #expect(sideEffects.count == 2)
        #expect(sideEffects.contains(.directory(.init(path: obsoleteDirectory, state: .absent))))
        #expect(sideEffects.contains(.file(.init(path: obsoleteFile, state: .absent))))
    }

    @Test(.inTemporaryDirectory) func map_withoutDerivedDirectoryHasNoSideEffects() async throws {
        let projectPath = try #require(FileSystem.temporaryTestDirectory)

        let (_, sideEffects) = try await DeleteDerivedDirectoryProjectMapper().map(project: .test(path: projectPath))

        #expect(sideEffects.isEmpty)
    }
}
