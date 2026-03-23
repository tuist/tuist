import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistSupport
import Testing
@testable import TuistEnvKit
@testable import TuistSupportTesting

struct InstalledVersionTests {
    @Test
    func test_description() {
        #expect(InstalledVersion.reference("ref").description == "ref")
        #expect(InstalledVersion.semver(Version("3.2.1")).description == "3.2.1")
    }
}

struct VersionsControllerTests {
    let subject: VersionsController
    init() {
        subject = VersionsController()
    }


    @Test
    func test_install() throws {
        try subject.install(version: "3.2.1") { path in
            let testPath = path.appending(component: "test")
            try Data().write(to: testPath.url)
        }

        let versionsPath = environment.versionsDirectory
        let testPath = versionsPath.appending(try RelativePath(validating: "3.2.1/test"))

        #expect(FileHandler.shared.exists(testPath))
    }

    @Test
    func test_path_for_version() {
        let got = subject.path(version: "ref")

        #expect(got == environment.versionsDirectory.appending(component: "ref"))
    }

    @Test
    func test_versions() throws {
        try FileHandler.shared.createFolder(environment.versionsDirectory.appending(component: "3.2.1"))
        try FileHandler.shared.createFolder(environment.versionsDirectory.appending(component: "ref"))

        let versions = subject.versions()

        #expect(versions.contains(.reference("ref")))
        #expect(versions.contains(.semver(Version("3.2.1"))))
    }

    @Test
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
        for version in versions {
            try fileHandler.createFolder(environment.versionsDirectory.appending(component: version))
        }

        // When
        let results = subject.semverVersions()

        // Then
        #expect(results == [
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
