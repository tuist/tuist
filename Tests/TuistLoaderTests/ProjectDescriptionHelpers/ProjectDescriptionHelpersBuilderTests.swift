import FileSystem
import Path
import XCTest
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class ProjectDescriptionHelpersBuilderTests: TuistUnitTestCase {
    var projectDescriptionHelpersHasher: MockProjectDescriptionHelpersHasher!
    var resourceLocator: ResourceLocator!
    var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    var subject: ProjectDescriptionHelpersBuilder!

    override func setUpWithError() throws {
        super.setUp()
        projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        resourceLocator = ResourceLocator()

        try initSubject()
    }

    override func tearDown() {
        projectDescriptionHelpersHasher = nil
        helpersDirectoryLocator = nil
        resourceLocator = nil
        subject = nil
        super.tearDown()
    }

    func test_build_dylid_once_for_unique_path_when_built_many_times() async throws {
        // Given
        let paths: [AbsolutePath] = [
            "/path/to/helpers/1",
            "/path/to/helpers/2",
            "/path/to/helpers/3",
        ].flatMap { path in
            Array(repeating: path, count: 5)
        }
        .shuffled()

        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        system.defaultCaptureStubs = (nil, nil, 0)
        projectDescriptionHelpersHasher.stubHash = { $0.basename }

        // When
        var allModules: [ProjectDescriptionHelpersModule] = []

        for path in paths {
            helpersDirectoryLocator.locateStub = path
            let modules = try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
            allModules.append(contentsOf: modules)
        }

        // Then
        XCTAssertEqual(system.calls.count, 3)
        XCTAssertEqual(allModules.uniqued().count, 3)
    }

    func test_build_dylid_once_for_unique_path_when_built_many_times_when_new_builder_created_between_runs() async throws {
        // Given
        let paths: [AbsolutePath] = [
            "/path/to/helpers/1",
            "/path/to/helpers/2",
            "/path/to/helpers/3",
        ].flatMap { path in
            Array(repeating: path, count: 5)
        }
        .shuffled()

        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        system.defaultCaptureStubs = (nil, nil, 0)
        projectDescriptionHelpersHasher.stubHash = { $0.basename }

        // When
        var allModules: [ProjectDescriptionHelpersModule] = []
        let fileSystemMock = MockFileSystem()
        for path in paths {
            try initSubject(fileSystem: fileSystemMock) // next iteration would be using a different subject, no runtime cache
            helpersDirectoryLocator.locateStub = path
            let modules = try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
            allModules.append(contentsOf: modules)
        }

        // Then
        XCTAssertEqual(system.calls.count, 0) // system call should not happen because we have the module pre-built alraedy
        XCTAssertEqual(allModules.uniqued().count, 3)
    }

    @discardableResult
    private func initSubject(fileSystem: FileSysteming = FileSystem()) throws -> ProjectDescriptionHelpersBuilder {
        let cachePath: AbsolutePath = try temporaryPath()
        let fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        let subject = ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cachePath,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileHandler: fileHandler,
            fileSystem: fileSystem
        )
        self.subject = subject
        return subject
    }
}

private class MockFileSystem: FileSysteming {
    var existsResults: Set<Path.AbsolutePath> = []
    var existsCounter: Int = 0
    func exists(_ path: Path.AbsolutePath) async throws -> Bool {
        return try await exists(path, isDirectory: false)
    }

    func exists(_: Path.AbsolutePath, isDirectory _: Bool) async throws -> Bool {
        existsCounter += 1
        return true
    }

    // No-Op
    func runInTemporaryDirectory<T>(
        prefix _: String,
        _: @Sendable (Path.AbsolutePath) async throws -> T
    ) async throws -> T { throw NSError(
        domain: "",
        code: 0
    ) }
    func touch(_: Path.AbsolutePath) async throws {}
    func remove(_: Path.AbsolutePath) async throws {}
    func remove(_: Path.AbsolutePath, recursively _: Bool) async throws {}
    func makeTemporaryDirectory(prefix _: String) async throws -> Path.AbsolutePath { throw NSError(domain: "", code: 0) }
    func move(from _: Path.AbsolutePath, to _: Path.AbsolutePath) async throws {}
    func move(from _: Path.AbsolutePath, to _: Path.AbsolutePath, options _: [MoveOptions]) async throws {}
    func makeDirectory(at _: Path.AbsolutePath) async throws {}
    func makeDirectory(at _: Path.AbsolutePath, options _: [MakeDirectoryOptions]) async throws {}
    func readFile(at _: Path.AbsolutePath) async throws -> Data { throw NSError(domain: "", code: 0) }
    func readTextFile(at _: Path.AbsolutePath) async throws -> String { "" }
    func readTextFile(at _: Path.AbsolutePath, encoding _: String.Encoding) async throws -> String { "" }
    func writeText(_: String, at _: Path.AbsolutePath) async throws {}
    func writeText(_: String, at _: Path.AbsolutePath, encoding _: String.Encoding) async throws {}
    func readPlistFile<T>(at _: Path.AbsolutePath) async throws -> T where T: Decodable { throw NSError(domain: "", code: 0) }
    func readPlistFile<T>(at _: Path.AbsolutePath, decoder _: PropertyListDecoder) async throws -> T
        where T: Decodable
    { throw NSError(
        domain: "",
        code: 0
    ) }
    func writeAsPlist(_: some Encodable, at _: Path.AbsolutePath) async throws { throw NSError(domain: "", code: 0) }
    func writeAsPlist(_: some Encodable, at _: Path.AbsolutePath, encoder _: PropertyListEncoder) async throws { throw NSError(
        domain: "",
        code: 0
    ) }
    func readJSONFile<T>(at _: Path.AbsolutePath) async throws -> T where T: Decodable { throw NSError(domain: "", code: 0) }
    func readJSONFile<T>(at _: Path.AbsolutePath, decoder _: JSONDecoder) async throws -> T where T: Decodable { throw NSError(
        domain: "",
        code: 0
    ) }
    func writeAsJSON(_: some Encodable, at _: Path.AbsolutePath) async throws {}
    func writeAsJSON(_: some Encodable, at _: Path.AbsolutePath, encoder _: JSONEncoder) async throws {}
    func fileSizeInBytes(at _: Path.AbsolutePath) async throws -> Int64? { nil }
    func replace(_: Path.AbsolutePath, with _: Path.AbsolutePath) async throws {}
    func copy(_: Path.AbsolutePath, to _: Path.AbsolutePath) async throws {}
    func locateTraversingUp(from _: Path.AbsolutePath, relativePath _: Path.RelativePath) async throws -> Path
        .AbsolutePath?
    { throw NSError(
        domain: "",
        code: 0
    ) }
    func createSymbolicLink(from _: Path.AbsolutePath, to _: Path.AbsolutePath) async throws {}
    func resolveSymbolicLink(_: Path.AbsolutePath) async throws -> Path.AbsolutePath { throw NSError(domain: "", code: 0) }
    func zipFileOrDirectoryContent(at _: Path.AbsolutePath, to _: Path.AbsolutePath) async throws {}
    func unzip(_: Path.AbsolutePath, to _: Path.AbsolutePath) async throws {}
    func glob(
        directory _: Path.AbsolutePath,
        include _: [String]
    ) throws -> AnyThrowingAsyncSequenceable<Path.AbsolutePath> {
        throw NSError(
            domain: "",
            code: 0
        )
    }

    func currentWorkingDirectory() async throws -> Path.AbsolutePath { throw NSError(domain: "", code: 0) }
}
