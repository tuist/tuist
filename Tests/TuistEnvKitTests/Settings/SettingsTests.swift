import Foundation
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class SettingsTests: TuistUnitTestCase {
    var gitHandler: MockGitHandler!
    var subject: VersionProvider!

    override func setUp() {
        super.setUp()

        gitHandler = MockGitHandler()
        subject = VersionProvider(gitHandler: gitHandler)
    }

    override func tearDown() {
        gitHandler = nil
        subject = nil

        super.tearDown()
    }

    func test_highest_remote_version() throws {
        gitHandler.lsremoteStub = """
         4e4230bb95e1c57e82a1e5f9b4c79486fc2543fb    refs/tags/1.9.0
         5e17254d4a3c14454ecab6575b4a44d6685d3865    refs/tags/2.0.0
         8435101aa093de2189c5ab03e63b9e6e3543b1d6    refs/tags/2.0.1
        """
        let highestRemoteVersion = try subject.latestVersion().toBlocking().first

        XCTAssertEqual(highestRemoteVersion, "2.0.1")
    }

    func test_versions() throws {
        gitHandler.lsremoteStub = """
         4e4230bb95e1c57e82a1e5f9b4c79486fc2543fb    refs/tags/1.9.0
         5e17254d4a3c14454ecab6575b4a44d6685d3865    refs/tags/2.0.0
         8435101aa093de2189c5ab03e63b9e6e3543b1d6    refs/tags/2.0.1
        """
        let versions = try subject.versions().toBlocking().first

        XCTAssertEqual(versions, ["1.9.0", "2.0.0", "2.0.1"])
    }

    func test_error() throws {
        gitHandler.lsremoteStub = ""
        do {
            _ = try subject.latestVersion().toBlocking().first
            XCTFail()
        } catch let error as VersionProviderError {
            XCTAssertEqual(error.description, "Error fetching versions from GitHub.")
        } catch {
            XCTFail()
        }
    }
}
