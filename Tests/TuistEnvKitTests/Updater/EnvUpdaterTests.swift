import Foundation
import XCTest

@testable import TuistCoreTesting
@testable import TuistEnvKit

final class EnvUpdaterTests: TuistUnitTestCase {
    var githubClient: MockGitHubClient!
    var subject: EnvUpdater!

    override func setUp() {
        super.setUp()

        githubClient = MockGitHubClient()
        subject = EnvUpdater(githubClient: githubClient)
    }

    override func tearDown() {
        githubClient = nil
        subject = nil

        super.tearDown()
    }

    func test_update() throws {
        // Given
        let temporaryPath = try self.temporaryPath()
        let downloadURL = URL(string: "https://file.download.com/tuistenv.zip")!
        let release = Release.test(assets: [Release.Asset(downloadURL: downloadURL, name: "tuistenv.zip")])
        githubClient.releasesStub = { [release] }

        let downloadPath = temporaryPath.appending(component: "tuistenv.zip")
        system.succeedCommand(["/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, downloadURL.absoluteString])
        system.succeedCommand(["/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/"])
        system.succeedCommand(["/bin/chmod", "+x", "/tmp/tuistenv"])
        system.succeedCommand(["/bin/cp", "-rf", "/tmp/tuistenv", "/usr/local/bin/tuist"])
        system.succeedCommand(["/bin/rm", "/tmp/tuistenv"])

        // When
        try subject.update()
    }
}
