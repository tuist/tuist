import Foundation
import TSCBasic
import XCTest

@testable import TuistEnvKit
@testable import TuistSupportTesting

final class EnvUpdaterTests: TuistUnitTestCase {
    var googleCloudStorageClient: MockGoogleCloudStorageClient!
    var subject: EnvUpdater!

    override func setUp() {
        super.setUp()

        googleCloudStorageClient = MockGoogleCloudStorageClient()
        subject = EnvUpdater(googleCloudStorageClient: googleCloudStorageClient)
    }

    override func tearDown() {
        googleCloudStorageClient = nil
        subject = nil

        super.tearDown()
    }

    func test_update() throws {
        // Given
        let installScriptPath = AbsolutePath(#file.replacingOccurrences(of: "file://", with: ""))
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .removingLastComponent()
            .appending(RelativePath("script/install"))
        system.succeedCommand([installScriptPath.pathString])

        // When
        try subject.update()
    }
}
