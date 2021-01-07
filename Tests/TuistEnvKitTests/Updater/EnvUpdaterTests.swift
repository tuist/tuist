import Foundation
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
        let temporaryPath = try self.temporaryPath()
        let downloadURL = URL(string: "https://file.download.com/tuistenv.zip")!
        googleCloudStorageClient.latestTuistEnvBundleURLStub = downloadURL
        let downloadPath = temporaryPath.appending(component: "tuistenv.zip")
        system.succeedCommand(["/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, downloadURL.absoluteString])
        system.succeedCommand(["/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/"])
        system.succeedCommand(["/bin/chmod", "+x", "/tmp/tuistenv"])
        system.succeedCommand(["/bin/cp", "-rf", "/tmp/tuistenv", "/usr/local/bin/tuist"])
        system.succeedCommand(["/bin/ln", "-sf", "/usr/local/bin/tuist", "/usr/local/bin/swift-project"])
        system.succeedCommand(["/bin/rm", "/tmp/tuistenv"])

        // When
        try subject.update()
    }
}
