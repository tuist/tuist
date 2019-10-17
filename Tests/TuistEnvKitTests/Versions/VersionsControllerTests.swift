import Basic
import Foundation
import SPMUtility
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistEnvKit

final class InstalledVersionTests: XCTestCase {
    func test_description() {
        XCTAssertEqual(InstalledVersion.reference("ref").description, "ref")
        XCTAssertEqual(InstalledVersion.semver(Version(string: "3.2.1")!).description, "3.2.1")
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
        XCTAssertTrue(versions.contains(.semver(Version(string: "3.2.1")!)))
    }
}
