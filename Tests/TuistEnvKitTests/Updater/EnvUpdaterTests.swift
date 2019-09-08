import Foundation
import XCTest

@testable import TuistCoreTesting
@testable import TuistEnvKit

final class EnvUpdaterTests: XCTestCase {
    var system: MockSystem!
    var fileHandler: MockFileHandler!
    var githubClient: MockGitHubClient!
    var subject: EnvUpdater!

    override func setUp() {
        super.setUp()
        mockAllSystemInteractions()
        fileHandler = sharedMockFileHandler()

        system = MockSystem()
        githubClient = MockGitHubClient()
        subject = EnvUpdater(system: system, githubClient: githubClient)
    }

    func test_update() throws {
        // Given
        let downloadURL = URL(string: "https://file.download.com/tuistenv.zip")!
        let release = Release.test(assets: [Release.Asset(downloadURL: downloadURL,
                                                          name: "tuistenv.zip")])
        githubClient.releasesStub = { [release] }

        let downloadPath = fileHandler.currentPath.appending(component: "tuistenv.zip")
        system.succeedCommand(["/usr/bin/curl", "-LSs", "--output", downloadPath.pathString, downloadURL.absoluteString])
        system.succeedCommand(["/usr/bin/unzip", "-o", downloadPath.pathString, "-d", "/tmp/"])
        system.succeedCommand(["/bin/chmod", "+x", "/tmp/tuistenv"])
        system.succeedCommand(["/bin/cp", "-rf", "/tmp/tuistenv", "/usr/local/bin/tuist"])
        system.succeedCommand(["/bin/rm", "/tmp/tuistenv"])

        // When
        try subject.update()
    }
}
