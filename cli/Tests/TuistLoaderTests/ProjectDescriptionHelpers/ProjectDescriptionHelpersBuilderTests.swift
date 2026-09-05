import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistSupport
import XCTest
@testable import TuistLoader
@testable import TuistTesting

final class ProjectDescriptionHelpersBuilderTests: TuistUnitTestCase {
    var projectDescriptionHelpersHasher: MockProjectDescriptionHelpersHasher!
    var resourceLocator: ResourceLocator!
    var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    var subject: ProjectDescriptionHelpersBuilder!
    var cachePath: AbsolutePath!
    var commandRunner: MockCommandRunner!

    override func setUpWithError() throws {
        super.setUp()
        commandRunner = MockCommandRunner()
        projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        resourceLocator = ResourceLocator()
        cachePath = try temporaryPath()
        try initSubject()
    }

    override func tearDown() {
        projectDescriptionHelpersHasher = nil
        helpersDirectoryLocator = nil
        resourceLocator = nil
        cachePath = nil
        commandRunner = nil
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

        commandRunner.defaultCaptureStubs = (nil, nil, 0)
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
        XCTAssertEqual(commandRunner.calls.count, 3)
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

        commandRunner.defaultCaptureStubs = (nil, nil, 0)
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

            try initSubject() // next iteration would be using a different subject, no runtime cache
            try await prepareProjectDescriptionHelpersCacheDirectory(for: path) // Creating the expected cache folder, next time
            // this
            // path is checked, no build action should be released
        }

        // Then
        XCTAssertEqual(commandRunner.calls.count, 3) // one per path
        XCTAssertEqual(allModules.uniqued().count, 3)
    }

    private func prepareProjectDescriptionHelpersCacheDirectory(for path: AbsolutePath) async throws {
        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let moduleCacheDirectory = cachePath.appending(component: hash)
        try await fileSystem.makeDirectory(at: moduleCacheDirectory)
    }

    @discardableResult
    private func initSubject() throws -> ProjectDescriptionHelpersBuilder {
        let subject = ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cachePath,
            helpersDirectoryLocator: helpersDirectoryLocator,
            commandRunner: commandRunner
        )
        self.subject = subject
        return subject
    }
}

struct ProjectDescriptionHelpersBuilderRecencyTests {
    private let fileSystem = FileSystem()
    private let projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
    private let helpersDirectoryLocator = MockHelpersDirectoryLocator()
    private let commandRunner = MockCommandRunner()

    @Test(.inTemporaryDirectory) func build_marksACachedModuleAsUsed() async throws {
        // Given
        let cacheDirectory = try #require(FileSystem.temporaryTestDirectory)
        let path: AbsolutePath = "/path/to/helpers/1"
        let searchPaths = try await ProjectDescriptionSearchPaths.paths(for: ResourceLocator().projectDescription())
        commandRunner.defaultCaptureStubs = (nil, nil, 0)
        projectDescriptionHelpersHasher.stubHash = { $0.basename }
        helpersDirectoryLocator.locateStub = path

        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let moduleCacheDirectory = cacheDirectory.appending(component: hash)
        try await fileSystem.makeDirectory(at: moduleCacheDirectory)
        let compiledAt = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: compiledAt],
            ofItemAtPath: moduleCacheDirectory.pathString
        )

        // When
        _ = try await ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cacheDirectory,
            helpersDirectoryLocator: helpersDirectoryLocator,
            commandRunner: commandRunner
        )
        .build(
            at: path,
            projectDescriptionSearchPaths: searchPaths,
            projectDescriptionHelperPlugins: []
        )

        // Then: a hit recompiles nothing, so without this the support-cache retention reads a module
        // every command uses as untouched since the day it was compiled, and evicts it first.
        #expect(commandRunner.calls.isEmpty)
        let lastUsed = try #require(try await fileSystem.fileMetadata(at: moduleCacheDirectory)?.lastModificationDate)
        #expect(lastUsed > compiledAt)
    }
}
