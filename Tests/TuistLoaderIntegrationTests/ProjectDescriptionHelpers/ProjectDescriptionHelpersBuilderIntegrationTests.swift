import FileSystem
import Foundation
import Path
import TuistCore
import XCTest

@testable import TuistLoader
@testable import TuistSupport
@testable import TuistSupportTesting

final class ProjectDescriptionHelpersBuilderIntegrationTests: TuistTestCase {
    private var subject: ProjectDescriptionHelpersBuilder!
    private var resourceLocator: ResourceLocator!
    private var helpersDirectoryLocator: HelpersDirectoryLocating!
    private var fileSystem: FileSysteming!

    override func setUp() {
        super.setUp()
        resourceLocator = ResourceLocator()
        helpersDirectoryLocator = HelpersDirectoryLocator(rootDirectoryLocator: RootDirectoryLocator())
        fileSystem = FileSystem()
    }

    override func tearDown() {
        subject = nil
        resourceLocator = nil
        helpersDirectoryLocator = nil
        fileSystem = nil
        super.tearDown()
    }

    func test_build_only_once_even_with_different_subjects() async throws {
        // Given
        let path = try temporaryPath()
        let helpersPath = path
            .appending(try RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPath.appending(component: "Helper.swift"),
            atomically: true
        )

        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        let fileSystem = MockFileSystem()
        let hash = try await ProjectDescriptionHelpersHasher().hash(helpersDirectory: path)
        let moduleCacheDirectory = path.appending(component: hash)
        let dylibName = "lib\(ProjectDescriptionHelpersBuilder.defaultHelpersName).dylib"
        let modulePath = moduleCacheDirectory.appending(component: dylibName)
        fileSystem.existsResults.insert(modulePath)
        let fileHandler = MockFileHandling()

        // When
        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            let subject = ProjectDescriptionHelpersBuilder(
                cacheDirectory: path,
                helpersDirectoryLocator: self.helpersDirectoryLocator,
                fileHandler: fileHandler,
                fileSystem: fileSystem
            )
            return try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertEqual(fileSystem.existsCounter, 3)
        XCTAssertEqual(fileHandler.createFolderCount, 0) // should not avoid creating a folder
    }

    func test_build_when_the_helpers_is_a_dylib() async throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(
            cacheDirectory: path,
            helpersDirectoryLocator: helpersDirectoryLocator
        )
        let helpersPath = path
            .appending(try RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Constants.helpersDirectoryName)"))
        try FileHandler.shared.createFolder(path.appending(component: Constants.tuistDirectoryName))
        try FileHandler.shared.createFolder(helpersPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPath.appending(component: "Helper.swift"),
            atomically: true
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        // When
        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await self.subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/ProjectDescriptionHelpers.swiftmodule"])
            .collect().first
        XCTAssertNotNil(swiftModule)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libProjectDescriptionHelpers.dylib"]).collect().first
        XCTAssertNotNil(dylib)
        let swiftdoc = try await fileSystem.glob(directory: path, include: ["*/ProjectDescriptionHelpers.swiftdoc"]).collect()
            .first
        XCTAssertNotNil(swiftdoc)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        XCTAssertTrue(exists)
    }

    func test_build_when_the_helpers_is_a_plugin() async throws {
        // Given
        let path = try temporaryPath()
        subject = ProjectDescriptionHelpersBuilder(cacheDirectory: path, helpersDirectoryLocator: helpersDirectoryLocator)

        let helpersPluginPath = path.appending(components: "Plugin", Constants.helpersDirectoryName)
        try FileHandler.shared.createFolder(path.appending(component: "Plugin"))
        try FileHandler.shared.createFolder(helpersPluginPath)
        try FileHandler.shared.write(
            "import Foundation; class Test {}",
            path: helpersPluginPath.appending(component: "Helper.swift"),
            atomically: true
        )
        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        let plugins = [ProjectDescriptionHelpersPlugin(name: "Plugin", path: helpersPluginPath, location: .local)]

        // When
        let paths = try await Array(0 ..< 3).concurrentMap { _ in
            try await self.subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: plugins
            )
        }

        // Then
        XCTAssertEqual(Set(paths).count, 1)
        let swiftSourceInfo = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftsourceinfo"]).collect().first
        XCTAssertNotNil(swiftSourceInfo)
        let swiftModule = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftmodule"]).collect().first
        XCTAssertNotNil(swiftModule)
        let dylib = try await fileSystem.glob(directory: path, include: ["*/libPlugin.dylib"]).collect().first
        XCTAssertNotNil(dylib)
        let swiftDoc = try await fileSystem.glob(directory: path, include: ["*/Plugin.swiftdoc"]).collect().first
        XCTAssertNotNil(swiftDoc)
        let helpersModule = try XCTUnwrap(paths.first?.first)
        let exists = try await fileSystem.exists(helpersModule.path)
        XCTAssertTrue(exists)
    }
}

private class MockFileHandling: FileHandler {
    var createFolderCount = 0
    override public func createFolder(_: Path.AbsolutePath) throws {
        createFolderCount += 1
    }
}

private class MockFileSystem: FileSysteming {
    var existsResults: Set<Path.AbsolutePath> = []
    var existsCounter: Int = 0
    func exists(_ path: Path.AbsolutePath) async throws -> Bool {
        return try await exists(path, isDirectory: false)
    }

    func exists(_ path: Path.AbsolutePath, isDirectory _: Bool) async throws -> Bool {
        existsCounter += 1
        return existsResults.contains(path)
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
    ) throws -> AnyThrowingAsyncSequenceable<Path.AbsolutePath> { throw NSError(
        domain: "",
        code: 0
    ) }
    func currentWorkingDirectory() async throws -> Path.AbsolutePath { throw NSError(domain: "", code: 0) }
}
