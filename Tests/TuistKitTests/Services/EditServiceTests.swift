import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import XcodeProj
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistLoaderTesting
@testable import TuistSupportTesting
@testable import TuistPluginTesting



final class EditServiceTests: XCTestCase {
    var subject: EditService!
    var opener: MockOpener!
    var configLoader: MockConfigLoader!
    var pluginService: MockPluginService!
    var signalHandler: MockSignalHandler!
    var cacheDirectoriesProvider: MockCacheDirectoriesProvider!
    var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactory!
    var projectEditor: MockProjectEditor!

    override func setUpWithError() throws {
        super.setUp()
        opener = MockOpener()
        configLoader = MockConfigLoader()
        pluginService = MockPluginService()
        signalHandler = MockSignalHandler()
        cacheDirectoriesProvider = try MockCacheDirectoriesProvider()
        cacheDirectoriesProviderFactory = MockCacheDirectoriesProviderFactory(provider: cacheDirectoriesProvider)
        projectEditor = MockProjectEditor()

        subject = EditService(projectEditor: projectEditor,
                              opener: opener,
                              configLoader: configLoader,
                              pluginService: pluginService,
                              signalHandler: signalHandler,
                              cacheDirectoryProviderFactory: cacheDirectoriesProviderFactory)
    }
    
    func test_edit_uses_caches_directory() async throws {
        try await subject.run(path: "/private/tmp",
                              permanent: false,
                              onlyCurrentDirectory: false)
        
        
        let cacheDirectory = try cacheDirectoriesProvider.tuistCacheDirectory(for: .editProjects)
        let projectDirectory = cacheDirectory.appending(component: "/private/tmp".md5)
        let openArgs = try XCTUnwrap(opener.openArgs.first)
        
        XCTAssertEqual(opener.openCallCount, 1)
        XCTAssertEqual(openArgs.0, projectDirectory.pathString)
        XCTAssertEqual(projectEditor.editingPath, "/private/tmp")
        XCTAssertEqual(projectEditor.onlyCurrentDirectory, false)
        XCTAssertEqual(projectEditor.destinationDirectory, projectDirectory)
    }
    
    
    func test_edit_permanent_does_not_open_workspace() async throws {
        try await subject.run(path: "/private/tmp",
                              permanent: true,
                              onlyCurrentDirectory: true)
        
        XCTAssertEqual(opener.openCallCount, 0)
        XCTAssertEqual(projectEditor.editingPath, "/private/tmp")
        XCTAssertEqual(projectEditor.destinationDirectory, "/private/tmp")
        XCTAssertEqual(projectEditor.onlyCurrentDirectory, true)
    }
}
