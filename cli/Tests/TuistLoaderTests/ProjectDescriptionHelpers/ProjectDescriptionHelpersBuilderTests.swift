import Path
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

    override func setUpWithError() throws {
        super.setUp()
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
        for path in paths {
            helpersDirectoryLocator.locateStub = path
            let modules = try await subject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
            allModules.append(contentsOf: modules)

            try initSubject() // next iteration would be using a different subject, no runtime cache
            try prepareProjectDescriptionHelpersCacheDirectory(for: path) // Creating the expected cache folder, next time this
            // path is checked, no build action should be released
        }

        // Then
        XCTAssertEqual(system.calls.count, 3) // one per path
        XCTAssertEqual(allModules.uniqued().count, 3)
    }

    private func prepareProjectDescriptionHelpersCacheDirectory(for path: AbsolutePath) throws {
        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let moduleCacheDirectory = cachePath.appending(component: hash)
        try fileHandler.createFolder(moduleCacheDirectory)
    }

    @discardableResult
    private func initSubject() throws -> ProjectDescriptionHelpersBuilder {
        let subject = ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cachePath,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileHandler: fileHandler // from parent -> parent test case object
        )
        self.subject = subject
        return subject
    }
}
