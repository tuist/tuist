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

    func test_latest_remote_version() throws {
        gitHandler.remoteTaggedVersionsStub = ["1.9.0", "2.0.0", "2.0.1"]
        let highestRemoteVersion = try subject.latestVersion()

        XCTAssertEqual(highestRemoteVersion, "2.0.1")
    }

    func test_versions() throws {
        gitHandler.remoteTaggedVersionsStub = ["1.9.0", "2.0.0", "2.0.1"]
        let versions = try subject.versions()

        XCTAssertEqual(versions, ["1.9.0", "2.0.0", "2.0.1"])
    }

    func test_error() throws {
        gitHandler.remoteTaggedVersionsStub = []

        XCTAssertEmpty(try subject.versions())
        XCTAssertNil(try subject.latestVersion())
    }
}
