import FileSystem
import FileSystemTesting
import Testing

@testable import TuistSupport

struct CacheWarmScratchDirectoryPreparerTests {
    private let fileSystem = FileSystem()

    @Test func prepareReturnsTemporaryModeWhenPathIsNil() async throws {
        #expect(try await subject.prepare(path: nil) == .temporary)
    }

    @Test(.inTemporaryDirectory) func prepareCreatesCallerOwnedDirectoryWhenItDoesNotExist() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryDirectory.appending(component: "cache-warm")

        #expect(try await subject.prepare(path: path) == .callerOwned(path))
        #expect(try await fileSystem.exists(path, isDirectory: true))
    }

    @Test(.inTemporaryDirectory) func prepareAcceptsEmptyCallerOwnedDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryDirectory.appending(component: "cache-warm")
        try await fileSystem.makeDirectory(at: path)

        #expect(try await subject.prepare(path: path) == .callerOwned(path))
    }

    @Test(.inTemporaryDirectory) func prepareRejectsFile() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryDirectory.appending(component: "cache-warm")
        try await fileSystem.touch(path)

        await #expect(throws: CacheWarmScratchDirectoryError.notDirectory(path)) {
            try await subject.prepare(path: path)
        }
    }

    @Test(.inTemporaryDirectory) func prepareRejectsNonEmptyDirectory() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let path = temporaryDirectory.appending(component: "cache-warm")
        try await fileSystem.makeDirectory(at: path)
        try await fileSystem.touch(path.appending(component: "existing"))

        await #expect(throws: CacheWarmScratchDirectoryError.notEmpty(path)) {
            try await subject.prepare(path: path)
        }
    }

    private var subject: CacheWarmScratchDirectoryPreparer {
        CacheWarmScratchDirectoryPreparer(fileSystem: fileSystem)
    }
}
