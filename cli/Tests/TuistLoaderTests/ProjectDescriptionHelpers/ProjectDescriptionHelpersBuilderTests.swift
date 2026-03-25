import FileSystem
import FileSystemTesting
import Path
import Testing
import TuistSupport
@testable import TuistLoader
@testable import TuistTesting

@Suite(.withMockedDependencies()) struct ProjectDescriptionHelpersBuilderTests {
    private var projectDescriptionHelpersHasher: MockProjectDescriptionHelpersHasher
    private let resourceLocator: ResourceLocator
    private var helpersDirectoryLocator: MockHelpersDirectoryLocator
    private var subject: ProjectDescriptionHelpersBuilder
    private let cachePath: AbsolutePath
    private let system = MockSystem()

    init() throws {
        let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
        projectDescriptionHelpersHasher = MockProjectDescriptionHelpersHasher()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        resourceLocator = ResourceLocator()
        cachePath = temporaryPath
        subject = ProjectDescriptionHelpersBuilder(
            projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
            cacheDirectory: cachePath,
            helpersDirectoryLocator: helpersDirectoryLocator,
            fileHandler: FileHandler.shared
        )
    }

    @Test(.inTemporaryDirectory) func build_dylid_once_for_unique_path_when_built_many_times() async throws {
        let paths: [AbsolutePath] = [
            "/path/to/helpers/1", "/path/to/helpers/2", "/path/to/helpers/3",
        ].flatMap { path in Array(repeating: path, count: 5) }.shuffled()

        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        system.defaultCaptureStubs = (nil, nil, 0)
        projectDescriptionHelpersHasher.stubHash = { $0.basename }

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

        #expect(system.calls.count == 3)
        #expect(allModules.uniqued().count == 3)
    }

    @Test(.inTemporaryDirectory) func build_dylid_once_for_unique_path_when_built_many_times_when_new_builder_created_between_runs(
    ) async throws {
        let paths: [AbsolutePath] = [
            "/path/to/helpers/1", "/path/to/helpers/2", "/path/to/helpers/3",
        ].flatMap { path in Array(repeating: path, count: 5) }.shuffled()

        let projectDescriptionPath = try await resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        system.defaultCaptureStubs = (nil, nil, 0)
        projectDescriptionHelpersHasher.stubHash = { $0.basename }

        var allModules: [ProjectDescriptionHelpersModule] = []
        var currentSubject = subject
        for path in paths {
            helpersDirectoryLocator.locateStub = path
            let modules = try await currentSubject.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                projectDescriptionHelperPlugins: []
            )
            allModules.append(contentsOf: modules)

            currentSubject = ProjectDescriptionHelpersBuilder(
                projectDescriptionHelpersHasher: projectDescriptionHelpersHasher,
                cacheDirectory: cachePath,
                helpersDirectoryLocator: helpersDirectoryLocator,
                fileHandler: FileHandler.shared
            )
            try prepareProjectDescriptionHelpersCacheDirectory(for: path)
        }

        #expect(system.calls.count == 3)
        #expect(allModules.uniqued().count == 3)
    }

    private func prepareProjectDescriptionHelpersCacheDirectory(for path: AbsolutePath) throws {
        let hash = try projectDescriptionHelpersHasher.hash(helpersDirectory: path)
        let moduleCacheDirectory = cachePath.appending(component: hash)
        try FileHandler.shared.createFolder(moduleCacheDirectory)
    }
}
