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

        let cachePath: AbsolutePath = try temporaryPath()
        let fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        subject = ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cachePath,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileHandler: fileHandler
        )
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
}
