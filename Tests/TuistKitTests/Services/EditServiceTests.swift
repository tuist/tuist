import MockableTest
import Path
import TuistCore
import TuistLoader
import XcodeGraph
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistPluginTesting
@testable import TuistSupportTesting

final class EditServiceTests: XCTestCase {
    var subject: EditService!
    var opener: MockOpener!
    var configLoader: MockConfigLoading!
    var pluginService: MockPluginService!
    var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactoring!
    var projectEditor: MockProjectEditing!

    override func setUpWithError() throws {
        super.setUp()
        opener = MockOpener()
        configLoader = MockConfigLoading()
        pluginService = MockPluginService()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.default)

        let mockCacheDirectoriesProvider = MockCacheDirectoriesProviding()
        cacheDirectoriesProvider = mockCacheDirectoriesProvider

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.editProjects))
            .willReturn("/Users/tuist/cache/EditProjects")

        let cacheDirectoryProviderFactory = MockCacheDirectoriesProviderFactoring()
        cacheDirectoriesProviderFactory = cacheDirectoryProviderFactory
        given(cacheDirectoryProviderFactory)
            .cacheDirectories()
            .willReturn(mockCacheDirectoriesProvider)

        projectEditor = MockProjectEditing()

        subject = EditService(
            projectEditor: projectEditor,
            opener: opener,
            configLoader: configLoader,
            cacheDirectoryProviderFactory: cacheDirectoriesProviderFactory
        )
    }

    func test_edit_uses_caches_directory() async throws {
        let path: AbsolutePath = "/private/tmp"
        let cacheDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .editProjects)
        let projectDirectory = cacheDirectory.appending(component: path.pathString.md5)

        given(projectEditor!)
            .edit(at: .any, in: .any, onlyCurrentDirectory: .any, plugins: .any)
            .willReturn(projectDirectory)

        try await subject.run(
            path: path.pathString,
            permanent: false,
            onlyCurrentDirectory: false
        )

        let openArgs = try XCTUnwrap(opener.openArgs.first)
        XCTAssertEqual(opener.openCallCount, 1)
        XCTAssertEqual(openArgs.0, projectDirectory.pathString)

        verify(projectEditor)
            .edit(at: .value(path), in: .value(projectDirectory), onlyCurrentDirectory: .value(false), plugins: .any)
            .called(1)
    }

    func test_edit_permanent_does_not_open_workspace() async throws {
        let path: AbsolutePath = "/private/tmp"
        let cacheDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .editProjects)
        let projectDirectory = cacheDirectory.appending(component: path.pathString.md5)

        given(projectEditor!)
            .edit(at: .any, in: .any, onlyCurrentDirectory: .any, plugins: .any)
            .willReturn(projectDirectory)

        try await subject.run(
            path: path.pathString,
            permanent: true,
            onlyCurrentDirectory: true
        )

        XCTAssertEqual(opener.openCallCount, 0)

        verify(projectEditor)
            .edit(at: .value(path), in: .value(path), onlyCurrentDirectory: .value(true), plugins: .any)
            .called(1)
    }
}
