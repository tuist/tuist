#if canImport(TuistCloud)
    import Foundation
    import TSCBasic
    import TuistCloudTesting
    import TuistCore
    import TuistCoreTesting
    import TuistGraph
    import TuistGraphTesting
    import TuistLoader
    import TuistLoaderTesting
    import TuistSupport
    import XCTest

    @testable import TuistKit
    @testable import TuistSupportTesting

    final class CloudSessionServiceTests: TuistUnitTestCase {
        private var cloudSessionController: MockCloudSessionController!
        private var subject: CloudSessionService!
        private var configLoader: MockConfigLoader!
        private var cloudURL: URL!

        override func setUp() {
            super.setUp()
            cloudSessionController = MockCloudSessionController()
            configLoader = MockConfigLoader()
            cloudURL = URL(string: "https://test.cloud.tuist.io")!
            configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }
            subject = CloudSessionService(
                cloudSessionController: cloudSessionController,
                configLoader: configLoader
            )
        }

        override func tearDown() {
            cloudSessionController = nil
            configLoader = nil
            cloudURL = nil
            subject = nil
            super.tearDown()
        }

        func test_printSession() throws {
            // When
            try subject.printSession(directory: nil)

            // Then
            XCTAssertTrue(cloudSessionController.printSessionArgs.contains(cloudURL))
        }
    }
#endif
