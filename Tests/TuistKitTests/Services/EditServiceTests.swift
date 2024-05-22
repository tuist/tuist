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
    var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactory!
    var projectEditor: MockProjectEditor!

    override func setUpWithError() throws {
        super.setUp()
        opener = MockOpener()
        configLoader = MockConfigLoader()
        pluginService = MockPluginService()
        signalHandler = MockSignalHandler()
        cacheDirectoriesProviderFactory = MockCacheDirectoriesProviderFactory(provider:  try MockCacheDirectoriesProvider())
        projectEditor = MockProjectEditor()

        subject = EditService(projectEditor: projectEditor,
                              opener: opener,
                              configLoader: configLoader,
                              pluginService: pluginService,
                              signalHandler: signalHandler,
                              cacheDirectoryProviderFactory: cacheDirectoriesProviderFactory)
    }
    
}
