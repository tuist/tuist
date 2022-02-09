import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistSupport
import XCTest
@testable import TuistEnvKit
@testable import TuistSupportTesting

final class InstalledVersionTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InstalledVersion.reference("ref").description, "ref")
        XCTAssertEqual(InstalledVersion.semver(Version("3.2.1")).description, "3.2.1")
    }
}

final class VersionsControllerTests: TuistUnitTestCase {
    var subject: VersionsController!

    override func setUp() {
        super.setUp()
        subject = VersionsController()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_install() throws {
        try subject.install(version: "3.2.1") { path in
            let testPath = path.appending(component: "test")
            try Data().write(to: testPath.url)
        }

        let versionsPath = environment.versionsDirectory
        let testPath = versionsPath.appending(RelativePath("3.2.1/test"))

        XCTAssertTrue(FileHandler.shared.exists(testPath))
    }

    func test_path_for_version() {
        let got = subject.path(version: "ref")

        XCTAssertEqual(got, environment.versionsDirectory.appending(component: "ref"))
    }

    func test_versions() throws {
        try FileHandler.shared.createFolder(environment.versionsDirectory.appending(component: "3.2.1"))
        try FileHandler.shared.createFolder(environment.versionsDirectory.appending(component: "ref"))

        let versions = subject.versions()

        XCTAssertTrue(versions.contains(.reference("ref")))
        XCTAssertTrue(versions.contains(.semver(Version("3.2.1"))))
    }

    func test_semverVersions_ordered() throws {
        // Given
        let versions = [
            "0.12.0",
            "0.12.12",
            "0.12.9",
            "0.9.0",
            "1.0.0",
            "1.12.0",
            "1.9.0",
            "12.2.0",
            "2.18.0",
        ]
        try versions.forEach {
            try fileHandler.createFolder(environment.versionsDirectory.appending(component: $0))
        }

        // When
        let results = subject.semverVersions()

        // Then
        XCTAssertEqual(results, [
            Version(0, 9, 0),
            Version(0, 12, 0),
            Version(0, 12, 9),
            Version(0, 12, 12),
            Version(1, 0, 0),
            Version(1, 9, 0),
            Version(1, 12, 0),
            Version(2, 18, 0),
            Version(12, 2, 0),
        ])
    }
}
