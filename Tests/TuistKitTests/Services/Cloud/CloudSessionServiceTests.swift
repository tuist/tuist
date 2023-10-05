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

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        subject = CloudSessionService(
            cloudSessionController: cloudSessionController
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        subject = nil
        super.tearDown()
    }

    func test_printSession() throws {
        // When
        try subject.printSession(serverURL: nil)

        // Then
        XCTAssertTrue(cloudSessionController.printSessionArgs.contains(URL(string: Constants.tuistCloudURL)!))
    }
}
#endif
