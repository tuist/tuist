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

    final class CloudAuthServiceTests: TuistUnitTestCase {
        var cloudSessionController: MockCloudSessionController!
        var subject: CloudAuthService!

        override func setUp() {
            super.setUp()
            cloudSessionController = MockCloudSessionController()
            subject = CloudAuthService(
                cloudSessionController: cloudSessionController
            )
        }

        override func tearDown() {
            cloudSessionController = nil
            subject = nil
            super.tearDown()
        }

        func test_authenticate() throws {
            // When
            try subject.authenticate(serverURL: nil)

            // Then
            XCTAssertTrue(
                cloudSessionController.authenticateArgs.contains(
                    URL(string: Constants.tuistCloudURL)!
                )
            )
        }
    }
#endif
